<#
    this script retrieve settings based on target environment
    1) create azure resource group
    2) create key vault
    3) create certificate and add to key vault
    4) create service principle with cert auth
    5) grant permission to service principle
        a) key vault
        b) resource group
#>
param(
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
$moduleFolder = Join-Path $scriptFolder "modules"

Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-ServicePrincipal"
LogTitle "Setting Up Service Principal for Environment $EnvName"
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $envRootFolder -SpaceName $SpaceName

# login and set subscription
LogStep -Step 1 -Message "Login to azure and set subscription to '$($bootstrapValues.global.subscriptionName)'..."
$azureAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName

# create service principal (SPN) for cluster provision
LogStep -Step 2 -Message "Creating service principal '$($bootstrapValues.global.servicePrincipal)'..."
$sp = az ad sp list --display-name $bootstrapValues.global.servicePrincipal | ConvertFrom-Json
if ($null -eq $sp -or $sp.Length -eq 0) {
    LogInfo -Message "Creating service principal with name '$($bootstrapValues.global.servicePrincipal)'..."

    $certName = $($bootstrapValues.global.servicePrincipal)
    EnsureCertificateInKeyVault -VaultName $($bootstrapValues.kv.name) -CertName $certName -ScriptFolder $envRootFolder

    az ad sp create-for-rbac -n $($bootstrapValues.global.servicePrincipal) --role contributor --keyvault $($bootstrapValues.kv.name) --cert $certName | Out-Null
    $sp = az ad sp list --display-name $($bootstrapValues.global.servicePrincipal) | ConvertFrom-Json
    LogInfo -Message "Granting spn '$($bootstrapValues.global.servicePrincipal)' 'contributor' role to subscription"
    $existingAssignments = az role assignment list --assignee $sp.appId --role Owner --scope "/subscriptions/$($azureAccount.id)" | ConvertFrom-Json
    if ($existingAssignments.Count -eq 0) {
        az role assignment create --assignee $sp.appId --role Owner --scope "/subscriptions/$($azureAccount.id)" | Out-Null
    }
    else {
        LogInfo -Message "Assignment already exists."
    }

    LogInfo -Message "Granting spn '$($bootstrapValues.global.servicePrincipal)' permissions to keyvault '$($bootstrapValues.kv.name)'"
    az keyvault set-policy `
        --name $($bootstrapValues.kv.name) `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $sp.objectId `
        --spn $sp.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null
}
else {
    LogInfo -Message "Service principal '$($bootstrapValues.global.servicePrincipal)' already exists."
}


if ($bootstrapValues.global.components.aks -eq $true) {
    LogStep -Step 3 -Message "Ensuring AKS service principal '$($bootstrapValues.aks.servicePrincipal)' is created..."
    az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | Out-Null

    Get-OrCreateAksServicePrincipal `
        -ServicePrincipalName $bootstrapValues.aks.servicePrincipal `
        -ServicePrincipalPwdSecretName $bootstrapValues.aks.servicePrincipalPassword `
        -VaultName $($bootstrapValues.kv.name) `
        -EnvRootFolder $envRootFolder `
        -EnvName $EnvName `
        -SpaceName $SpaceName `
        -ForceResetSpn $bootstrapValues.aks.forceResetSpn | Out-Null

    $aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
    LogInfo -Message "set groupMembershipClaims to [All] to spn '$($bootstrapValues.aks.servicePrincipal)'"
    $aksServerApp = az ad app show --id $aksSpn.appId | ConvertFrom-Json
    if ($aksServerApp.groupMembershipClaims -and $aksServerApp.groupMembershipClaims -eq "All") {
        LogInfo -Message "AKS server app manifest property 'groupMembershipClaims' is already set to true"
    }
    else {
        az ad app update --id $aksSpn.appId --set groupMembershipClaims=All | Out-Null
    }

    # write to values.yaml
    LogInfo -Message "Granting spn '$($bootstrapValues.aks.servicePrincipal)' 'Contributor' role to resource group '$($bootstrapValues.aks.resourceGroup)'"
    $existingAssignments = az role assignment list `
        --assignee $aksSpn.appId `
        --role Contributor `
        --resource-group $bootstrapValues.aks.resourceGroup | ConvertFrom-Json
    if ($existingAssignments.Count -eq 0) {
        az role assignment create `
            --assignee $aksSpn.appId `
            --role Contributor `
            --resource-group $bootstrapValues.aks.resourceGroup | Out-Null
    }
    LogInfo -Message "Granting spn '$($bootstrapValues.aks.servicePrincipal)' permissions to keyvault '$($bootstrapValues.kv.name)'"
    az keyvault set-policy `
        --name $($bootstrapValues.kv.name) `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $aksSpn.objectId `
        --spn $aksSpn.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null

    LogInfo -Message "Ensuring AKS Client App '$($bootstrapValues.aks.clientAppName)' is created..."
    Get-OrCreateAksClientApp -EnvRootFolder $envRootFolder -EnvName $EnvName -SpaceName $SpaceName -ForceResetSpn $bootstrapValues.aks.forceResetSpn | Out-Null
}

# connect as service principal
LoginAsServicePrincipal -EnvName $EnvName -SpaceName $SpaceName -EnvRootFolder $envRootFolder
LogTitle "Remember to manually grant aad app request before creating aks cluster!"