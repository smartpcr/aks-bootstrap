<#
 # Validating env yaml files, make sure the following are unique within subscription
 # 1) vault name
 # 2) spn name (3, deployment spn, aks server spn and aks client spn)
 # 3) acr name
 # 4) appInsights
 # 4) cosmosdb account
 #>

param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "xd"
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
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CosmosDb.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "ValidateEnvSettings"
LogStep -Message "Login to azure ..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

LogStep -Message "Validating resource group..."
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

LogStep -Message "Verifying key vault name '$($bootstrapValues.kv.name)'..."
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

        LogInfo -Message "clean up Key Vault $($bootstrapValues.kv.name)..."
        az keyvault delete --resource-group $bootstrapValues.kv.resourceGroup --name $($bootstrapValues.kv.name)
    }
    catch {
        throw "Invalid vault name: $($bootstrapValues.kv.name)"
    }
}

LogStep -Message "Verifying SPNs..."
$spnNames = New-Object System.Collections.ArrayList
if (-not ($spnNames -contains $bootstrapValues.global.servicePrincipal)) {
    $spnNames.Add($bootstrapValues.global.servicePrincipal) | Out-Null
}
if (-not ($spnNames -contains $bootstrapValues.terraform.servicePrincipal)) {
    $spnNames.Add($bootstrapValues.terraform.servicePrincipal) | Out-Null
}
if (-not ($spnNames -contains $bootstrapValues.aks.servicePrincipal)) {
    $spnNames.Add($bootstrapValues.aks.servicePrincipal) | Out-Null
}
if (-not ($spnNames -contains $bootstrapValues.aks.clientAppName)) {
    $spnNames.Add($bootstrapValues.aks.clientAppName) | Out-Null
}
$spnNames | ForEach-Object {
    $spnName = $_
    $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
    if (!$sp) {
        try {
            LogInfo -Message "Try creating spn '$spnName'..."
            az ad sp create-for-rbac `
                --name $spnName `
                --password "fake-password" `
                --role="Contributor" `
                --scopes=$scopes | Out-Null

            LogInfo -Message "Clean up spn '$spnName'..."
            $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
            az ad sp delete --id $sp.appId | Out-Null
        }
        catch {
            throw "Unable to create service principal '$spnName'"
        }
    }
}

LogStep -Message "Verifying app insights account..."
$existingAppInsights = az resource list --resource-group $bootstrapValues.appInsights.resourceGroup --name $bootstrapValues.appInsights.name | ConvertFrom-Json
if (!$existingAppInsights -or ($existingAppInsights -is [array] -and $existingAppInsights.Count -eq 0)) {
    try {
        $templateFolder = Join-Path $envRootFolder "templates"
        if (-not (Test-Path $templateFolder)) {
            New-Item -Path $templateFolder -ItemType Directory | Out-Null
        }
        $appInsightTemplateFile = Join-Path $templateFolder "AppInsights.json"
        ('{"Application_Type":"' + $bootstrapValues.appInsights.applicationType + ')"}') | Out-File $appInsightTemplateFile
        LogInfo -Message "Try creating app insights '$($bootstrapValues.appInsights.name)'..."
        az resource create `
            --resource-group $bootstrapValues.appInsights.resourceGroup `
            --resource-type "Microsoft.Insights/components" `
            --name $bootstrapValues.appInsights.name `
            --location $bootstrapValues.global.location `
            --properties "@$appInsightTemplateFile" | Out-Null

        LogInfo -Message "Clean up app insights '$($bootstrapValues.appInsights.name)'..."
        az resource delete `
            --resource-group $bootstrapValues.appInsights.resourceGroup `
            --resource-type "Microsoft.Insights/components" `
            --name $bootstrapValues.appInsights.name
    }
    catch {
        throw "Failed to creating app insights with name '$($bootstrapValues.appInsights.name)'"
    }
}

LogStep -Message "Verifying cosmos db account..."
$accountSettings = New-Object System.Collections.ArrayList
if ($bootstrapValues.global.components.docDb -and $bootstrapValues.cosmosdb.docDb.account) {
    if (([string]$bootstrapValues.cosmosdb.docDb.account).Length -gt 30) {
        throw "Account name '$($bootstrapValues.cosmosdb.docDb.account)' length cannot exceed 30 characters"
    }

    $cosmosdbSetting = @{
        account       = $bootstrapValues.cosmosdb.docDb.account
        api           = $bootstrapValues.cosmosdb.docDb.api
        resourceGroup = $bootstrapValues.cosmosdb.docDb.resourceGroup
        location      = $bootstrapValues.cosmosdb.docDb.location
    }
    $accountSettings.Add($cosmosdbSetting) | Out-Null
}
if ($bootstrapValues.global.components.graphDb -and $bootstrapValues.cosmosdb.graphDb.account) {
    $cosmosdbSetting = @{
        account       = $bootstrapValues.cosmosdb.graphDb.account
        api           = $bootstrapValues.cosmosdb.graphDb.api
        resourceGroup = $bootstrapValues.cosmosdb.graphDb.resourceGroup
        location      = $bootstrapValues.cosmosdb.graphDb.location
    }
    $accountSettings.Add($cosmosdbSetting) | Out-Null
}
if ($bootstrapValues.global.components.mongoDb -and $bootstrapValues.cosmosdb.mongoDb.account) {
    $cosmosdbSetting = @{
        account       = $bootstrapValues.cosmosdb.mongoDb.account
        api           = $bootstrapValues.cosmosdb.mongoDb.api
        resourceGroup = $bootstrapValues.cosmosdb.mongoDb.resourceGroup
        location      = $bootstrapValues.cosmosdb.mongoDb.location
    }
    $accountSettings.Add($cosmosdbSetting) | Out-Null
}
$accountSettings | ForEach-Object {
    $accountSetting = $_
    $dbAcct = az cosmosdb list --query "[?name=='$($accountSetting.account)']" | ConvertFrom-Json
    if (!$dbAcct) {
        try {
            EnsureCosmosDbAccount -AccountName $accountSetting.account -API $accountSetting.api -ResourceGroupName $accountSetting.resourceGroup -Location $accountSetting.location
            az cosmosdb delete --name $accountSetting.account --resource-group $accountSetting.resourceGroup | Out-Null
        }
        catch {
            throw "Unable to create cosmosdb account '$($accountSetting.account)'"
        }
    }
}
