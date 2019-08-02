
param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "taufiq",
    [bool] $RecreateCollections = $false
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
Import-Module (Join-Path $moduleFolder "CosmosDb.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up CosmosDB for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -SpaceName $SpaceName -EnvRootFolder $envRootFolder
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

LogInfo "Retrieving cosmosdb settings..."
$cosmosDbSettings = New-Object System.Collections.ArrayList
if ($bootstrapValues.global.components.cosmosdb.docDb) {
    $cosmosDbSettings.Add(@{
            AccountName      = $bootstrapValues.cosmosDb.docDb.account
            Db               = $bootstrapValues.cosmosDb.docDb.db
            API              = $bootstrapValues.cosmosDb.docDb.api
            ResourceGroup    = $bootstrapValues.cosmosdb.docDb.resourceGroup
            Location         = $bootstrapValues.cosmosDb.docDb.location
            ConsistencyLevel = $bootstrapValues.cosmosdb.docDb.consistencyLevel
            VaultName        = $bootstrapValues.kv.name
            KeySecret        = $bootstrapValues.cosmosDb.docDb.keySecret
            Collections      = $bootstrapValues.cosmosDb.docDb.collections
        }) | Out-Null
}
if ($bootstrapValues.global.components.cosmosdb.mongoDb) {
    $cosmosDbSettings.Add(@{
            AccountName      = $bootstrapValues.cosmosDb.mongoDb.account
            Db               = $bootstrapValues.cosmosDb.mongoDb.db
            API              = $bootstrapValues.cosmosDb.mongoDb.api
            ResourceGroup    = $bootstrapValues.cosmosdb.mongoDb.resourceGroup
            Location         = $bootstrapValues.cosmosDb.mongoDb.location
            ConsistencyLevel = $bootstrapValues.cosmosdb.mongoDb.consistencyLevel
            VaultName        = $bootstrapValues.kv.name
            KeySecret        = $bootstrapValues.cosmosDb.mongoDb.keySecret
            Collections      = $bootstrapValues.cosmosDb.mongoDb.collections
        }) | Out-Null
}
if ($bootstrapValues.global.components.cosmosdb.graphDb) {
    $cosmosDbSettings.Add(@{
            AccountName      = $bootstrapValues.cosmosDb.graphDb.account
            Db               = $bootstrapValues.cosmosDb.graphDb.db
            API              = $bootstrapValues.cosmosDb.graphDb.api
            ResourceGroup    = $bootstrapValues.cosmosdb.graphDb.resourceGroup
            Location         = $bootstrapValues.cosmosDb.graphDb.location
            ConsistencyLevel = $bootstrapValues.cosmosdb.graphDb.consistencyLevel
            VaultName        = $bootstrapValues.kv.name
            KeySecret        = $bootstrapValues.cosmosDb.graphDb.keySecret
            Collections      = $bootstrapValues.cosmosDb.graphDb.collections
        }) | Out-Null
}

$cosmosDbSettings | ForEach-Object {
    $cosmosDbSetting = $_
    LogStep -Step 2 "Ensure docdb is created..."
    LogInfo -Message "Ensure account '$($cosmosDbSetting.AccountName)' is created..."
    EnsureCosmosDbAccount `
        -AccountName $cosmosDbSetting.AccountName `
        -API $cosmosDbSetting.API `
        -ResourceGroupName $cosmosDbSetting.ResourceGroup `
        -Location $cosmosDbSetting.Location `
        -ConsistencyLevel $cosmosDbSetting.ConsistencyLevel
    $docdbPrimaryMasterKey = GetCosmosDbAccountKey -AccountName $cosmosDbSetting.AccountName -ResourceGroupName $cosmosDbSetting.ResourceGroup
    az keyvault secret set `
        --vault-name $cosmosDbSetting.VaultName `
        --name $cosmosDbSetting.KeySecret `
        --value $docdbPrimaryMasterKey | Out-Null

    LogInfo -Message "Ensure db '$($cosmosDbSetting.Db)' is created..."
    EnsureDatabaseExists `
        -Endpoint "https://$($cosmosDbSetting.AccountName).documents.azure.com:443/" `
        -MasterKey $docdbPrimaryMasterKey `
        -DatabaseName $cosmosDbSetting.Db | Out-Null

    if ($null -ne $cosmosDbSetting.Collections -and $cosmosDbSetting.Collections.Count -gt 0) {
        if ($RecreateCollections) {
            $cosmosDbSetting.Collections | ForEach-Object {
                $collectionName = $_.name

                DeleteCollection `
                    -AccountName $cosmosDbSetting.AccountName `
                    -ResourceGroupName $cosmosDbSetting.ResourceGroup `
                    -DbName $cosmosDbSetting.Db `
                    -CollectionName $collectionName `
                    -CosmosDbKey $docdbPrimaryMasterKey | Out-Null
            }
        }

        $cosmosDbSetting.Collections | ForEach-Object {
            $collection = $_
            $collectionName = $collection.name
            $collectionPartition = $null
            if ($null -ne $collection["partition"]) {
                $collectionPartition = $collection["partition"]
            }
            $collectionThroughput = 400
            if ($null -ne $collection["throughput"]) {
                $collectionThroughput = $collection["throughput"]
            }
            LogInfo -Message "Ensure collection '$($collectionName)' is created..."
            EnsureCollectionExists `
                -AccountName $cosmosDbSetting.AccountName `
                -ResourceGroupName $cosmosDbSetting.ResourceGroup `
                -DbName $cosmosDbSetting.Db `
                -CollectionName $collectionName `
                -PartitionKeyPath $collectionPartition `
                -Throughput $collectionThroughput `
                -CosmosDbKey $docdbPrimaryMasterKey
        }
    }
}
