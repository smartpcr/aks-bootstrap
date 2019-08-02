
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [ValidateSet("rrdp", "rrdu", "aamva", "xiaodoli", "xiaodong", "comp", "kojamroz", "taufiq")]
    [string] $SpaceName = "rrdp",
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
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-Infrastructure"
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

if ($IsLocal) {
    & "$scriptFolder\Bootstrap-DockerContainers.ps1 -EnvName $EnvName"
}
else {
    UsingScope("Ensure resoruce groups and key vaults") {
        & $scriptFolder\Setup-KeyVaults.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }

    UsingScope("Ensure service principals") {
        & $scriptFolder\Setup-ServicePrincipal.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }

    if ($SyncKeyVault) {
        UsingScope("Synchronize key vault") {
            & $scriptFolder\Sync-KeyVault.ps1 `
                -TgtSubscriptionName $bootstrapValues.global.subscriptionName `
                -TgtVaultName $bootstrapValues.kv.name
        }
    }

    if ($bootstrapValues.global.components.terraform) {
        UsingScope("Setup terraform") {
            & $scriptFolder\Setup-Terraform.ps1 -EnvName $EnvName -SpaceName $SpaceName
        }
    }

    if ($bootstrapValues.global.components.acr) {
        UsingScope("Setup ACR") {
            & $scriptFolder\Setup-ContainerRegistry.ps1 -EnvName $EnvName -SpaceName $SpaceName
        }

        if ($SyncAcr) {
            UsingScope("Sync ACR") {
                & $scriptFolder\Sync-AcrRepos.ps1 -EnvName $EnvName -SpaceName $SpaceName
            }
        }
    }

    if ($bootstrapValues.global.components.aks) {
        UsingScope("Setup AKS") {
            & $scriptFolder\Setup-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName
        }
    }
}


if ($bootstrapValues.global.components.appInsights) {
    UsingScope("Setup App Insights") {
        & $scriptFolder\Setup-ApplicationInsights.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }
}


if ($null -ne $bootstrapValues.global.components["cosmosdb"]) {
    $cosmosDbSetting = $bootstrapValues.global.components.cosmosdb
    if ($cosmosDbSetting.docDb -or $cosmosDbSetting.mongoDb -or $cosmosDbSetting.graphDb) {
        UsingScope("Setup Cosmos DB") {
            & $scriptFolder\Setup-CosmosDb.ps1 -EnvName $EnvName -SpaceName $SpaceName
        }
    }
}


if ($bootstrapValues.global.components.servicebus) {
    UsingScope("Setup service bus") {
        & $scriptFolder\Setup-ServiceBus.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }
}


if ($bootstrapValues.global.components.redis) {
    UsingScope("Setup redis cluster") {
        & $scriptFolder\Setup-Redis.ps1 -EnvName $EnvName -SpaceName $SpaceName
    }
}