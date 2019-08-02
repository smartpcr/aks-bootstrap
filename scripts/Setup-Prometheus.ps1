
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodoli"
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
$templatesFolder = Join-Path $envRootFolder "templates"
$moduleFolder = Join-Path $scriptFolder "modules"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item $yamlsFolder -ItemType Directory -Force | Out-Null
}
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up prometheus for AKS cluster in '$EnvName'..."
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -SpaceName $SpaceName -EnvRootFolder $envRootFolder
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -AsAdmin -SpaceName $SpaceName


LogStep -Step 2 -Message "Install prometheus-operator..."
$nsMonitorYaml = @"
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
"@
$monitoringNamespaceYaml = Join-Path $yamlsFolder "monitoringNamespaceYaml.yaml"
$nsMonitorYaml | Out-File $monitoringNamespaceYaml -Encoding utf8
kubectl apply -f $monitoringNamespaceYaml

# kubectl get secret $bootstrapValues.dns.sslCert -o yaml --export | kubectl apply --namespace monitoring -f -

$prometheusTemplateFile = Join-Path $templatesFolder "prometheus-ingress.yaml"
$prometheusTemplate = Get-Content $prometheusTemplateFile -Raw
$prometheusTemplate = Set-YamlValues -valueTemplate $prometheusTemplate -settings $bootstrapValues
$prometheusYamlFile = Join-Path $yamlsFolder "prometheus-values.yaml"
$prometheusTemplate | Out-File $prometheusYamlFile -Encoding utf8 -Force | Out-Null

$existingDeployment = helm list | grep prometheus
if ($null -ne $existingDeployment) {
    helm delete prometheus --purge
    kubectl delete crd alertmanagers.monitoring.coreos.com
    kubectl delete crd prometheuses.monitoring.coreos.com
    kubectl delete crd prometheusrules.monitoring.coreos.com
    kubectl delete crd servicemonitors.monitoring.coreos.com
    kubectl delete crd podmonitors.monitoring.coreos.com
    kubectl delete namespace monitoring

    LogInfo -Message "Waiting resource to be cleaned up..."
    Start-Sleep -Seconds 10
}

helm install --namespace monitoring --name prometheus --version "6.0.0" -f $prometheusYamlFile stable/prometheus-operator

