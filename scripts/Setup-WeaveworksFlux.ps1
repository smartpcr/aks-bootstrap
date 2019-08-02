
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "rrdp"
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
$credentialFolder = Join-Path $scriptFolder "credential"
if (-not (Test-Path $credentialFolder)) {
    New-Item $credentialFolder -ItemType Directory -Force | Out-Null
}
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AksUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-WeaveworksFlux"
LogStep -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin


LogStep -Message "Retrieving github repo '$($bootstrapValues.flux.repo)' deployment key..."
[array]$deployPubKeyFound = az keyvault secret list `
    --vault-name $bootstrapValues.kv.name `
    --query "[?name=='$($bootstrapValues.flux.deployPublicKey)']" | ConvertFrom-Json
[array]$deployPrivateKeyFound = az keyvault secret list `
    --vault-name $bootstrapValues.kv.name `
    --query "[?name=='$($bootstrapValues.flux.deployPrivateKey)']" | ConvertFrom-Json
$sshKeyFile = Join-Path $credentialFolder "git-$($bootstrapValues.flux.user)"
if (Test-Path $sshKeyFile) {
    Remove-Item $sshKeyFile -Force
}
if ($null -eq $deployPrivateKeyFound -or $null -eq $deployPubKeyFound -or $deployPrivateKeyFound.Count -eq 0 -or $deployPubKeyFound.Count -eq 0) {
    ssh-keygen -b 4096 -t rsa -f $sshKeyFile
    az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.flux.deployPrivateKey --file $sshKeyFile | Out-Null
    az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.flux.deployPublicKey --file "$($sshKeyFile).pub" | Out-Null
}
else {
    az keyvault secret download --vault-name $bootstrapValues.kv.name --name $bootstrapValues.flux.deployPrivateKey -e base64 -f $sshKeyFile
    az keyvault secret download --vault-name $bootstrapValues.kv.name --name $bootstrapValues.flux.deployPublicKey -e base64 -f "$($sshKeyFile).pub"
}

$pubKeyContent = Get-Content "$($sshKeyFile).pub"
LogInfo -Message "publick key: '$($bootstrapValues.flux.deployPublicKey)'`n$($pubKeyContent)"
LogInfo -Message "navigate to https://github.com/smartpcr/flux/settings/keys and add public deploy key"
Read-Host "Hit enter after add deploy key to github manually"


LogStep -Message "Add flux"
helm repo add fluxcd https://fluxcd.github.io/flux
helm repo update 



LogStep -Message "Apply terraform variables binding..."
AddAdditionalAksProperties -bootstrapValues $bootstrapValues
PopulateTerraformProperties -bootstrapValues $bootstrapValues
$bootstrapValues.flux["deployPrivateKeyFile"] = $sshKeyFile
$terraformFolder = Join-Path $envRootFolder "terraform"
$azureSimpleFolder = Join-Path $terraformFolder "azure-simple"
$tfVarFile = Join-Path $azureSimpleFolder "terraform.tfvars"
$tfVarContent = Get-Content $tfVarFile -Raw
$tfVarContent = Set-YamlValues -ValueTemplate $tfVarContent -Settings $bootstrapValues
$terraformOutputFolder = Join-Path $scriptFolder "terraform"
if (-not (Test-Path $terraformOutputFolder)) {
    New-Item $terraformOutputFolder -ItemType Directory -Force | Out-Null
}
$azureSimpleOutputFolder = Join-Path $terraformOutputFolder "azure-simple"
if (-not (Test-Path $azureSimpleOutputFolder)) {
    New-Item $azureSimpleOutputFolder -ItemType Directory -Force | Out-Null
}
LogInfo "Write terraform output to '$azureSimpleOutputFolder'"
$tfVarContent | Out-File (Join-Path $azureSimpleOutputFolder "terraform.tfvars") -Force
Copy-Item (Join-Path $azureSimpleFolder "main.tf") -Destination (Join-Path $azureSimpleOutputFolder "main.tf") -Force
Copy-Item (Join-Path $azureSimpleFolder "variables.tf") -Destination (Join-Path $azureSimpleOutputFolder "variables.tf") -Force
Set-Location $azureSimpleOutputFolder
terraform init


helm repo add fluxcd https://fluxcd.github.io/flux
helm install --name flux `
    --set git.url=git@github.com:weaveworks/flux-get-started `
    --namespace flux `
    fluxcd/flux