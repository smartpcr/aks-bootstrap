
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
LogTitle -Message "Setting up Lets-Encrypt for environment '$EnvName/$SpaceName'..."


LogStep -Step 1 -Message "Login azure and connect to aks ..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin
$aks = az aks show --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | ConvertFrom-Json
$bootstrapValues.aks["fqdn"] = $aks.fqdn


LogStep -Step 2 -Message "Retrieving aks cluster spn '$($bootstrapValues.aks.clusterName)' and save its password as k8s secret..."
$aksClusterSpn = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
if (!$aksClusterSpn) {
    throw "AKS cluster service principal '$($bootstrapValues.aks.clusterName)' is not setup yet"
}
$bootstrapValues.aks["clusterServicePrincipalAppId"] = $aksClusterSpn.appId
$bootstrapValues.global["tenantId"] = $azAccount.tenantId
$bootstrapValues.global["subscriptionId"] = $azAccount.id

$aksClusterSpnPwdSecretName = "$($bootstrapValues.aks.clusterName)-password"
$aksClusterSpnPwd = "$(az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksClusterSpnPwdSecretName --query ""value"" -o tsv)"

kubectl -n kube-system create secret generic azuredns-config --from-literal=client-secret=$aksClusterSpnPwd
kubectl -n cert-manager create secret generic azuredns-config --from-literal=client-secret=$aksClusterSpnPwd
kubectl -n default create secret generic azuredns-config --from-literal=client-secret=$aksClusterSpnPwd


LogInfo -Message "Grant permission to DNS zone..."
$dnsRg = az group create --name $bootstrapValues.dns.resourceGroup --location $bootstrapValues.dns.location | ConvertFrom-Json
if ($null -eq $dnsRg) {
    throw "Unable to find resource group '$bootstrapValues.dns.resourceGroup'"
}
$dnsZone = az network dns zone show -g $bootstrapValues.dns.resourceGroup -n $bootstrapValues.dns.domain | ConvertFrom-Json
if ($null -eq $dnsZone) {
    throw "Unable to find dns zone '$bootstrapValues.dns.domain'"
}
$existingAssignments = az role assignment list --role "Reader" --assignee $aksClusterSpn.appId --scope $dnsRg.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    LogInfo -Message "Granting reader permission on resource group '$($bootstrapValues.dns.resourceGroup)' to '$($bootstrapValues.aks.clusterName)'..."
    az role assignment create --role "Reader" --assignee $aksClusterSpn.appId --scope $dnsRg.id | Out-Null
}
else {
    LogInfo -Message "Reader permission already granted to '$($bootstrapValues.aks.clusterName)'"
}

$existingAssignments = az role assignment list --role "DNS Zone Contributor" --assignee $aksClusterSpn.appId --scope $dnsZone.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    LogInfo -Message "Granting contributor permission on dns zone '$($bootstrapValues.dns.domain)' to '$($bootstrapValues.aks.clusterName)'..."
    az role assignment create --role "DNS Zone Contributor" --assignee $aksClusterSpn.appId --scope $dnsZone.id | Out-Null
}
else {
    LogInfo -Message "Contributor permission already granted to '$($bootstrapValues.aks.clusterName)'"
}


$clusterIssuerName = "letsencrypt"
LogStep -Step 3 -Message "Deploy wildcard cluster issuer '$clusterIssuerName'..."
$clusterIssuerTemplateFile = Join-Path $templatesFolder "lets-encrypt-clusterissuer-prod.yaml"
if ($null -ne $bootstrapValues.dns["letsencrypt"] -and $bootstrapValues.dns.letsencrypt.issuer -eq "staging") {
    $clusterIssuerTemplateFile = Join-Path $templatesFolder "lets-encrypt-clusterissuer-staging.yaml"
}
$clusterIssuerTemplate = Get-Content $clusterIssuerTemplateFile -Raw
$clusterIssuerTemplate = Set-YamlValues -valueTemplate $clusterIssuerTemplate -settings $bootstrapValues
$clusterIssuerYamlFile = Join-Path $yamlsFolder "ClusterIssuer.yaml"
$clusterIssuerTemplate | Out-File $clusterIssuerYamlFile -Encoding utf8 -Force | Out-Null
$existingClusterIssuerFound = kubectl get clusterissuer | grep $clusterIssuerName
if ($null -ne $existingClusterIssuerFound) {
    kubectl delete clusterissuer $clusterIssuerName
}
kubectl apply -f $clusterIssuerYamlFile


LogStep -Step 4 -Message "Deploy wildcard certificate '$($bootstrapValues.dns.sslCert)'..."
$existingSslSecretFound = kubectl get secret | grep $bootstrapValues.dns.sslCert
if ($null -ne $existingSslSecretFound) {
    kubectl delete secret $bootstrapValues.dns.sslCert
}
$existingCertFound = kubectl get certificate | grep $bootstrapValues.dns.sslCert
if ($null -ne $existingCertFound) {
    kubectl delete certificate $bootstrapValues.dns.sslCert
}
$wildcardCertTemplateFile = Join-Path $templatesFolder "wildcard-cert-letsencrypt.yaml"
$wildcardCertTemplate = Get-Content $wildcardCertTemplateFile -Raw
$wildcardCertTemplate = Set-YamlValues -ValueTemplate $wildcardCertTemplate -Settings $bootstrapValues
$wildcardCertYamlFile = Join-Path $yamlsFolder "wildcard-cert.yaml"
$wildcardCertTemplate | Out-File $wildcardCertYamlFile -Encoding utf8 -Force | Out-Null
kubectl apply -f $wildcardCertYamlFile


# https://medium.com/@brentrobinson5/automating-certificate-management-with-azure-and-lets-encrypt-fee6729e2b78