param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "rrdp"
)

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envRootFolder = Join-Path $gitRootFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up App Insights for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retriing app insights settings..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -SpaceName $SpaceName -EnvRootFolder $envRootFolder
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
$existingAppInsights = az resource list --resource-group $bootstrapValues.appInsights.resourceGroup --name $bootstrapValues.appInsights.name | ConvertFrom-Json
if (!$existingAppInsights -or ($existingAppInsights -is [array] -and $existingAppInsights.Count -eq 0)) {
    $templateFolder = Join-Path $envRootFolder "templates"
    if (-not (Test-Path $templateFolder)) {
        New-Item -Path $templateFolder -ItemType Directory | Out-Null
    }
    $appInsightTemplateFile = Join-Path $templateFolder "AppInsights.json"
    ('{"Application_Type":"' + $bootstrapValues.appInsights.applicationType + ')"}') | Out-File $appInsightTemplateFile
    LogInfo -Message "Creating app insights '$($bootstrapValues.appInsights.name)'..."
    az resource create `
        --resource-group $bootstrapValues.appInsights.resourceGroup `
        --resource-type "Microsoft.Insights/components" `
        --name $bootstrapValues.appInsights.name `
        --location $bootstrapValues.global.location `
        --properties "@$appInsightTemplateFile" | Out-Null
}
else {
    LogInfo -Message "App insights with name '$($bootstrapValues.appInsights.name)' is already created."
}

$instrumentationKey = az resource show -g $bootstrapValues.appInsights.resourceGroup -n $bootstrapValues.appInsights.name --resource-type "Microsoft.Insights/components" --query properties.InstrumentationKey
az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.appInsights.instrumentationKeySecret --value $instrumentationKey | Out-Null