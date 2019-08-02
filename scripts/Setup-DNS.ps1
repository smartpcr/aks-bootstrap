
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
$moduleFolder = Join-Path $scriptFolder "modules"
$templatesFolder = Join-Path $envRootFolder "templates"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
}

Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-DNS"
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
$existingDockerReg = kubectl get secret -n ingress-nginx | grep acr-auth
if ($null -eq $existingDockerReg) {
    kubectl create secret docker-registry acr-auth `
        --docker-server $acrLoginServer `
        --docker-username $bootstrapValues.acr.name `
        --docker-password $acrPassword `
        --docker-email $acrOwnerEmail -n ingress-nginx
}


LogInfo -Message "create nginx controller and default backend..."
$nginxTemplateFile = Join-Path $templatesFolder "nginx.yaml"
$nginxTemplate = Get-Content $nginxTemplateFile -Raw
$nginxTemplate = Set-YamlValues -valueTemplate $nginxTemplate -settings $bootstrapValues
$nginxYamlFile = Join-Path $yamlsFolder "nginx.yaml"
$nginxTemplate | Out-File $nginxYamlFile -Encoding utf8 -Force | Out-Null
kubectl apply -f $nginxYamlFile


LogInfo -Message "Retrieving aks spn '$($bootstrapValues.aks.clusterName)' and password..."
[array]$aksClusterSpns = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
if ($null -eq $aksClusterSpns -or $aksClusterSpns.Length -ne 1) {
    throw "AKS service principal is not setup yet"
}
$aksClusterSpn = $aksClusterSpns[0]

$aksClusterSpnPwdSecretName = "$($bootstrapValues.aks.clusterName)-password"
$aksSpnPwd = "$(az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksClusterSpnPwdSecretName --query ""value"" -o tsv)"
$dnsRg = az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | ConvertFrom-Json


LogStep -Step 2 -Message "create k8s secret to store dns credential..."
$dnsSecret = @{
    tenantId        = $azAccount.tenantId
    subscriptionId  = $azAccount.id
    aadClientId     = $aksClusterSpn.appId
    aadClientSecret = $aksSpnPwd
    resourceGroup   = $bootstrapValues.dns.resourceGroup
  } | ConvertTo-JSON -Compress
SetSecret -Name "external-dns-config-file" -Key "azure.json" -Value $dnsSecret -Namespace "default" -ScriptFolder $scriptFolder -EnvRootFolder $envRootFolder


LogStep -Step 3 -Message "Creating dns zone in azure..."
az group create --name $bootstrapValues.dns.resourceGroup --location $bootstrapValues.global.location | Out-Null
[array]$dnsZonesFound = az network dns zone list -g $bootstrapValues.dns.resourceGroup --query "[?name=='$($bootstrapValues.dns.domain)']" | ConvertFrom-Json
if ($null -eq $dnsZonesFound -or $dnsZonesFound.Length -eq 0) {
    $dnsZone = az network dns zone create -g $bootstrapValues.dns.resourceGroup -n $bootstrapValues.dns.domain | ConvertFrom-Json
}
else {
    $dnsZone = $dnsZonesFound[0]
    LogInfo "DNS zone '$($bootstrapValues.dns.domain)' alread created."
}


LogStep -Step 4 -Message "Add CAA record to allow letsencrypt perform authorization..."
$caaRecords = az network dns record-set caa list `
    --resource-group $bootstrapValues.dns.resourceGroup `
    --zone-name $bootstrapValues.dns.domain | ConvertFrom-Json
$letsencryptCaaRecord = $caaRecords | Where-Object { $_.name -eq $bootstrapValues.global.envName }
if ($null -eq $letsencryptCaaRecord) {
    LogInfo -Message "Adding caa record 'letsencrypt'..."
    az network dns record-set caa add-record `
        -g $bootstrapValues.dns.resourceGroup `
        -z $bootstrapValues.dns.domain `
        -n $bootstrapValues.global.envName `
        --flags 0 `
        --tag "issue" `
        --value "letsencrypt.org" | Out-Null
}
else {
    LogInfo -Message "Caa record '$($bootstrapValues.global.envName)' already added."
}


LogStep -Step 5 -Message "Granting aks spn '$($bootstrapValues.aks.clusterName)' contributor access to dns zone '$($bootstrapValues.dns.domain)'"
$existingAssignments = az role assignment list --role "Reader" --assignee $aksClusterSpn.appId --scope $dnsRg.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --role "Reader" --assignee $aksClusterSpn.appId --scope $dnsRg.id | Out-Null
}
$existingAssignments = az role assignment list --role "DNS Zone Contributor" --assignee $aksClusterSpn.appId --scope $dnsZone.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --role "DNS Zone Contributor" --assignee $aksClusterSpn.appId --scope $dnsZone.id | Out-Null
}


LogStep -Step 6 -Message "Setup k8s external-dns..."
$externalDnsTemplateFile = Join-Path $templatesFolder "external-dns.yaml"
$externalDnsTemplate = Get-Content $externalDnsTemplateFile -Raw
$externalDnsTemplate = Set-YamlValues -valueTemplate $externalDnsTemplate -settings $bootstrapValues
$externalDnsYamlFile = Join-Path $yamlsFolder "external-dns.yaml"
$externalDnsTemplate | Out-File $externalDnsYamlFile -Encoding utf8 -Force | Out-Null
kubectl apply -f $externalDnsYamlFile