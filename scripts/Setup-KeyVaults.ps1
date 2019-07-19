param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "rrdu",
    [bool] $IsLocal = $true
)

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

LogStep -Step 1 -Message "Ensure resource groups are created..."
$groupNames = New-Object System.Collections.ArrayList
if (-not ($groupNames -contains $bootstrapValues.global.resourceGroup)) {
    $groupNames.Add($bootstrapValues.global.resourceGroup) | Out-Null
}
if (-not ($groupNames -contains $bootstrapValues.kv.resourceGroup)) {
    $groupNames.Add($bootstrapValues.kv.resourceGroup) | Out-Null
}
if (-not ($groupNames -contains $bootstrapValues.acr.resourceGroup)) {
    $groupNames.Add($bootstrapValues.acr.resourceGroup) | Out-Null
}
if (-not ($groupNames -contains $bootstrapValues.terraform.resourceGroup)) {
    $groupNames.Add($bootstrapValues.terraform.resourceGroup) | Out-Null
}
if (-not ($groupNames -contains $bootstrapValues.aks.resourceGroup)) {
    $groupNames.Add($bootstrapValues.aks.resourceGroup) | Out-Null
}
if (-not ($groupNames -contains $bootstrapValues.appInsights.resourceGroup)) {
    $groupNames.Add($bootstrapValues.appInsights.resourceGroup) | Out-Null
}
if ($bootstrapValues.cosmosdb) {
    if ($bootstrapValues.cosmosdb.docDb) {
        if (-not ($groupNames -contains $bootstrapValues.cosmosdb.docDb.resourceGroup)) {
            $groupNames.Add($bootstrapValues.cosmosdb.docDb.resourceGroup) | Out-Null
        }
    }
    if ($bootstrapValues.cosmosdb.graphDb) {
        if (-not ($groupNames -contains $bootstrapValues.cosmosdb.graphDb.resourceGroup)) {
            $groupNames.Add($bootstrapValues.cosmosdb.graphDb.resourceGroup) | Out-Null
        }
    }
    if ($bootstrapValues.cosmosdb.mongoDb) {
        if (-not ($groupNames -contains $bootstrapValues.cosmosdb.mongoDb.resourceGroup)) {
            $groupNames.Add($bootstrapValues.cosmosdb.mongoDb.resourceGroup) | Out-Null
        }
    }
}
$groupNames | ForEach-Object {
    $rgName = $_
    az group create --name $rgName --location $bootstrapValues.global.location | Out-Null
}

LogStep -Step 2 -Message "Ensure key vaults are created..."
$kvs = az keyvault list --resource-group $bootstrapValues.kv.resourceGroup --query "[?name=='$($bootstrapValues.kv.name)']" | ConvertFrom-Json
if ($kvs.Count -eq 0) {

    try {
        LogInfo -Message "Try creating Key Vault $($bootstrapValues.kv.name)..."

        az keyvault create `
            --resource-group $bootstrapValues.kv.resourceGroup `
            --name $($bootstrapValues.kv.name) `
            --sku standard `
            --location $bootstrapValues.global.location `
            --enabled-for-deployment $true `
            --enabled-for-disk-encryption $true `
            --enabled-for-template-deployment $true | Out-Null
    }
    catch {
        throw "Invalid vault name: $($bootstrapValues.kv.name)"
    }
}
