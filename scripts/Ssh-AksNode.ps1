param(
    [string] $EnvName = "dev3",
    [string] $SpaceName = "xd",
    [string] $NodeName = "aks-nodepool1-33901137-0"
)


$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envFolder = Join-Path $gitRootFolder "env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Ssh-AksNode"
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -SpaceName $SpaceName -EnvRootFolder $envFolder
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | Out-Null
$kubeContextName = "$(kubectl config current-context)"
LogStep -Message "You are now connected to kubenetes context: '$kubeContextName'"


LogStep "Retrieve ip config selected vm"
$nodeResourceGroup = "$(az aks show --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName) --query nodeResourceGroup -o tsv)"
$vm = az vm show -g $nodeResourceGroup -n $NodeName | ConvertFrom-Json
[string]$pipId = $vm.networkProfile.networkInterfaces.id
$nicName = $pipId.Substring($pipId.LastIndexOf("/") + 1)
$ipConfig = az network nic ip-config list --nic-name $nicName -g $nodeResourceGroup | ConvertFrom-Json


LogStep -Message "Setup public IP for selected node"
$publicIpName = "jumpbox"
az network public-ip create -g $nodeResourceGroup -n $publicIpName | Out-Null
az network nic ip-config update -g $nodeResourceGroup --nic-name $nicName --name $ipConfig.name --public-ip-address $publicIpName | Out-Null
$pip = az network public-ip show -g $nodeResourceGroup -n $publicIpName | ConvertFrom-Json

<# in case you lose ssh key file
$password = Read-Host "Enter user password"
az vm user update `
    --resource-group $nodeResourceGroup `
    --name $NodeName `
    --username azureuser `
    --password $password

#>

ssh "$($bootstrapValues.aks.adminUsername)@$($pip.ipAddress)"


<# remove pip
az network public-ip delete -g $nodeResourceGroup -n $publicIpName
#>