
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodoli"
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

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-WeaveworksFlux"
LogStep -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin


LogStep -Message "Retrieving github repo '$($bootstrapValues.flux.repo)' deployment key..."
$sshKeyFile = Join-Path $credentialFolder "git-$($bootstrapValues.flux.user)"
if (Test-Path $sshKeyFile) {
    Remove-Item $sshKeyFile -Force
}
ssh-keygen -b 4096 -t rsa -f $sshKeyFile
az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.flux.tokenSecret --file $sshKeyFile | Out-Null


helm repo add fluxcd https://fluxcd.github.io/flux
helm install --name flux `
    --set git.url=git@github.com:weaveworks/flux-get-started `
    --namespace flux `
    fluxcd/flux