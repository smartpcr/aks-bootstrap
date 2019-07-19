
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong",
    [string] $ServiceTemplateFile = "e:/work/my/userspace/deploy/examples/1es/services.yaml",
    [string] $ServiceName = "product-catalog-api",
    [bool] $UsePodIdentity = $true,
    [string] $BuildNumber = $(Get-Date -f "yyyyMMddHHmm"),
    [bool] $IsLocal = $false
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
$templateFolder = Join-Path $envRootFolder "templates"
$moduleFolder = Join-Path $scriptFolder "modules"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
}
$svcOutputFolder = Join-Path $yamlsFolder $ServiceName
if (-not (Test-Path $svcOutputFolder)) {
    New-Item $svcOutputFolder -ItemType Directory -Force | Out-Null
}

Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AksUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "ServiceUtil.psm1") -Force

SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder

LogTitle -Message "Building and deploy service '$ServiceName' to '$EnvName/$SpaceName'..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LogStep -Step 1 -Message "Login to azure, aks and acr..."
$azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin
az acr login -n $bootstrapValues.acr.name


LogStep -Step 2 -Message "Ensure runtime base image is build and pushed to acr"
EnsureBaseDockerImage -templateFolder $templateFolder -scriptFolder $scriptFolder -AcrName $bootstrapValues.acr.name


LogStep -Step 3 -Message "Building appsetting file for space '$SpaceName'..."
LogInfo -Message "Reading service manifest from file '$ServiceTemplateFile'..."

$serviceSetting = GetServiceSetting `
    -EnvName $EnvName `
    -SpaceName $SpaceName `
    -AzAccount $azAccount `
    -ServiceName $serviceName `
    -templateFolder $templateFolder `
    -scriptFolder $scriptFolder `
    -bootstrapValues $bootstrapValues `
    -UsePodIdentity $UsePodIdentity `
    -BuildNumber $BuildNumber `
    -ServiceTemplateFile $ServiceTemplateFile `
    -IsLocal $IsLocal

LogInfo -Message "Building app settings..."
$spaceAppSettingFile = CreateAppSettings `
    -EnvName $EnvName `
    -SpaceName $SpaceName `
    -ServiceTemplateFile $ServiceTemplateFile `
    -ServiceSetting $ServiceSetting `
    -BootstrapValues $bootstrapValues `
    -ScriptFolder $scriptFolder `
    -TemplateFolder $templateFolder

$spaceAppSettingDestinationFile = Join-Path $serviceSetting.service.solutionFolder "$($ServiceSetting.service.name).appsettings.$SpaceName.json"
LogInfo -Message "Moving space app setting file to project folder: '$spaceAppSettingDestinationFile'"
Copy-Item $spaceAppSettingFile -Destination $spaceAppSettingDestinationFile -Force


LogStep -Step 3 -Message "Build docker file..."
BuildDockerFile `
    -EnvName $EnvName `
    -SpaceName $SpaceName `
    -templateFolder $templateFolder `
    -scriptFolder $scriptFolder `
    -serviceSetting $serviceSetting `
    -bootstrapValues $bootstrapValues


LogStep -Step 4 -Message "Building docker-compose file"
BuildDockerComposeFile `
    -EnvName $EnvName `
    -SpaceName $SpaceName `
    -TemplateFolder $templateFolder `
    -ScriptFolder $scriptFolder `
    -ServiceSetting $serviceSetting


LogStep -Step 5 -Message "Build docker image"
$dockerComposeFile = Join-Path $svcOutputFolder "docker-compose.$($ServiceName).yaml"
docker-compose -f $dockerComposeFile stop $ServiceName
docker-compose -f $dockerComposeFile rm -vf $ServiceName
docker-compose -f $dockerComposeFile build $ServiceName

LogInfo -Message "Removing file '$spaceAppSettingDestinationFile'..."
if (Test-Path $spaceAppSettingDestinationFile) {
    Remove-Item $spaceAppSettingDestinationFile -Force | Out-Null
}

if ($IsLocal) {
    LogStep -Step 6 -Message "Running docker image on local"
    # Remove stopped containers
    (& docker ps --quiet --filter 'status=exited' ) | Foreach-Object {
        & docker rm $_ | out-null
    }

    # Remove dangling images
    (& docker images --all --quiet --filter 'dangling=true') | Foreach-Object {
        & docker rmi $_ | out-null
    }
    Start-Process powershell "docker-compose -f $dockerComposeFile up $ServiceName"
}
else {
    LogStep -Step 6 -Message "Publishing docker image '$($serviceSetting.acrName).azurecr.io/$($serviceSetting.service.image.name):$($serviceSetting.service.image.tag)' to ACR..."
    az acr login -n $serviceSetting.acrName
    docker push "$($serviceSetting.acrName).azurecr.io/$($serviceSetting.service.image.name):$($serviceSetting.service.image.tag)"
    LogInfo "docker image '$($serviceSetting.service.image.name):$($serviceSetting.service.image.tag)' successfully pushed to acr '$($serviceSetting.acrName)'"
}

