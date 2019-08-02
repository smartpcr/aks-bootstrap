
param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong"
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
$templatesFolder = Join-Path $envRootFolder "templates"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
}
$moduleFolder = Join-Path $scriptFolder "modules"

Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AksUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlTemplates.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-GenevaService"
LogTitle -Message "Setting up AKS cluster for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and populate azure settings..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azureAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin


LogStep -Step 2 -Message "Retrieving AKS settings..."
$aksSpn = az ad app list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
$aksSpnPwd = az keyvault secret show --name $bootstrapValues.aks.servicePrincipalPassword --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
$acrName = $bootstrapValues.acr.name
$acrPassword = az acr credential show -n $acrName | ConvertFrom-Json
$additionalSettings = @{
    azAccount = @{
        tenantId = $azureAccount.tenantId
        id       = $azureAccount.id
        name     = $azureAccount.name
    }
    aks       = @{
        spn = @{
            appId = $aksSpn.appId
            pwd   = $aksSpnPwd.value
        }
    }
}
$bootstrapValues = Get-EnvironmentSettings `
    -EnvName $envName `
    -EnvRootFolder $envRootFolder `
    -SpaceName $SpaceName `
    -AdditionalSettings $additionalSettings

$bootstrapValues["azAccount"] = $additionalSettings.azAccount
$bootstrapValues.aks["spn"] = $additionalSettings.aks.spn
$bootstrapValues.aks["nodeResourceGroup"] = GetAksResourceGroupName -bootstrapValues $bootstrapValues
$bootstrapValues.aks["networkSecurityGroup"] = (GetNetworkSecurityGroup -bootstrapValues $bootstrapValues).name
$bootstrapValues.aks["virtualNetwork"] = (GetVirtualNetwork -bootstrapValues $bootstrapValues).name
$bootstrapValues.aks["routeTable"] = (GetRouteTable -bootstrapValues $bootstrapValues).name
$bootstrapValues.aks["availabilitySet"] = (GetAvailabilitySet -bootstrapValues $bootstrapValues).name
$bootstrapValues.acr["pwd"] = $acrPassword.passwords[0].value
$genevaCertThumbprint = az keyvault secret show --name $bootstrapValues.geneva.certThumbprintSecret --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
$genevaCertificate = az keyvault secret show --name $bootstrapValues.geneva.certName --vault-name $bootstrapValues.kv.name | ConvertFrom-Json
$bootstrapValues.geneva["cert"] = @{
    base64string = $genevaCertificate.value
    thumbprint = $genevaCertThumbprint.value
}

$adCredsFolder = Join-Path $yamlsFolder "ad-creds"
if (-not (Test-Path $adCredsFolder)) {
    New-Item -Path $adCredsFolder -ItemType Directory -Force | Out-Null
}
$azureSettingTemplateFile = Join-Path $templatesFolder "azure.json.tpl"
$azureSettingTemplate = Get-Content -Raw $azureSettingTemplateFile
$azureSettingJson = Set-YamlValues -valueTemplate $azureSettingTemplate -settings $bootstrapValues
$azureSettingJson | Out-File (Join-Path $adCredsFolder "azure.json") -Encoding utf8

LogStep -Step 3 -Message "Copy and transform conf files"
$genevaWarmpathContainers = @("mdm", "mdmstatsd", "mdsd", "fluentd", "azsecpack", "janitor")
$genevaWarmpathContainers | ForEach-Object {
    $container = $_
    try {
        if ($null -ne $bootstrapValues.geneva[$container]["confs"]) {
            $configFiles = @($bootstrapValues.geneva[$container]["confs"])
            $configFiles | ForEach-Object {
                $fileName = $_.name
                $configSourceFile = Join-Path $templatesFolder $fileName
                $configFile = Join-Path $yamlsFolder $fileName
                LogInfo -Message "Copying file '$fileName'..."
                Copy-Item $configSourceFile -Destination $configFile -Force | Out-Null
                $configFileContent = Get-Content $configFile -Raw
                $configFileContent = Set-YamlValues -valueTemplate $configFileContent -settings $bootstrapValues
                $configFileContent | Out-File $configFile -Encoding utf8
            }
        }
    }
    catch { }
}


LogStep -Step 4 -Message "Generate yaml file"
$genevaServiceTemplateFile = Join-Path $templatesFolder "geneva-service.tpl"
$serviceYamlTemplate = Get-Content $genevaServiceTemplateFile -Raw
$serviceYaml = Set-YamlValues -valueTemplate $serviceYamlTemplate -settings $bootstrapValues
$genevaServiceYamlFile = Join-Path $yamlsFolder "geneva-serice.yaml"
$serviceYaml | Out-File $genevaServiceYamlFile -Encoding utf8
UpdateYamlWithEmbeddedFunctions -YamlFile $genevaServiceYamlFile


LogStep -Step 4 -Message "Apply file to k8s..."
kubectl apply -f $genevaServiceYamlFile
