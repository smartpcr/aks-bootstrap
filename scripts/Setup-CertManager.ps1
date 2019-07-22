
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
LogTitle -Message "Setting up cert-manager, lets-encrypt to automate wildcard ssl cert creation and trust in environment '$EnvName/$SpaceName'..."


LogStep -Step 1 -Message "Login azure and connect to aks ..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin


# LogStep -Step 2 -Message "Creating wildcard tls cert"
# $sslCertSecretBundle = az keyvault secret show --name $bootstrapValues.dns.sslCert --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
# if (!$sslCertSecretBundle) {
#     New-WildcardSslCert `
#         -domainName $bootstrapValues.dns.domain `
#         -CertSubject "/CN=*.$($bootstrapValues.dns.domain)" `
#         -CertSecret $bootstrapValues.dns.sslCert `
#         -YamlsFolder $yamlsFolder `
#         -VaultName $bootstrapValues.kv.name
# }


LogStep -Step 2 -Message "Installing cert-manager..."
LogInfo -Message "Clearing previous installation..."
$existingHelmInstalation = helm list | grep cert-manager
if ($null -ne $existingHelmInstalation) {
    helm delete --purge cert-manager
    kubectl delete crd certificates.certmanager.k8s.io
    kubectl delete crd challenges.certmanager.k8s.io
    kubectl delete crd clusterissuers.certmanager.k8s.io
    kubectl delete crd issuers.certmanager.k8s.io
    kubectl delete crd orders.certmanager.k8s.io
    kubectl delete namespace cert-manager
}


LogInfo -Message "Following instruction here: https://docs.cert-manager.io/en/latest/getting-started/install/kubernetes.html"
kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true

LogInfo -Message "Helm install cert-manager from Jetstack..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install `
    --name cert-manager `
    --namespace cert-manager `
    --version v0.9.0-beta.0 jetstack/cert-manager `
    --set ingressShim.defaultIssuerName=letsencrypt `
    --set ingressShim.defaultIssuerKind=ClusterIssuer `
    --set ingressShim.defaultACMEChallengeType=dns01 

<# verify 
LogInfo -Message "Verifying cert-manager..."
LogInfo -Message "Waiting for helm deployment to complete..."
Start-Sleep -Seconds 15
$testYamlFile = Join-Path $templatesFolder "cert-manager-test.yaml"
kubectl apply -f $testYamlFile
LogInfo -Message "waiting for certificate creation..."
Start-Sleep -Seconds 5
kubectl describe certificate example-com-tls -n default
kubectl describe secret example-com-tls -n default
LogInfo -Message "Removing test cert, secret and issuer..."
kubectl delete Issuer example-com-issuer
kubectl delete Certificate example-com-tls
kubectl delete Secret example-com-tls
#>


# LogStep -Step 3 -Message "Create cluster issuer using letsencrypt"
# $clusterIssuerTemplateFile = Join-Path $templatesFolder "lets-encrypt-clusterissuer-prod.yaml"
# if ($null -ne $bootstrapValues.dns["letsencrypt"] -and $bootstrapValues.dns.letsencrypt.issuer -eq "staging") {
#     $clusterIssuerTemplateFile = Join-Path $templatesFolder "lets-encrypt-clusterissuer-staging.yaml"
# }
# $clusterIssuerTemplate = Get-Content $clusterIssuerTemplateFile -Raw
# $clusterIssuerTemplate = Set-YamlValues -valueTemplate $clusterIssuerTemplate -settings $bootstrapValues
# $clusterIssuerYamlFile = Join-Path $yamlsFolder "ClusterIssuer.yaml"
# $clusterIssuerTemplate | Out-File $clusterIssuerYamlFile -Encoding utf8 -Force | Out-Null
# kubectl apply -f $clusterIssuerYamlFile


# LogStep -Step 4 -Message "Testing tls with sample app"
# helm repo add azure-samples https://azure-samples.github.io/helm-charts/
# helm repo update
# helm install --name aks-helloworld --namespace ingress-basic azure-samples/aks-helloworld
# helm install --name aks-helloworld2 --namespace ingress-basic azure-samples/aks-helloworld --set title="AKS Ingress Demo" --set serviceName="ingress-demo"

# LogInfo "Getting public IP for ingress controller"
# kubectl get svc -n ingress-nginx
# $PublicIP = "52.250.117.235"
# $DnsName = "xiaodong"
# $pubIpId = $(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$PublicIP')].[id]" --output tsv)
# $pubIpDnsNameSetting = az network public-ip update --ids $pubIpId --dns-name $DnsName | ConvertFrom-Json
# LogInfo "FQDN=$($pubIpDnsNameSetting.dnsSettings.fqdn)"

# LogInfo "Applying ingress rules"
# $helloWorldIngressYamlFile = Join-Path $templatesFolder "AksHelloWorldIngress.yaml"
# ReplaceValuesInYamlFile -YamlFile $helloWorldIngressYamlFile -PlaceHolder "fqdn" -Value $pubIpDnsNameSetting.dnsSettings.fqdn
# kubectl apply -f $helloWorldIngressYamlFile

# $certMgrTemplateFile = Join-Path $templatesFolder "CertManager.yaml"
# $certMgrTemplate = Get-Content $certMgrTemplateFile -Raw
# $certMgrTemplate = Set-YamlValues -valueTemplate $certMgrTemplate -settings $bootstrapValues
# $certMgrYamlFile = Join-Path $yamlsFolder "CertManager.yaml"
# $certMgrTemplate | Out-File $certMgrYamlFile -Encoding utf8 -Force | Out-Null
# kubectl apply -f $certMgrYamlFile