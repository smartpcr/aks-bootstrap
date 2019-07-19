
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong",
    [bool] $IsLocal = $false,
    [string] $ServiceTemplateFile = "c:\work\my\userspace\deploy\examples\1es\services.yaml"
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
$deployFolder = Join-Path $gitRootFolder "deploy"
if (!$ServiceTemplateFile) {
    $ServiceTemplateFile = Join-Path (Join-Path (Join-Path $deployFolder "examples") "1es") "services.yaml"
}
if (-not (Test-Path $ServiceTemplateFile)) {
    throw "Unable to find service template: '$ServiceTemplateFile'"
}

$envRootFolder = Join-Path $gitRootFolder "env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
$buildNumber = Get-Date -f yyyyMMddHHmm

if ($IsLocal) {
    & $scriptFolder\Deploy-AppsInDocker.ps1 -EnvName $EnvName
}
else {
    $usePodIdentity = $bootstrapValues.aks.keyVaultAccess -contains "podIdentity"
    & $scriptFolder\Deploy-AppsInCluster.ps1 `
        -EnvName $EnvName `
        -SpaceName $SpaceName `
        -UsePodIdentity $usePodIdentity `
        -IsLocal $false `
        -BuildNumber $buildNumber `
        -ServiceTemplateFile $ServiceTemplateFile
}
