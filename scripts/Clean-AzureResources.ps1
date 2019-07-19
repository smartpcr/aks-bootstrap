
param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong",
    [switch] $IncludeData
)


$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}


$envFolder = Join-Path $gitRootFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

if ($bootstrapValues.global.components.aks -eq $true) {
    LogStep -Step 1 -Message "Delete AKS cluster '$($bootstrapValues.aks.clusterName)'..."
    az aks delete --name $bootstrapValues.aks.clusterName --resource-group $bootstrapValues.aks.resourceGroup --yes

    $aksClusterSpnName = $bootstrapValues.aks.clusterName
    $aksClusterSpns = az ad sp list --display-name $aksClusterSpnName | ConvertFrom-Json
    if ($null -eq $aksClusterSpns) {
        LogInfo "AKS spn '$aksClusterSpnName' is already removed"
    }
    elseif ($aksClusterSpns.Count -eq 1) {
        LogInfo "Removing spn for AKS cluster '$aksClusterSpnName'..."
        az ad sp delete --id $aksClusterSpns[0].appId
    }
    else {
        LogInfo -Message "Multiple of spn exists for ''$aksClusterSpnName" 
    }
}

if ($bootstrapValues.global.components.dns -eq $true) {
    LogStep -Step 2 -Message "Delete DNA zone '$($bootstrapValues.dns.name)'..."
    az network dns zone delete -g $bootstrapValues.dns.resourceGroup -n $bootstrapValues.dns.domain --yes
}

if ($bootstrapValues.global.components.appInsights -eq $true) {
    LogStep -Step 3 -Message "Delete app insights '$($bootstrapValues.appInsights.name)'..."
    az resource delete `
        --resource-group $bootstrapValues.appInsights.resourceGroup `
        --resource-type "Microsoft.Insights/components" `
        --name $bootstrapValues.appInsights.name
}


if ($bootstrapValues.global.components.cosmosdb.docDb -eq $true -and $IncludeData) {
    LogStep -Step 4 -Message "Delete docdb '$($bootstrapValues.cosmosdb.docDb.account)'..."
    az cosmosdb delete `
        --resource-group $bootstrapValues.cosmosdb.docDb.resourceGroup `
        --name $bootstrapValues.cosmosdb.docDb.account --yes
}

if ($bootstrapValues.global.components.cosmosdb.mongoDb -eq $true -and $IncludeData) {
    LogStep -Step 4 -Message "Delete mongodb '$($bootstrapValues.cosmosdb.mongoDb.account)'..."
    az cosmosdb delete `
        --resource-group $bootstrapValues.cosmosdb.mongoDb.resourceGroup `
        --name $bootstrapValues.cosmosdb.mongoDb.account --yes
}

if ($bootstrapValues.global.components.cosmosdb.graphDb -eq $true -and $IncludeData) {
    LogStep -Step 4 -Message "Delete graphDb '$($bootstrapValues.cosmosdb.graphDb.account)'..."
    az cosmosdb delete `
        --resource-group $bootstrapValues.cosmosdb.graphDb.resourceGroup `
        --name $bootstrapValues.cosmosdb.graphDb.account --yes
}

if ($bootstrapValues.global.components.redis -eq $true) {
    LogStep -Step 5 -Message "Delete redis cluster '$($bootstrapValues.redis.name)'..."
    az redis delete `
        --name $bootstrapValues.redis.name `
        --resource-group $bootstrapValues.redis.resourceGroup --yes
}

if ($bootstrapValues.global.components.acr -eq $true -and $IncludeData) {
    LogStep -Step 6 -Message "Delete ACR '$($bootstrapValues.acr.name)'..."
    az acr delete -g $bootstrapValues.acr.resourceGroup -n $bootstrapValues.acr.name --yes
}

if ($IncludeData) {
    LogStep -Step 7 -Message "Delete KV '$($bootstrapValues.kv.name)'..."
    az keyvault delete --name $bootstrapValues.kv.name --resource-group $bootstrapValues.kv.resourceGroup --yes
}