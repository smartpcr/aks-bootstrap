
param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodoli"
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
$envFolder = Join-Path $gitRootFolder "env"
$moduleFolder = Join-Path $scriptFolder "modules"

Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AcrUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Sync-AcrRepos"
LogStep -Message "Retrieving environment settings for '$EnvName'..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -SpaceName $SpaceName -EnvRootFolder $envFolder
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
$vaultName = $bootstrapValues.kv.name

$sourceAcrSettings = New-Object System.Collections.ArrayList

# $AcrName = "registry1811d0c3"
# $AcrSecret = "$AcrName-credentials"
# Write-Host "Setting access to acr '$AcrName'..."
# $AcrCredential = SetAcrCredential `
#     -AcrName $AcrName `
#     -AcrSecret $AcrSecret `
#     -SpnAppId $null `
#     -SubscriptionName "Compliance_Tools_Eng" `
#     -VaultSubscriptionName $bootstrapValues.global.subscriptionName `
#     -VaultName $vaultName `
#     -SpnPwdSecret $null
# $sourceAcrSettings.Add(@{
#         AcrName           = $AcrName
#         TargetImageFolder = "1es"
#         Credential        = $AcrCredential
#     }) | Out-Null

$AcrName = "oneesdevacr"
$AcrSecret = "$AcrName-credentials"
Write-Host "Setting access to acr '$AcrName'..."
$AcrCredential = SetAcrCredential `
    -AcrName $AcrName `
    -AcrSecret $AcrSecret `
    -SpnAppId $null `
    -SubscriptionName "Compliance_Tools_Eng" `
    -VaultSubscriptionName $bootstrapValues.global.subscriptionName `
    -VaultName $vaultName `
    -SpnPwdSecret $null
$sourceAcrSettings.Add(@{
        AcrName           = $AcrName
        TargetImageFolder = "1es"
        Credential        = $AcrCredential
    }) | Out-Null

# $AcrName = "linuxgeneva-microsoft"
# $SpnAppId = "9beb98b0-4b0d-4989-b4ea-625d28b7d98a"
# $AcrSecret = "$AcrName-credentials"
# $SpnName = "xiaodoli-acr-sp"
# $SpnPwdSecret = "$SpnName-pwd"
# Write-Host "Setting access to acr '$AcrName'..."
# $AcrCredential = SetAcrCredential `
#     -AcrName $AcrName `
#     -AcrSecret $AcrSecret `
#     -SpnAppId $SpnAppId `
#     -SubscriptionName "Compliance_Tools_Eng" `
#     -VaultSubscriptionName $bootstrapValues.global.subscriptionName `
#     -VaultName $vaultName `
#     -SpnPwdSecret $SpnPwdSecret
# $sourceAcrSettings.Add(@{
#         AcrName           = $AcrName
#         TargetImageFolder = "geneva"
#         Credential        = $AcrCredential
#     }) | Out-Null


$TargetAcrCredential = SetAcrCredential `
    -AcrName $bootstrapValues.acr.name `
    -AcrSecret "$($bootstrapValues.acr.name)-credentials" `
    -SpnAppId $null `
    -SubscriptionName $bootstrapValues.global.subscriptionName `
    -VaultSubscriptionName $bootstrapValues.global.subscriptionName `
    -VaultName $bootstrapValues.kv.name `
    -SpnPwdSecret $null

$sourceAcrSettings | ForEach-Object {
    $AcrName = $_.AcrName
    $AcrCredential = $_.Credential
    $AcrSecret = "$AcrName-credentials"
    LogStep "Getting all images from '$AcrName' to '$($bootstrapValues.acr.name)'"
    $images = GetAllDockerImages -AcrSecret $AcrSecret -VaultName $vaultName
    $totalImageCount = $images.Count
    $imagePushed = 0
    $images | ForEach-Object {
        $ImageName = $_
        LogStep "Sync image '$ImageName'..., $imagePushed/$totalImageCount"
        SyncDockerImage `
            -SourceAcrName $AcrName `
            -SourceAcrCredential $AcrCredential `
            -TargetAcrName $bootstrapValues.acr.name `
            -TargetAcrCredential $TargetAcrCredential `
            -ImageName $ImageName

        $imagePushed++
    }
}


