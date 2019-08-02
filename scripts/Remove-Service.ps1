
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "xiaodong",
    [string] $ServiceTemplateFile = "e:/work/my/userspace/deploy/examples/1es/services.yaml",
    [string] $ServiceName = "product-catalog-api",
    [string] $BuildNumber,
    [bool] $IsLocal = $false
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
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AksUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "ServiceUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AcrUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Remove-Service"

LogTitle -Message "Building and deploy service '$ServiceName' to '$EnvName/$SpaceName'..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LogStep -Message "Login to azure and aks..."
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
& $scriptFolder\ConnectTo-AksCluster.ps1 -EnvName $EnvName -SpaceName $SpaceName -AsAdmin


LogStep -Message "Get service setting..."
$serviceTemplates = Get-Content $ServiceTemplateFile -Raw | ConvertFrom-Yaml -Ordered
$serviceType = "api"
$serviceTemplates.services | ForEach-Object {
    if ($_.name -eq $ServiceName) {
        $serviceType = $_.type
    }
}


if ($IsLocal) {
    LogStep -Message "Stop docker image on local"
    # Remove stopped containers
    (& docker ps --quiet --filter 'status=exited' ) | Foreach-Object {
        & docker rm $_ | out-null
    }

    # Remove dangling images
    (& docker images --all --quiet --filter 'dangling=true') | Foreach-Object {
        & docker rmi $_ | out-null
    }
    Start-Process powershell "docker-compose -f $dockerComposeFile down $ServiceName"
}
else {
    LogStep -Message  "Remove deployment '$ServiceName'..."
    if ($serviceType -eq "job") {
        kubectl delete cronjob $ServiceName
    }
    else {
        kubectl delete deployment $ServiceName
    }
}

