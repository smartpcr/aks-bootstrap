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
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-Terraform"
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

LogStep -Step 1 -Message "Ensure terraform resource group '$($bootstrapValues.terraform.resourceGroup)' is created..."
az group create --name $bootstrapValues.terraform.resourceGroup --location $bootstrapValues.terraform.location | Out-Null

LogStep -Step 2 -Message "Ensure terraform service principal '$($bootstrapValues.terraform.servicePrincipal)' is created..."
Get-OrCreateAksServicePrincipal `
    -ServicePrincipalName $bootstrapValues.terraform.servicePrincipal `
    -ServicePrincipalPwdSecretName $bootstrapValues.terraform.servicePrincipalSecretName `
    -VaultName $($bootstrapValues.kv.name) `
    -EnvRootFolder $envRootFolder `
    -EnvName $EnvName `
    -SpaceName $SpaceName `
    -ForceResetSpn $bootstrapValues.aks.forceResetSpn | Out-Null

LogInfo -Message "set groupMembershipClaims to [All] to spn '$($bootstrapValues.terraform.servicePrincipal)'"
$terraformSpn = az ad sp list --display-name $bootstrapValues.terraform.servicePrincipal | ConvertFrom-Json
$terraformServerApp = az ad app show --id $terraformSpn.appId | ConvertFrom-Json
if ($terraformServerApp.groupMembershipClaims -and $terraformServerApp.groupMembershipClaims -eq "All") {
    LogInfo -Message "AKS server app manifest property 'groupMembershipClaims' is already set to true"
}
else {
    az ad app update --id $terraformSpn.appId --set groupMembershipClaims=All | Out-Null
}

LogInfo -Message "Granting spn '$($bootstrapValues.terraform.servicePrincipal)' 'Contributor' role to resource group '$($bootstrapValues.aks.resourceGroup)'"
$existingAssignments = az role assignment list `
    --assignee $terraformSpn.appId `
    --role Contributor `
    --resource-group $bootstrapValues.terraform.resourceGroup | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create `
        --assignee $terraformSpn.appId `
        --role Contributor `
        --resource-group $bootstrapValues.terraform.resourceGroup | Out-Null
}

LogStep -Step 2 -Message "Creating storage '$($bootstrapValues.terraform.stateStorageAccountName)' for terraform state..."
$storageAccount = az storage account show --resource-group $bootstrapValues.terraform.resourceGroup --name $bootstrapValues.terraform.stateStorageAccountName | ConvertFrom-Json
if (!$storageAccount) {
    az storage account create `
        --name $bootstrapValues.terraform.stateStorageAccountName `
        --resource-group $bootstrapValues.terraform.resourceGroup `
        --location $bootstrapValues.terraform.location `
        --sku Standard_LRS | Out-Null

    $rgName = $bootstrapValues.terraform.resourceGroup
    $accountName = $bootstrapValues.terraform.stateStorageAccountName
    $storageKeys = az storage account keys list -g $rgName -n $accountName | ConvertFrom-Json
    $storageKey = $storageKeys[0].value

    $containerName = $bootstrapValues.terraform.stateBlobContainerName
    LogInfo -Message "Ensure container '$containerName' is created..."
    $blobContainer = az storage container show --name $containerName --account-key $storageKey | ConvertFrom-Json
}
else {
    LogInfo "Storage account '$($bootstrapValues.terraform.stateStorageAccountName)' is already created."
}



