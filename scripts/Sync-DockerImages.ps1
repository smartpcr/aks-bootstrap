
param(
    [string] $SourceSubscription = "Compliance_Tools_Eng",
    [string] $SourceAcrName = "oneesdevacr",
    [string] $SourceVaultName = "xiaodong-kv",
    [string] $TargetSubscription = "RRD MSDN Premium",
    [string] $TargetAcrName = "rrdpdevacr",
    [string] $TargetVaultName = "xd-rrdp-kv"
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
$moduleFolder = Join-Path $scriptFolder "modules"

Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AcrUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder

LogStep -Step 1 -Message "Get credential for '$($SourceSubscription)/$($SourceAcrName)'..."
LoginAzureAsUser -SubscriptionName $SourceSubscription | Out-Null
$SourceAcrSecret = "$SourceAcrName-credentials"
LogInfo -Message "Setting access to acr '$SourceAcrName'..."
$SourceAcrCredential = SetAcrCredential `
    -AcrName $SourceAcrName `
    -AcrSecret $SourceAcrSecret `
    -SpnAppId $null `
    -SubscriptionName $SourceSubscription `
    -VaultName $SourceVaultName `
    -SpnPwdSecret $null


LogStep -Step 2 "Getting all images from '$SourceAcrName'..."
$images = GetAllDockerImages -AcrSecret $SourceAcrSecret -VaultName $SourceVaultName


LogStep -Step 3 -Message "Get credential for '$($TargetSubscription)/$($TargetAcrName)'..."
LoginAzureAsUser -SubscriptionName $TargetSubscription | Out-Null
$TargetAcrSecret = "$TargetAcrName-credentials"
LogInfo -Message "Setting access to acr '$TargetAcrName'..."
$TargetAcrCredential = SetAcrCredential `
    -AcrName $TargetAcrName `
    -AcrSecret $TargetAcrSecret `
    -SpnAppId $null `
    -SubscriptionName $TargetSubscription `
    -VaultName $TargetVaultName `
    -SpnPwdSecret $null


LogStep -Step 4 "Sync all images from '$SourceAcrName'..."
$totalImageCount = $images.Count
$imagePushed = 0
$images | ForEach-Object {
    $ImageName = $_
    LogStep -Step 4 "Sync image '$ImageName'..., $imagePushed/$totalImageCount"
    SyncDockerImage `
        -SourceAcrName $SourceAcrName `
        -SourceAcrCredential $SourceAcrCredential `
        -TargetAcrName $TargetAcrName `
        -TargetAcrCredential $TargetAcrCredential `
        -ImageName $ImageName

    $imagePushed++
    LogInfo -Message "Synced $imagePushed of $totalImageCount..."
}


LogStep -Step 5 -Message "Sync older version of secret-broker..."
$ImageName = "1es/secret-broker"
$Tag = "394719"
SyncDockerImageWithTag `
    -SourceAcrName $SourceAcrName `
    -SourceAcrCredential $SourceAcrCredential `
    -TargetAcrName $TargetAcrName `
    -TargetAcrCredential $TargetAcrCredential `
    -ImageName $ImageName `
    -Tag $Tag

Write-Host "Done!"