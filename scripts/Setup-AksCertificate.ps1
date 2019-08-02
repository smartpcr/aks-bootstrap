
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "taufiq"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envRootFolder = Join-Path $gitRootFolder "env"
$moduleFolder = Join-Path $scriptFolder "modules"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item $yamlsFolder -ItemType Directory -Force | Out-Null
}

Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-AksCertificate"
LogTitle -Message "Install certificates for environment '$EnvName'..."


LogStep -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin


LogStep -Message "Download certificates from keyvaults..."
Initialize-BouncyCastleSupport
$bootstrapValues.aks.certs | ForEach-Object {
    $certSetting = $_
    $secretName = ([string]$certSetting.name).ToLowerInvariant()
    $secretCertName = "tls.crt"
    $secretKeyName = "tls.key"
    if ($certSetting["type"] -eq "geneva") {
        $secretCertName = "gcscert.pem"
        $secretKeyName = "gcskey.pem"
    }
    $certificate = $null
    LogInfo -Message "Downloading secret '$secretName' from vault '$($bootstrapValues.kv.name)' as cert..."
    $secret = az keyvault secret show --name $secretName --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
    # If certificate was stored in certificates storage (new schema)
    # Handle a base64-encoded PKCS12 certificate
    if ([bool]($secret.Attributes.PSobject.Properties.name -match "ContentType")) {
        if ($secret.Attributes.ContentType -eq "application/x-pkcs12") {
            $certificate = @{
                data     = $secret.value
                password = ""
            }
        }
    }

    if ($null -eq $certificate) {
        # If certificate was stored in the secrets storage (old schema)
        # Handle a base64-encoded JSON with certificate and password stored as a secret
        $certificateBytes = [System.Convert]::FromBase64String($secret.value)
        $jsonCertificate = [System.Text.Encoding]::UTF8.GetString($certificateBytes) | ConvertFrom-Json
        $certificate = @{
            data     = $jsonCertificate.data;
            password = $jsonCertificate.password
        }
    }

    $pfxFile = New-TemporaryFile
    $crtFile = $pfxFile.FullName + ".crt"
    $keyFile = $pfxFile.FullName + ".key"
    try {
        $data = [System.Convert]::FromBase64String($certificate.data)
        $certObject = new-object 'System.Security.Cryptography.X509Certificates.X509Certificate2' ($data, $certificate.password, "Exportable")

        # Write the certificate chain
        $certText = "";
        $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = "NoCheck"
        [void]$chain.Build($certObject)
        $chain.ChainElements | ForEach-Object {
            $certText += "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($_.Certificate.Export('Cert'), 'InsertLineBreaks') + "`n-----END CERTIFICATE-----`n"
        }
        Set-Content -LiteralPath $crtFile -Value $certText

        # Write the private key
        $keyPair = [Org.BouncyCastle.Security.DotNetUtilities]::GetRsaKeyPair($certObject.PrivateKey)
        $streamWriter = [System.IO.StreamWriter]$keyFile
        try {
            $pemWriter = new-object 'Org.BouncyCastle.OpenSsl.PemWriter' ($streamWriter)
            $pemWriter.WriteObject($keyPair.Private)
        }
        finally {
            $streamWriter.Dispose()
        }

        LogInfo -Message "Setup k8s secret for '$secretName' as cert"
        $certContent = Get-Content -LiteralPath $crtFile -Raw
        $keyContent = Get-Content -LiteralPath $keyFile -Raw

        $genevaSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
  name: $($secretName)
  namespace: default
data:
  $($secretCertName): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
  $($secretKeyName): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
type: Opaque
"@

        $genevaSecretYamlFile = Join-Path $yamlsFolder "$($secretName).yaml"
        $genevaSecretYaml | Out-File $genevaSecretYamlFile -Encoding utf8
        kubectl apply -f $genevaSecretYamlFile
    }
    finally {
        Remove-Item -LiteralPath $crtFile -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $keyFile -Force -ErrorAction Ignore
        Remove-Item -LiteralPath $pfxFile -Force -ErrorAction Ignore
    }
}


LogStep -Message "Ensure ssl wildcard cert is create and deployed to k8s"
$sslCertSecret = $bootstrapValues.dns.sslCert
$wildCardDomain = "*.$($bootstrapValues.dns.domain)"

[array]$aksClusterSpns = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
if ($null -eq $aksClusterSpns -or $aksClusterSpns.Count -ne 1) {
    throw "Unable to find service principal for aks cluster"
}
$aksClusterSpn = $aksClusterSpns[0]
$aksClusterSpnPwdSecretName = "$($bootstrapValues.aks.clusterName)-password"
$aksClusterSpnSecret = az keyvault secret show `
    --vault-name $bootstrapValues.kv.name `
    --name $aksClusterSpnPwdSecretName | ConvertFrom-Json
$aksClusterSpnPwd = $aksClusterSpnSecret.value

NewWildCardSslCertUsingAcme `
    -SubscriptionId $azAccount.id `
    -TenantId $azAccount.tenantId `
    -ClientId $aksClusterSpn.appId `
    -ClientSecret $aksClusterSpnPwd `
    -Domain $wildCardDomain `
    -VaultName $bootstrapValues.kv.name `
    -SslCertSecretName $sslCertSecret `
    -K8sNamespaces @($SpaceName, "monitoring") `
    -YamlsFolder $yamlsFolder


# $sslCertYamlSecret = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $sslCertSecret | ConvertFrom-Json
# if (!$sslCertYamlSecret) {
#     $certSubject = "/C=$($bootstrapValues.dns.country)/ST=$($bootstrapValues.dns.state)/L=$($bootstrapValues.dns.city)/O=$($bootstrapValues.dns.organization)/CN=*.$($bootstrapValues.dns.domain)"
#     New-WildcardSslCert -domainName $bootstrapValues.dns.domain -Subject $certSubject -CertSecret $sslCertSecret -YamlsFolder $yamlsFolder -VaultName $bootstrapValues.kv.name
#     $sslCertYamlSecret = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $sslCertSecret | ConvertFrom-Json
# }
# $sslCertYaml = $sslCertYamlSecret.value

# # [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent))
# $genevaSslCertYamlFile = Join-Path $yamlsFolder "$($sslCertSecret).yaml"
# $sslCertYaml | Out-File $genevaSslCertYamlFile -Encoding ascii
# kubectl apply -f $genevaSslCertYamlFile

# LogInfo -Message "Install ssl cert to other namespaces..."
# $otherK8sNamespaces = @("azds", $SpaceName, "monitoring")
# $otherK8sNamespaces | ForEach-Object {
#     $ns = $_
#     kubectl get secret $sslCertSecret -o yaml --export | kubectl apply --namespace $ns -f -
# }
