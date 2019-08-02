
param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong"
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
$templatesFolder = Join-Path $envRootFolder "templates"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
}
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AksUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-GenevaMetrics"
LogStep -Message "Login and populate azure settings..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azureAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin
$aksSpn = az ad app list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
$aksSpnPwd = az keyvault secret show --name $bootstrapValues.aks.servicePrincipalPassword --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
$acrName = $bootstrapValues.acr.name
$acrPassword = az acr credential show -n $acrName | ConvertFrom-Json
$additionalSettings = @{
    azAccount = @{
        tenantId = $azureAccount.tenantId
        id       = $azureAccount.id
        name     = $azureAccount.name
    }
    aks       = @{
        spn = @{
            appId = $aksSpn.appId
            pwd   = $aksSpnPwd.value
        }
    }
}
$bootstrapValues = Get-EnvironmentSettings `
    -EnvName $envName `
    -EnvRootFolder $envRootFolder `
    -SpaceName $SpaceName `
    -AdditionalSettings $additionalSettings

$bootstrapValues["azAccount"] = $additionalSettings.azAccount
$bootstrapValues.aks["spn"] = $additionalSettings.aks.spn
$bootstrapValues.aks["nodeResourceGroup"] = GetAksResourceGroupName -bootstrapValues $bootstrapValues
$bootstrapValues.aks["networkSecurityGroup"] = (GetNetworkSecurityGroup -bootstrapValues $bootstrapValues).name
$bootstrapValues.aks["virtualNetwork"] = (GetVirtualNetwork -bootstrapValues $bootstrapValues).name
$bootstrapValues.aks["routeTable"] = (GetRouteTable -bootstrapValues $bootstrapValues).name
$bootstrapValues.aks["availabilitySet"] = (GetAvailabilitySet -bootstrapValues $bootstrapValues).name
$bootstrapValues.acr["pwd"] = $acrPassword.passwords[0].value
$genevaCertThumbprint = az keyvault secret show --name $bootstrapValues.geneva.certThumbprintSecret --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
$genevaCertificate = az keyvault secret show --name $bootstrapValues.geneva.certName --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
$bootstrapValues.geneva["cert"] = @{
    base64string = $genevaCertificate.value.Trim()
    thumbprint   = $genevaCertThumbprint.value.Trim()
}

$adCredsFolder = Join-Path $yamlsFolder "ad-creds"
if (-not (Test-Path $adCredsFolder)) {
    New-Item -Path $adCredsFolder -ItemType Directory -Force | Out-Null
}
$azureSettingTemplateFile = Join-Path $templatesFolder "azure.json.tpl"
$azureSettingTemplate = Get-Content -Raw $azureSettingTemplateFile
$azureSettingJson = Set-YamlValues -valueTemplate $azureSettingTemplate -settings $bootstrapValues
$azureSettingJson | Out-File (Join-Path $adCredsFolder "azure.json") -Encoding utf8


LogStep -Message "Download and setup geneva certificate..."
Initialize-BouncyCastleSupport
$genevaCert = DownloadGenevaCertFromKeyVault -VaultName $bootstrapValues.kv.name -CertName $bootstrapValues.geneva.certName -AsSecret
$pfxFile = New-TemporaryFile
$crtFile = $pfxFile.FullName + ".crt"
$keyFile = $pfxFile.FullName + ".key"
try {
    $data = [System.Convert]::FromBase64String($genevaCert.data)
    $certObject = new-object 'System.Security.Cryptography.X509Certificates.X509Certificate2' ($data, $genevaCert.password, "Exportable")
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

    $certContent = Get-Content -LiteralPath $crtFile -Raw
    $keyContent = Get-Content -LiteralPath $keyFile -Raw

    $genevaSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
  name: $($bootstrapValues.geneva.k8sSecret)
  namespace: $($bootstrapValues.geneva.k8sNamespace)
data:
  $($bootstrapValues.geneva.secretCert): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
  $($bootstrapValues.geneva.secretKey): $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
type: Opaque
"@

    $genevaSecretYamlFile = Join-Path $yamlsFolder "geneva-certificate.yaml"
    $genevaSecretYaml | Out-File $genevaSecretYamlFile -Encoding utf8
    kubectl apply -f $genevaSecretYamlFile
}
finally {
    Remove-Item -LiteralPath $crtFile -Force -ErrorAction Ignore
    Remove-Item -LiteralPath $keyFile -Force -ErrorAction Ignore
    Remove-Item -LiteralPath $pfxFile -Force -ErrorAction Ignore
}


LogStep -Message "Install geneva metrics (telegraf-mdm) daemonset..."
$metricsYamlTemplateFile = Join-Path $templatesFolder "linux-geneva-agent-metrics.tpl"
$metricsYamlTemplate = Get-Content $metricsYamlTemplateFile -Raw
$metricsYaml = Set-YamlValues -valueTemplate $metricsYamlTemplate -settings $bootstrapValues
$metricsYamlFile = Join-Path $yamlsFolder "linux-geneva-agent-metrics.yaml"
$metricsYaml | Out-File $metricsYamlFile -Encoding utf8
kubectl apply -f $metricsYamlFile