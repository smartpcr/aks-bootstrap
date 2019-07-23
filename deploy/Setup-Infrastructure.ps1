
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [ValidateSet("rrdp", "rrdu", "aamva", "xiaodoli", "xiaodong", "comp", "kojamroz", "taufiq")]
    [string] $SpaceName = "xiaodoli",
    [bool] $IsLocal = $false,
    [switch] $SyncKeyVault,
    [switch] $SyncAcr
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
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

if ($IsLocal) {
    & "$scriptFolder\Bootstrap-DockerContainers.ps1 -EnvName $EnvName"
}
else {
    LogStep -Step 1 -Message "Setup resoruce groups and key vaults..."
    & $scriptFolder\Setup-KeyVaults.ps1 -EnvName $EnvName -SpaceName $SpaceName

    LogStep -Step 2 -Message "Creating service principals..."
    & $scriptFolder\Setup-ServicePrincipal.ps1 -EnvName $EnvName -SpaceName $SpaceName

    if ($SyncKeyVault) {
        LogStep -Step 3 -Message "Synchronize key vault certs and secrets..."
        & $scriptFolder\Sync-KeyVault.ps1 `
            -TgtSubscriptionName $bootstrapValues.global.subscriptionName `
            -TgtVaultName $bootstrapValues.kv.name
    }

    if ($bootstrapValues.global.components.terraform) {
        LogStep -Step 4 -Message "Setup terraform..."
        & $scriptFolder\Setup-Terraform.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }

    if ($bootstrapValues.global.components.acr) {
        LogStep -Step 5 -Message "Bootstrap ACR..."
        & $scriptFolder\Setup-ContainerRegistry.ps1 -EnvName $EnvName -SpaceName $SpaceName

        if ($SyncAcr) {
            LogStep -Step 6 -Message "Sync ACR..."
            & $scriptFolder\Sync-AcrRepos.ps1 -EnvName $EnvName -SpaceName $SpaceName
        }
    }

    if ($bootstrapValues.global.components.aks) {
        LogStep -Step 7 -Message "Setup AKS..."
        & $scriptFolder\Setup-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }
}


if ($bootstrapValues.global.components.appInsights) {
    LogStep -Step 8 -Message "Setup App Insights..."
    & $scriptFolder\Setup-ApplicationInsights.ps1 -EnvName $EnvName -SpaceName $SpaceName
}


if ($null -ne $bootstrapValues.global.components["cosmosdb"]) {
    $cosmosDbSetting = $bootstrapValues.global.components.cosmosdb
    if ($cosmosDbSetting.docDb -or $cosmosDbSetting.mongoDb -or $cosmosDbSetting.graphDb) {
        LogStep -Step 9 -Message "Setup Mongo DB..."
        & $scriptFolder\Setup-CosmosDb.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }
}


if ($bootstrapValues.global.components.servicebus) {
    LogStep -Step 10 -Message "Setup service bus..."
    & $scriptFolder\Setup-ServiceBus.ps1 -EnvName $EnvName -SpaceName $SpaceName
}


if ($bootstrapValues.global.components.redis) {
    LogStep -Step 11 -Message "Setup redis cluster '$($bootstrapValues.redis.name)' in resource group '$($bootstrapValues.redis.resourceGroup)'..."
    & $scriptFolder\Setup-Redis.ps1 -EnvName $EnvName -SpaceName $SpaceName
}