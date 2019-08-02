
function New-CertificateAsSecret {
    param(
        [string] $CertName,
        [string] $VaultName
    )

    $cert = New-SelfSignedCertificate `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -Subject "CN=$CertName" `
        -KeySpec KeyExchange `
        -HashAlgorithm "SHA256" `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $certPwdSecretName = "$CertName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName
    $pwd = $spCertPwdSecret.SecretValue
    $pfxFilePath = [System.IO.Path]::GetTempFileName()
    Export-PfxCertificate -cert $cert -FilePath $pfxFilePath -Password $pwd -ErrorAction Stop | Out-Null
    $Bytes = [System.IO.File]::ReadAllBytes($pfxFilePath)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $JSONBlob = @{
        data     = $Base64
        dataType = 'pfx'
        password = $spCertPwdSecret.SecretValueText
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    $SecretValue = ConvertTo-SecureString -String $Content -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $VaultName -Name $CertName -SecretValue $SecretValue | Out-Null

    Remove-Item $pfxFilePath
    Remove-Item "cert:\\CurrentUser\My\$($cert.Thumbprint)"

    return $cert
}

function New-CertificateAsSecret2 {
    param(
        [string] $ScriptFolder,
        [string] $CertName,
        [string] $VaultName
    )

    $certPwdSecretName = "$CertName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault2 -vaultName $VaultName -SecretName $certPwdSecretName
    $password = $spCertPwdSecret.value

    $certPrivateKeyFile = "$ScriptFolder/credential/$($CertName)"
    $certPublicKeyFile = "$ScriptFolder/credential/$($CertName).pub"
    $pemFilePath = "$ScriptFolder/credential/$($CertName).pem"

    ssh-keygen -f $certPrivateKeyFile -P $password
    $certPemString = ssh-keygen -f $certPublicKeyFile -e -m pem
    $certPemString | Out-File $pemFilePath

    $privateKeyBytes = [System.IO.File]::ReadAllBytes($certPrivateKeyFile)
    $privateKeyText = [System.Convert]::ToBase64String($privateKeyBytes)
    $privateKeyJson = @{
        data     = $privateKeyText
        dataType = 'pem'
        password = $password
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($privateKeyJson)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    az keyvault secret set --vault-name $VaultName --name $CertName --value $Content --query $env:out_null
    az keyvault certificate import --vault-name $VaultName --name $CertName --file $certPrivateKeyFile --password $password

    # $publicKeyBytes = [System.IO.File]::ReadAllBytes($certPublicKeyFile)
    # $publicKeyText = [System.Convert]::ToBase64String($publicKeyBytes)
    $publicKeySecretName = "$($CertName)-pub"
    # az keyvault secret set --vault-name $VaultName --name $publicKeySecretName --value $publicKeyText --query $env:out_null
    az keyvault certificate import --name $publicKeySecretName --file $certPublicKeyFile --vault-name $VaultName

    # $pemKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($certPemString)
    # $pemKeyContent = [System.Convert]::ToBase64String($pemKeyBytes)
    $pemKeySecretName = "$($CertName)-pem"

    # az keyvault secret set --vault-name $VaultName --name $pemKeySecretName --value $pemKeyContent --query $env:out_null
    az keyvault certificate import --name $pemKeySecretName --file $pemFilePath --vault-name $VaultName
}

function Install-CertFromVaultSecret {
    param(
        [string] $VaultName,
        [string] $CertSecretName
    )
    $certSecret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $CertSecretName

    $kvSecretBytes = [System.Convert]::FromBase64String($certSecret.SecretValueText)
    $certDataJson = [System.Text.Encoding]::UTF8.GetString($kvSecretBytes) | ConvertFrom-Json
    $pfxBytes = [System.Convert]::FromBase64String($certDataJson.data)
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2

    $certPwdSecretName = "$CertSecretName-pwd"
    $certPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName

    $pfx.Import($pfxBytes, $certPwdSecret.SecretValue, $flags)
    $thumbprint = $pfx.Thumbprint

    $certAlreadyExists = Test-Path Cert:\CurrentUser\My\$thumbprint
    if (!$certAlreadyExists) {
        $x509Store = new-object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList My, CurrentUser
        $x509Store.Open('ReadWrite')
        $x509Store.Add($pfx)
    }

    return $pfx
}

function DownloadGenevaCertFromKeyVault {
    param(
        [string] $VaultName = "int-disco-east-us",
        [string] $CertName = "Geneva-Certificate",
        [switch] $AsSecret
    )

    if ($AsSecret) {
        $certificate = az keyvault secret show --name $CertName --vault-name $VaultName | ConvertFrom-Json
    }
    else {
        $certFile = [System.IO.Path]::GetTempFileName()
        if (Test-Path $certFile) {
            Remove-Item $certFile -Force | Out-Null
        }
        az keyvault certificate download --file $certFile --name $CertName --encoding PEM --vault-name $VaultName
        $certData = Get-Content $certFile -Raw
        Remove-Item $certFile -Force | Out-Null
        return @{
            data     = $certData
            password = ""
        }
    }

    if ($certificate.Attributes.ContentType -eq "application/x-pkcs12") {
        return @{
            data     = $certificate.value;
            password = ""
        }
    }

    $certificateBytes = [System.Convert]::FromBase64String($certificate.value)
    $jsonCertificate = [System.Text.Encoding]::UTF8.GetString($certificateBytes) | ConvertFrom-Json
    $genevaCert = @{
        data     = $jsonCertificate.data;
        password = $jsonCertificate.password
    }

    return $genevaCert
}


function Initialize-BouncyCastleSupport {
    $tempPath = $env:TEMP
    if ($null -eq $tempPath) {
        $tempPath = "/tmp"
    }

    $bouncyCastleDllPath = Join-Path $tempPath "BouncyCastle.Crypto.dll"

    if (-not (Test-Path $bouncyCastleDllPath)) {
        Invoke-WebRequest `
            -Uri "https://avalanchebuildsupport.blob.core.windows.net/files/BouncyCastle.Crypto.dll" `
            -OutFile $bouncyCastleDllPath
    }

    [System.Reflection.Assembly]::LoadFile($bouncyCastleDllPath) | Out-Null
}

function New-WildcardSslCert() {
    param(
        [string] $domainName,
        [string] $CertSubject,
        [string] $CertSecret,
        [string] $YamlsFolder,
        [string] $VaultName
    )

    $sslCertSecretFound = az keyvault secret show --name $CertSecret --vault-name $VaultName | ConvertFrom-Json
    if ($null -eq $sslCertSecretFound) {
        $caKey = Join-Path $YamlsFolder "ca.key"
        $caCrt = Join-Path $YamlsFolder "ca.crt"
        $serverKey = Join-Path $YamlsFolder "server.key"
        $serverCsr = Join-Path $YamlsFolder "server.csr"
        $serverCrt = Join-Path $YamlsFolder "server.crt"
        $clientKey = Join-Path $YamlsFolder "client.key"
        $clientCsr = Join-Path $YamlsFolder "client.csr"
        $clientCrt = Join-Path $YamlsFolder "client.crt"

        # Generate the CA Key and Certificate
        openssl req -x509 -sha256 -newkey rsa:4096 -keyout $caKey -out $caCrt -days 356 -nodes -subj "/CN=$domainName Cert Authority"
        # Generate the Server Key, and Certificate and Sign with the CA Certificate
        openssl req -new -newkey rsa:4096 -keyout $serverKey -out $serverCsr -nodes -subj "/CN=*.$domainName"
        openssl x509 -req -sha256 -days 365 -in $serverCsr -CA $caCrt -CAkey $caKey -set_serial 01 -out $serverCrt
        # Generate the Client Key, and Certificate and Sign with the CA Certificate
        openssl req -new -newkey rsa:4096 -keyout $clientKey -out $clientCsr -nodes -subj "/CN=k8s-service"
        openssl x509 -req -sha256 -days 365 -in $clientCsr -CA $caCrt -CAkey $caKey -set_serial 02 -out $clientCrt

        kubectl create secret generic $CertSecret --from-file=tls.crt=$serverCrt --from-file=tls.key=$serverKey --from-file=ca.crt=$caCrt


        $certContent = Get-Content -LiteralPath $serverCrt -Raw
        $keyContent = Get-Content -LiteralPath $serverKey -Raw
        $caCertContent = Get-Content -LiteralPath $caCrt -Raw
        $sslCertSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
    name: $($CertSecret)
    namespace: default
data:
    tls.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
    tls.key: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
    ca.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($caCertContent)))
type: Opaque
"@

        LogInfo -Message "Add server ssl cert '$CertSecret' to key vault"
        $sslCertYamlFile = Join-Path $yamlsFolder "$($CertSecret).secret"
        $sslCertSecretYaml | Out-File $sslCertYamlFile -Encoding ascii
        az keyvault secret set --vault-name $VaultName --name $CertSecret --file $sslCertYamlFile | Out-Null

        $clientCertContent = Get-Content -LiteralPath $clientCrt -Raw
        $clientKeyContent = Get-Content -LiteralPath $clientKey -Raw
        $sslCertClientSecret = "$($CertSecret)-client"
        $sslClientCertSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
    name: $($sslCertClientSecret)
    namespace: default
data:
    tls.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($clientCertContent)))
    tls.key: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($clientKeyContent)))
    ca.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($caCertContent)))
type: Opaque
"@

        LogInfo -Message "Add client ssl cert '$sslCertClientSecret' to key vault"
        $clientSslCertYamlFile = Join-Path $yamlsFolder "$($sslCertClientSecret).secret"
        $sslClientCertSecretYaml | Out-File $clientSslCertYamlFile -Encoding utf8
        az keyvault secret set --vault-name $VaultName --name $sslCertClientSecret --file $clientSslCertYamlFile | Out-Null
    }
    else {
        LogInfo -Message "ssl cert '$CertSecret' is already created."
    }
}

function NewWildCardSslCertUsingAcme() {
    param(
        [string]$SubscriptionId,
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Domain,
        [string]$VaultName,
        [string]$SslCertSecretName,
        [string[]]$K8sNamespaces,
        [string]$YamlsFolder
    )

    LogInfo "Check if ssl cert is already created and available in key vault"
    [array]$sslCertsFound = az keyvault secret list --vault-name $VaultName --query "[?id=='https://$($VaultName).vault.azure.net/secrets/$($SslCertSecretName)']" | ConvertFrom-Json
    if ($null -eq $sslCertsFound -or $sslCertsFound.Count -eq 0) {
        # TODO: run this in docker
        $acmesh = "~/.acme.sh/acme.sh"

        $certOutputFolder = "~/.acme.sh/$($Domain)"
        $shellContent = New-Object System.Text.StringBuilder

        $shellContent.AppendLine("export AZUREDNS_SUBSCRIPTIONID=`"$($SubscriptionId)`"") | Out-Null
        $shellContent.AppendLine("export AZUREDNS_TENANTID=`"$($TenantId)`"") | Out-Null
        $shellContent.AppendLine("export AZUREDNS_APPID=`"$($ClientId)`"") | Out-Null
        $shellContent.AppendLine("export AZUREDNS_CLIENTSECRET=`"$($ClientSecret)`"") | Out-Null
        $shellContent.AppendLine("export DOMAIN=`"$($Domain)`"") | Out-Null
        $shellContent.AppendLine("$($acmesh) --issue --dns dns_azure -d $DOMAIN --debug") | Out-Null
        $shFile = Join-Path $YamlsFolder "acme-wildcard.sh"
        $shellContent.ToString() | Out-File $shFile -Encoding ascii -Force | Out-Null
        Invoke-Expression "chmod +x $shFile"
        Invoke-Expression "bash $shFile"

        $crtFile = Join-Path $certOutputFolder "$($Domain).cer"
        $keyFile = Join-Path $certOutputFolder "$($Domain).key"
        $caFile = Join-Path $certOutputFolder "ca.cer"

        $certContent = Get-Content -LiteralPath $crtFile -Raw
        $keyContent = Get-Content -LiteralPath $keyFile -Raw
        $caCertContent = Get-Content -LiteralPath $caFile -Raw

        $sslCertSecretYaml = @"
---
apiVersion: v1
kind: Secret
metadata:
name: $($SslCertSecretName)
namespace: default
data:
tls.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($certContent)))
tls.key: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($keyContent)))
ca.crt: $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($caCertContent)))
type: kubernetes.io/tls
"@

        $sslCertYamlFile = Join-Path $YamlsFolder "$($SslCertSecretName).secret"
        $sslCertSecretYaml | Out-File $sslCertYamlFile -Encoding ascii
        az keyvault secret set --vault-name $VaultName --name $SslCertSecretName --file $sslCertYamlFile | Out-Null
    }

    $sslCertYamlSecret = az keyvault secret show --vault-name $VaultName --name $SslCertSecretName | ConvertFrom-Json
    $sslCertYaml = $sslCertYamlSecret.value
    $genevaSslCertYamlFile = Join-Path $YamlsFolder "$($SslCertSecretName).yaml"
    $sslCertYaml | Out-File $genevaSslCertYamlFile -Encoding ascii
    kubectl apply -f $genevaSslCertYamlFile

    $K8sNamespaces | ForEach-Object {
        $ns = $_
        Write-Host "Adding secret '$SslCertSecretName' to '$($ns)'" -ForegroundColor Green

        kubectl delete secret $SslCertSecretName -n $ns
        kubectl get secret $SslCertSecretName -o yaml --export | kubectl apply --namespace $ns -f -
    }
}