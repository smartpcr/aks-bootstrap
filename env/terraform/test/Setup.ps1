
param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "rrdu"
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
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup"
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azureAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
$sp = az ad sp list --display-name $bootstrapValues.global.servicePrincipal | ConvertFrom-Json
$spPwd = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $bootstrapValues.terraform.servicePrincipalSecretName | ConvertFrom-Json

$Script:subscription_id = $azureAccount.id
$Script:tenant_id = $azureAccount.tenantId
$Script:client_id = $sp.appId
$Script:client_secret = $spPwd.value

$terraformFolder = Join-Path $envRootFolder "terraform"
$testFolder = Join-Path $terraformFolder "test"
Set-Location $testFolder

LogStep -Message "Setting up resource group..."
terraform init
terraform plan
terraform apply