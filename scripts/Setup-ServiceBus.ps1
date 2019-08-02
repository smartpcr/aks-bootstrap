
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "rrdu"
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

$envRootFolder = Join-Path $gitRootFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up AKS cluster for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve settings..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

LogStep -Step 2 -Message "Ensure service bus namespace '$($bootstrapValues.servicebus.name)' is created..."
$serviceBusesFound = az servicebus namespace list --resource-group $bootstrapValues.servicebus.resourceGroup --query "[?name=='$($bootstrapValues.servicebus.name)']" | ConvertFrom-Json
if (!$serviceBusesFound -or ([array]$serviceBusesFound).Length -eq 0) {
    LogInfo "Creating service bus namespace '$($bootstrapValues.servicebus.name)'..."
    az servicebus namespace create `
        --name $bootstrapValues.servicebus.name `
        --resource-group $bootstrapValues.servicebus.resourceGroup `
        --location $bootstrapValues.servicebus.location `
        --sku $bootstrapValues.servicebus.sku | Out-Null
}

LogStep -Step 3 -Message "Ensure queues are created..."
if ($bootstrapValues.servicebus.queues) {
    $bootstrapValues.servicebus.queues | ForEach-Object {
        $queue = $_
        $queuesFound = az servicebus queue list `
            --namespace-name $bootstrapValues.servicebus.name `
            --resource-group $bootstrapValues.servicebus.resourceGroup `
            --query "[?name=='$($queue.name)']" | ConvertFrom-Json
        if (!$queuesFound) {
            LogInfo -Message "Creating queue '$($queue.name)'..."
            az servicebus queue create `
                --name $queue.name `
                --namespace-name $bootstrapValues.servicebus.name `
                --resource-group $bootstrapValues.servicebus.resourceGroup | Out-Null
        }
        else {
            LogInfo -Message "Queue '$($queue.name)' is already created."
        }
    }
}

LogStep -Step 4 -Message "Ensure topics are created..."
if ($bootstrapValues.servicebus.topics) {
    $bootstrapValues.servicebus.topics | ForEach-Object {
        $topic = $_
        $topicsFound = az servicebus topic list `
            --namespace-name $bootstrapValues.servicebus.name `
            --resource-group $bootstrapValues.servicebus.resourceGroup `
            --query "[?name=='$($topic.name)']" | ConvertFrom-Json
        if (!$topicsFound) {
            LogInfo -Message "Creating topic '$($topic.name)'..."
            az servicebus topic create `
                --name $topic.name `
                --namespace-name $bootstrapValues.servicebus.name `
                --resource-group $bootstrapValues.servicebus.resourceGroup | Out-Null
        }
        else {
            LogInfo -Message "Topic '$($topic.name)' is already created."
        }
    }
}