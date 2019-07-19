
param(
    [string] $SrcVaultName = "int-disco-east-us",
    [string] $SrcSubscriptionName = "Compliance_Tools_Eng",
    [string] $TgtVaultName = "xiaodong-kv",
    [string] $TgtSubscriptionName = "Compliance_Tools_Eng"
)

function IsCertExists() {
    param(
        [string]$VaultName,
        [string]$CertName
    )

    $existingCerts = az keyvault certificate list --vault-name $VaultName --query "[?name=='$CertName']" | ConvertFrom-Json
    return $null -ne $existingCerts -and $existingCerts.Count -gt 0
}

function IsSecretExists() {
    param(
        [string]$VaultName,
        [string]$SecretName
    )

    $existingSecrets = az keyvault secret list --vault-name $VaultName --query "[?name=='$SecretName']" | ConvertFrom-Json
    return $null -ne $existingSecrets -and $existingSecrets.Count -gt 0
}


$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest


Write-Host "1. Login to azure..." -ForegroundColor White
$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}
$moduleFolder = Join-Path $scriptFolder "modules"
$certsFolder = Join-Path $scriptFolder "certs"
if (-not (Test-Path $certsFolder)) {
    New-Item $certsFolder -ItemType Directory -Force | Out-Null
}
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item $yamlsFolder -ItemType Directory -Force | Out-Null
}
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
LoginAzureAsUser -SubscriptionName $SrcSubscriptionName | Out-Null


Write-Host "2. Download all certificates..." -ForegroundColor White
$downloadedCertFiles = New-Object System.Collections.ArrayList
$allCerts = az keyvault certificate list --vault-name $SrcVaultName --query "[].{id:id}" | convertfrom-json
$totalCerts = $allCerts.Length
$certsImported = 0
$allCerts | ForEach-Object {
    $certId = [string]$_.id
    $certName = $certId.Substring($certId.LastIndexOf("/") + 1)
    Write-Host "`tDownloading cert '$certName'..." -ForegroundColor Green
    $certFile = Join-Path $certsFolder "$certName.pfx"
    if (Test-Path $certFile) {
        Remove-Item $certFile -Force | Out-Null
    }
    if ($certName.EndsWith("-Managed")) {
        az keyvault secret download --vault-name $SrcVaultName --name $certName -e base64 -f $certFile
    }
    else {
        az keyvault certificate download --file $certFile --name $certName --encoding PEM --vault-name $SrcVaultName
    }

    $downloadedCertFiles.Add(@{
            CertName = $certName
            CertFile = $certFile
        }) | Out-Null

    $certsImported ++
    Write-Host "`tImported $certsImported of $totalCerts..." -ForegroundColor White
}


Write-Host "3. Downloading all secrets..." -ForegroundColor White
$downloadedSecrets = New-Object System.Collections.ArrayList
$allSecrets = az keyvault secret list --vault-name $SrcVaultName --query "[].{id:id}" | ConvertFrom-Json
$totalSecrets = $allSecrets.Length
$secretsImported = 0
$allSecrets | ForEach-Object {
    $secretId = [string]$_.id
    $secretName = $secretId.Substring($secretId.LastIndexOf("/") + 1)
    Write-Host "`tDownload secret '$secretName'..." -ForegroundColor Green
    $secret = az keyvault secret show --vault-name $SrcVaultName --name $secretName | ConvertFrom-Json
    $downloadedSecrets.Add(@{
            Name  = $secretName
            Value = $secret.value
        }) | Out-Null

    #
    $secretsImported++
    Write-Host "`tImported $secretsImported of $totalSecrets..." -ForegroundColor White
}

$secretsJsonFile = Join-Path $yamlsFolder "secrets.json"
$downloadedSecrets | ConvertTo-Json -Depth 99 | Out-File $secretsJsonFile

Write-Host "4. Login to azure..." -ForegroundColor White
LoginAzureAsUser -SubscriptionName $TgtSubscriptionName | Out-Null


Write-Host "5. Importing secrets..." -ForegroundColor White
$secrets = Get-Content $secretsJsonFile | ConvertFrom-Json
$totalSecrets = $secrets.Length
$secretsImported = 0
$secretsFolder = Join-Path $yamlsFolder "secrets"
if (-not (Test-Path $secretsFolder)) {
    New-Item $secretsFolder -ItemType Directory -Force | Out-Null
}
$secrets | ForEach-Object {
    $name = $_.Name
    $value = $_.Value
    Write-Host "`tImporting secret '$name'..." -ForegroundColor Green
    $certFound = $downloadedCertFiles | Where-Object { $_.CertName -eq $name }
    if ($null -eq $certFound) {
        $secretExist = IsSecretExists -VaultName $TgtVaultName -SecretName $name
        if ($secretExist -eq $true) {
            az keyvault secret delete --name $name --vault-name $TgtVaultName | Out-Null
        }
        $tempFile = Join-Path $secretsFolder $name
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force | Out-Null
        }
        # current version of cross-platform powershell generate newline when using Out-File
        [System.IO.File]::WriteAllText($tempFile, $value, [System.Text.Encoding]::ASCII)
        az keyvault secret set --vault-name $TgtVaultName --name $name --file $tempFile --encoding ascii | Out-Null
        $secretsImported++
        # Remove-Item $tempFile -Force | Out-Null
        Write-Host "`tImported $secretsImported of $($totalSecrets) secrets" -ForegroundColor White
    }
    else {
        Write-Host "`tSkipping import secret '$name', since it's managed by cert" -ForegroundColor Yellow
    }
}


Write-Host "6. Importing certificates..." -ForegroundColor White
$certsImported = 0
$downloadedCertFiles | ForEach-Object {
    $name = $_.CertName
    $file = $_.CertFile
    Write-Host "`tImporting cert '$name'..." -ForegroundColor Green
    $certAlreadyExist = IsCertExists -VaultName $TgtVaultName -CertName $name
    if ($certAlreadyExist -eq $true) {
        az keyvault certificate delete --vault-name $TgtVaultName --name $name | Out-Null
    }
    $certSecretExist = IsSecretExists -VaultName $TgtVaultName -SecretName $name
    if ($certSecretExist -eq $true) {
        az keyvault secret delete --vault-name $TgtVaultName --name $name | Out-Null
    }
    az keyvault certificate import --file $file --name $name --vault-name $TgtVaultName | Out-Null
    $certsImported++
    Write-Host "`tImported $certsImported of $($downloadedCertFiles.Count) certs" -ForegroundColor White
    Remove-Item $file -Force | Out-Null
}


Write-Host "Done!" -ForegroundColor White