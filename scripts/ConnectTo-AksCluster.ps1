param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "taufiq",
    [switch] $AsAdmin,
    [switch] $ShowDashboard,
    [switch] $UseProxy,
    [int] $Port = 8082
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
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "ConnectTo-AksCluster"
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
if ($AsAdmin) {
    az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin --overwrite-existing
}
else {
    az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --overwrite-existing | Out-Null
}

$currentContextName = "$(kubectl config current-context)"
Write-Host "You are now connected to kubenetes context: '$currentContextName'" -ForegroundColor Green

if ($ShowDashboard) {
    Write-Host "Browse aks dashboard..." -ForegroundColor Green
    Write-Host "Make sure AKS cluster AAD app ($($bootstrapValues.aks.servicePrincipal)) required permission is granted" -ForegroundColor Yellow
    Write-Host "Make sure AKS client AAD app ($($bootstrapValues.aks.clientAppName)) required permission is granted" -ForegroundColor Yellow

    $isMac = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.OS.Contains("Darwin"))
    if ($isMac) {
        if ($UseProxy) {
            Invoke-Expression "kubectl proxy --port=$Port &"
        }
        else {
            Invoke-Expression "az aks browse --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName) --listen-port $Port &"
        }
    }
    else {
        if ($UseProxy) {
            Start-Process powershell "kubectl proxy --port=$Port"
        }
        else {
            Start-Process powershell "az aks browse --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName) --listen-port $Port"
        }
    }

    $dashboardUrl = "http://localhost:$($Port)/api/v1/namespaces/kube-system/services/http:kubernetes-dashboard:/proxy/#!/overview?namespace=default"
    if ($isMac) {
        & open $dashboardUrl
    }
    else {
        Start-Process $dashboardUrl
    }
}
