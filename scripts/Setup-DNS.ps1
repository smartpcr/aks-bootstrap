
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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
$templatesFolder = Join-Path $envRootFolder "templates"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
}

Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up DNS records/zone for environment '$EnvName'..."


LogStep -Step 1 -Message "Login azure and connect to aks ..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin
$aks = az aks show --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | ConvertFrom-Json
$bootstrapValues.aks["fqdn"] = $aks.fqdn

LogStep -Step 2 -Message "Make sure nginx is deployed, which is required by external-dns"

LogInfo -Message "Create K8S secret for docker registry in namespace 'ingress-nginx'..."
$acr = az acr show -g $bootstrapValues.acr.resourceGroup -n $bootstrapValues.acr.name | ConvertFrom-Json
az acr login -n $bootstrapValues.acr.name
$acrPassword = "$(az acr credential show -n $($bootstrapValues.acr.name) --query ""passwords[0].value"")"
$acrOwnerEmail = $bootstrapValues.acr.email
$acrLoginServer = $acr.loginServer
kubectl create secret docker-registry acr-auth `
    --docker-server $acrLoginServer `
    --docker-username $bootstrapValues.acr.name `
    --docker-password $acrPassword `
    --docker-email $acrOwnerEmail -n ingress-nginx

LogInfo -Message "create nginx controller and default backend..."
$nginxTemplateFile = Join-Path $templatesFolder "nginx.yaml"
$nginxTemplate = Get-Content $nginxTemplateFile -Raw
$nginxTemplate = Set-YamlValues -valueTemplate $nginxTemplate -settings $bootstrapValues
$nginxYamlFile = Join-Path $yamlsFolder "nginx.yaml"
$nginxTemplate | Out-File $nginxYamlFile -Encoding utf8 -Force | Out-Null
kubectl apply -f $nginxYamlFile


LogInfo -Message "Retrieving aks spn '$($bootstrapValues.aks.servicePrincipal)' and password..."
$aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
if (!$aksSpn) {
    throw "AKS service principal is not setup yet"
}
$aksClientApp = az ad app list --display-name $bootstrapValues.aks.clientAppName | ConvertFrom-Json
if (!$aksClientApp) {
    throw "AKS client app is not setup yet"
}
$aksSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
$aksSpnPwd = "$(az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksSpnPwdSecretName --query ""value"" -o tsv)"
$dnsRg = az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | ConvertFrom-Json


LogStep -Step 2 -Message "create k8s secret to store dns credential..."
$dnsSecret = @{
    tenantId        = $azAccount.tenantId
    subscriptionId  = $azAccount.id
    aadClientId     = $aksSpn.appId
    aadClientSecret = $aksSpnPwd
    resourceGroup   = $bootstrapValues.dns.resourceGroup
  } | ConvertTo-JSON -Compress
SetSecret -Name "external-dns-config-file" -Key "azure.json" -Value $dnsSecret -Namespace "default" -ScriptFolder $scriptFolder -EnvRootFolder $envRootFolder


LogStep -Step 3 -Message "Creating dns zone in azure..."
az group create --name $bootstrapValues.dns.resourceGroup --location $bootstrapValues.global.location | Out-Null
$dnsZone = az network dns zone show -g $bootstrapValues.dns.resourceGroup -n $bootstrapValues.dns.domain | ConvertFrom-Json
if ($null -eq $dnsZone) {
    $dnsZone = az network dns zone create -g $bootstrapValues.dns.resourceGroup -n $bootstrapValues.dns.domain | ConvertFrom-Json
}


LogStep -Step 4 -Message "Granting aks spn '$($bootstrapValues.aks.servicePrincipal)' contributor access to dns zone '$($bootstrapValues.dns.domain)'"
$existingAssignments = az role assignment list --role "Reader" --assignee $aksSpn.appId --scope $dnsRg.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --role "Reader" --assignee $aksSpn.appId --scope $dnsRg.id | Out-Null
}
$existingAssignments = az role assignment list --role "Contributor" --assignee $aksSpn.appId --scope $dnsZone.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --role "Contributor" --assignee $aksSpn.appId --scope $dnsZone.id | Out-Null
}


LogStep -Step 5 -Message "Setup k8s external-dns..."
$externalDnsTemplateFile = Join-Path $templatesFolder "external-dns.yaml"
$externalDnsTemplate = Get-Content $externalDnsTemplateFile -Raw
$externalDnsTemplate = Set-YamlValues -valueTemplate $externalDnsTemplate -settings $bootstrapValues
$externalDnsYamlFile = Join-Path $yamlsFolder "external-dns.yaml"
$externalDnsTemplate | Out-File $externalDnsYamlFile -Encoding utf8 -Force | Out-Null
kubectl apply -f $externalDnsYamlFile