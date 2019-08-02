
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong",
    [bool] $UseOldImage = $false
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
$templateFolder = Join-Path $envRootFolder "templates"
$secretBrokerTemplateFile = Join-Path $templateFolder "secret-broker.tpl"
if ($UseOldImage) {
    $secretBrokerTemplateFile = Join-Path $templateFolder "secret-broker.old.tpl"
}
if (-not (Test-Path $secretBrokerTemplateFile)) {
    throw "Unable to find secret broker template file: $secretBrokerTemplateFile"
}
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item $yamlsFolder -ItemType Directory -Force | Out-Null
}

Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up secret broker for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve settings..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin

if ($UseOldImage) {
    $bootstrapValues.geneva.secretBroker.image.tag = "394719"
}
else {
    $bootstrapValues.geneva.secretBroker.image.tag = "638876"
}

LogStep -Step 2 -Message "Setting secret broker yaml file and apply to k8s"
$secretBrokerYamlFile = Join-Path $yamlsFolder "secret-broker.yaml"
Copy-Item $secretBrokerTemplateFile -Destination $secretBrokerYamlFile -Force | Out-Null
ReplaceValuesInYamlFile -YamlFile $secretBrokerYamlFile -PlaceHolder "acr.name" -Value $bootstrapValues.acr.name
ReplaceValuesInYamlFile -YamlFile $secretBrokerYamlFile -PlaceHolder "service.image.tag" -Value $bootstrapValues.geneva.secretBroker.image.tag
ReplaceValuesInYamlFile -YamlFile $secretBrokerYamlFile -PlaceHolder "azAccount.tenantId" -Value $azAccount.tenantId
ReplaceValuesInYamlFile -YamlFile $secretBrokerYamlFile -PlaceHolder "aks.clusterName" -Value $bootstrapValues.aks.clusterName
kubectl apply -f $secretBrokerYamlFile