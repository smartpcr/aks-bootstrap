
function EnsureBaseDockerImage() {
    param(
        [string] $TemplateFolder,
        [string] $ScriptFolder,
        [string] $AcrName
    )

    $imageNames = @("aspnetcore-runtime", "dotnetcore-sdk")
    $imageNames | ForEach-Object {
        $ImageName = $_


        $found = $null
        try {
            $found = az acr repository show -n $AcrName -t $ImageName | ConvertFrom-Json
            LogInfo "Image '$ImageName' is already published to '$AcrName' with tag '$($found.name)'"
        }
        catch {
            $found = $null
        }

        if ($null -ne $found) {
            return
        }

        $dockerTemplateFile = Join-Path $TemplateFolder "Dockerfile-$($ImageName)"
        $imageTag = "latest"
        docker build -f $dockerTemplateFile . -t "$($AcrName).azurecr.io/$($ImageName):$($imageTag)"

        az acr login -n $AcrName
        docker push "$($AcrName).azurecr.io/$($ImageName):$($imageTag)"
        LogInfo "Image '$ImageName' is published to '$AcrName' with tag '$imageTag'"
    }

}

function BuildDockerFile() {
    param(
        [string] $EnvName,
        [string] $SpaceName,
        [string] $TemplateFolder,
        [string] $ScriptFolder,
        [object] $ServiceSetting,
        [object] $bootstrapValues
    )

    $ServiceName = $ServiceSetting.service.name
    $yamlsFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }
    $svcOutputFolder = Join-Path $yamlsFolder $ServiceName
    if (-not (Test-Path $svcOutputFolder)) {
        New-Item $svcOutputFolder -ItemType Directory -Force | Out-Null
    }

    $dockerTemplateFile = Join-Path $TemplateFolder "Dockerfile-api.tpl"
    if ($ServiceSetting.service.type -eq "job") {
        $dockerTemplateFile = Join-Path $TemplateFolder "Dockerfile-job.tpl"
    }
    elseif ($ServiceSetting.service.type -eq "web") {
        $dockerTemplateFile = Join-Path $TemplateFolder "Dockerfile-web.tpl"
    }
    LogInfo -Message "Pick dockerfile template '$dockerTemplateFile'"

    LogInfo -Message "Updating dockerfile with service setting..."
    $dockerContent = Get-Content $dockerTemplateFile -Raw
    $dockerContent = Set-YamlValues -valueTemplate $dockerContent -settings $ServiceSetting
    $dockerContent = Set-YamlValues -valueTemplate $dockerContent -settings $bootstrapValues

    $dockerFile = Join-Path $svcOutputFolder "Dockerfile_$($ServiceName)"
    $dockerContent | Out-File $dockerFile -Encoding utf8 -Force | Out-Null

    if ($ServiceSetting.privateNugetFeed) {
        LogInfo -Message "retrieving private nuget feed pat token..."
        $isWindowsOs = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq "Win32NT")
        $isUnix = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.Platform -eq "Unix")
        $isMac = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.OS.Contains("Darwin"))
        if ($isWindowsOs) {
            $pat = [System.Environment]::GetEnvironmentVariable($ServiceSetting.privateNugetFeed.passwordFromEnvironment, "User")
            if ($null -eq $pat -or $pat.Length -eq 0) {
                $pat = Read-Host "Enter pat for nuget feed: '$($ServiceSetting.privateNugetFeed.name)'"
                [System.Environment]::SetEnvironmentVariable($ServiceSetting.privateNugetFeed.passwordFromEnvironment, $pat, "User")
            }
        }
        elseif ($isUnix -or $isMac) {
            $nugetFolder = Join-Path $env:HOME ".nuget"
            if (-not (Test-Path $nugetFolder)) {
                New-Item $nugetFolder -ItemType Directory -Force | Out-Null
            }
            $patFilePath = Join-Path $nugetFolder $ServiceSetting.privateNugetFeed.passwordFromEnvironment
            if (Test-Path $patFilePath) {
                $pat = [System.IO.File]::ReadAllText($patFilePath)
                $pat = $pat.Trim()  # trim newline added by some of the editor
            }
            else {
                $pat = Read-Host "Enter pat for nuget feed: '$($ServiceSetting.privateNugetFeed.name)'"
                [System.IO.File]::WriteAllText($patFilePath, $pat)
            }
        }

        if ($null -eq $pat -or $pat.Length -eq 0) {
            throw "Environment variable '$($ServiceSetting.privateNugetFeed.passwordFromEnvironment)' is not set"
        }

        $dockerFileContent = Get-Content $dockerFile -Raw
        $dockerFileContent = $dockerFileContent.Replace("### RUN echo ""{{.Values.nugetConfig}}"" > nuget.config", "RUN echo ""{{.Values.nugetConfig}}"" > nuget.config")
        $dockerFileContent | Out-File $dockerFile

        $buffer = New-Object System.Text.StringBuilder
        $buffer.Append("<configuration>") | Out-Null
        $buffer.Append("<packageSources>") | Out-Null
        $buffer.Append("<add key=\""$($ServiceSetting.privateNugetFeed.name)\"" value=\""$($ServiceSetting.privateNugetFeed.url)\"" />") | Out-Null
        $buffer.Append("</packageSources>") | Out-Null
        $buffer.Append("<packageSourceCredentials>") | Out-Null
        $buffer.Append("<AppCenterNuGet>") | Out-Null
        $buffer.Append("<add key=\""Username\"" value=\""PAT\"" /><add key=\""ClearTextPassword\"" value=\""$pat\"" />") | Out-Null
        $buffer.Append("</AppCenterNuGet>") | Out-Null
        $buffer.Append("</packageSourceCredentials>") | Out-Null
        $buffer.Append("</configuration>") | Out-Null

        $nugetConfig = $buffer.ToString()
        ReplaceValuesInYamlFile -YamlFile $dockerFile -PlaceHolder "nugetConfig" -Value $nugetConfig
    }

    if ($null -ne $SpaceName -and $SpaceName.Length -gt 0) {
        LogInfo -Message "Copying appsettings file for space '$SpaceName'..."
        $dockerFileContent = Get-Content $dockerFile -Raw
        $dockerFileContent = $dockerFileContent.Replace("### TODO: COPY space app setting file", "COPY ""{{.Values.service.name}}.appsettings.{{.Values.spaceName}}.json"" ""appsettings.{{.Values.spaceName}}.json""")
        $dockerFileContent | Out-File $dockerFile
        ReplaceValuesInYamlFile -YamlFile $dockerFile -PlaceHolder "service.name" -Value $ServiceSetting.service.name
        ReplaceValuesInYamlFile -YamlFile $dockerFile -PlaceHolder "spaceName" -Value $SpaceName
    }

    LogInfo -Message "Dockerfile '$dockerFile' is built"
}

function BuildDockerComposeFile() {
    param(
        [string] $EnvName,
        [string] $SpaceName,
        [string] $TemplateFolder,
        [string] $ScriptFolder,
        [object] $ServiceSetting
    )

    $ServiceName = $ServiceSetting.service.name
    $yamlsFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }
    $svcOutputFolder = Join-Path $yamlsFolder $ServiceName
    if (-not (Test-Path $svcOutputFolder)) {
        New-Item $svcOutputFolder -ItemType Directory -Force | Out-Null
    }

    $dockerComposeTemplateFileName = "DockerCompose-api.yaml"
    if ($ServiceSetting.service.type -eq "job") {
        $dockerComposeTemplateFileName = "DockerCompose-job.yaml"
    }
    elseif ($ServiceSetting.service.type -eq "web") {
        $dockerComposeTemplateFileName = "DockerCompose-web.yaml"
    }
    $dockerComposeTemplateFile = Join-Path $TemplateFolder $dockerComposeTemplateFileName
    LogInfo -Message "Using docker compose template '$dockerComposeTemplateFile'"

    LogInfo "Bind docker compose file with service setting..."
    $buildConfiguration = "Release"
    if ($IsLocal) {
        $buildConfiguration = "Debug"
    }

    $ServiceSetting.service["buildConfiguration"] = $buildConfiguration

    $dockerFile = Join-Path $svcOutputFolder "Dockerfile_$($ServiceName)"
    $ServiceSetting.service["dockerFile"] = $dockerFile

    $dockerComposeContent = Get-Content $dockerComposeTemplateFile -Raw
    $dockerComposeContent = Set-YamlValues -valueTemplate $dockerComposeContent -settings $ServiceSetting
    $dockerComposeContent = $dockerComposeContent.Replace("\", "/")
    $dockerComposeFile = Join-Path $svcOutputFolder "docker-compose.$($ServiceName).yaml"
    $dockerComposeContent | Out-File $dockerComposeFile -Encoding utf8 -Force | Out-Null
    $composeFileYaml = Get-Content $dockerComposeFile -Raw | ConvertFrom-Yaml -Ordered

    LogInfo -Message "Handling ports..."
    if ($null -eq $ServiceSetting.service["ports"]) {
        if ($null -ne $composeFileYaml.services[$ServiceName]["ports"]) {
            $composeFileYaml.services[$ServiceName].Remove("ports")
        }
    }

    LogInfo -Message "Handling volumes..."
    if ($null -eq $ServiceSetting.service["volumes"]) {
        if ($null -ne $composeFileYaml.services[$ServiceName]["volumes"]) {
            $composeFileYaml.services[$ServiceName].Remove("volumes")
        }
    }

    LogInfo -Message "Handling envfile..."
    if ($null -ne $composeFileYaml.services[$ServiceName]["envFile"]) {
        LogInfo -Message "Update .env file"
        $composeFileYaml.services[$ServiceName].Remove("env_file")
        $composeFileYaml.services[$ServiceName]["env_file"] = $ServiceSetting.service.envFile
    }
    else {
        $composeFileYaml.services[$ServiceName].Remove("env_file")
    }

    if ($null -ne $composeFileYaml.services[$ServiceName]["env_file"]) {
        LogInfo -Message "Copying env file"
        $envFileName = $composeFileYaml.services[$ServiceName].env_file
        $envFile = Join-Path (Split-Path $ServiceTemplateFile -Parent) $envFileName
        $envTargetFile = Join-Path $svcOutputFolder $envFileName
        Copy-Item $envFile -Destination $envTargetFile -Force | Out-Null
    }

    $dockerComposeYamlContent = $composeFileYaml | ConvertTo-Yaml
    $dockerComposeYamlContent | Out-File $dockerComposeFile -Encoding utf8 -Force | Out-Null

    LogInfo -Message "dockercompose file is built: '$dockerComposeFile'"
}

function GetServiceSetting() {
    param(
        [string] $EnvName,
        [string] $SpaceName,
        [object] $AzAccount,
        [string] $ServiceName,
        [string] $TemplateFolder,
        [string] $ScriptFolder,
        [object] $bootstrapValues,
        [bool] $UsePodIdentity,
        [string] $BuildNumber,
        [string] $ServiceTemplateFile,
        [bool] $IsLocal
    )

    if (-not (Test-Path $ServiceTemplateFile)) {
        throw "Unable to find service template file: '$ServiceTemplateFile'!"
    }
    if (!$buildNumber) {
        $buildNumber = Get-Date -f "yyyyMMddHHmm"
    }
    $yamlsFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }

    $servicesYamlFile = Join-Path $yamlsFolder "services.yaml"
    Copy-Item $ServiceTemplateFile -Destination $servicesYamlFile -Force | Out-Null
    $serviceYamlContent = Get-Content $servicesYamlFile -Raw
    $serviceYamlSettings = $serviceYamlContent | ConvertFrom-Yaml -Ordered
    $fileExtension = [System.IO.Path]::GetExtension($ServiceTemplateFile)
    $serviceSpaceSettingFile = $ServiceTemplateFile.Substring(0, $ServiceTemplateFile.Length - $fileExtension.Length) + ".$($SpaceName)$($fileExtension)"
    if (Test-Path $serviceSpaceSettingFile) {
        $spaceSettingsContent = Get-Content $serviceSpaceSettingFile -Raw
        $spaceSettingsContent = Set-YamlValues -ValueTemplate $spaceSettingsContent -Settings $bootstrapValues
        $spaceSettings = $spaceSettingsContent | ConvertFrom-Yaml
        Copy-YamlObject -FromObj $spaceSettings -ToObj $serviceYamlSettings
        $serviceYamlContent = $serviceYamlSettings | ConvertTo-Yaml
    }
    else {
        $serviceEnvSettingFile = $ServiceTemplateFile.Substring(0, $ServiceTemplateFile.Length - $fileExtension.Length) + ".$($EnvName)$($fileExtension)"
        if (Test-Path $serviceEnvSettingFile) {
            $envSettings = Get-Content $serviceEnvSettingFile -Raw | ConvertFrom-Yaml
            Copy-YamlObject -fromObj $envSettings -toObj $serviceYamlSettings
            $serviceYamlContent = $serviceYamlSettings | ConvertTo-Yaml
        }
    }

    $homeFolder = $($env:HOME).Replace("\", "/")
    $bootstrapValues["homeFolder"] = $homeFolder
    $bootstrapValues["buildNumber"] = $BuildNumber
    $aadApps = az ad sp list --display-name $bootstrapValues.global.servicePrincipal | ConvertFrom-Json
    $spnAppId = $aadApps[0].appId
    $spnCertSecret = $bootstrapValues.global.servicePrincipal
    $bootstrapValues.kv["clientId"] = $spnAppId
    $bootstrapValues.kv["clientCertName"] = $spnCertSecret
    $bootstrapValues.global["spaceName"] = $SpaceName

    $serviceYamlContent = Set-YamlValues -valueTemplate $serviceYamlContent -settings $bootstrapValues
    $serviceYamlContent | Out-File $servicesYamlFile -Encoding utf8 -Force | Out-Null

    $services = Get-Content $servicesYamlFile -Raw | ConvertFrom-Yaml -Ordered

    $service = $null
    $services.services | ForEach-Object {
        if ($_.name -eq $ServiceName) {
            $service = $_
        }
    }
    if ($null -eq $service) {
        throw "Unable to find service in template: '$ServiceName'!"
    }

    $sourceCodeRootFolder = $services.sourceCodeRepoRoot
    $solutionFile = Join-Path $sourceCodeRootFolder $service.solutionFile
    $solutionFolder = [System.IO.Path]::GetDirectoryName($solutionFile)
    $dockerContext = $solutionFolder
    $solutionFile = [System.IO.Path]::GetFileName($solutionFile)
    $projectFile = Join-Path $sourceCodeRootFolder $service.projectFile
    $projectFolder = [System.IO.Path]::GetDirectoryName($projectFile)
    if ($projectFile.StartsWith($dockerContext)) {
        $projectFile = $projectFile.Substring($dockerContext.Length)
    }
    $projectFile = $projectFile.Replace("\", "/")
    $projectFile = $projectFile.TrimStart("/")
    if (!$projectFile.StartsWith("./")) {
        $projectFile = $projectFile.TrimStart("/")
        $projectFile = "./" + $projectFile
    }

    $privateNugetFeed = $null # only one private nuget feed is allowed
    if ($null -ne $service["privateNugetFeed"]) {
        $services.nugetFeeds | ForEach-Object {
            if ($_.name -eq $service.privateNugetFeed) {
                $privateNugetFeed = $_
            }
        }
    }

    $portSettings = New-Object System.Collections.ArrayList
    $portSettings.Add("51022:22") | Out-Null
    if ($null -ne $service["containerPort"]) {
        $portSettings.Add("$($service.containerPort):$($service.containerPort)") | Out-Null
    }

    $volumeSettings = New-Object System.Collections.ArrayList
    if ($null -ne $service["volumes"]) {
        $service.volumes | ForEach-Object {
            $volumeName = $_.name
            $volumeFound = $null
            $services.shares | ForEach-Object {
                $volume = $_
                if ($volume.name -eq $volumeName -and $IsLocal -eq $volume.localOnly) {
                    $volumeFound = $volume
                }
            }
            if ($null -ne $volumeFound) {
                $volumePathMapping = $volumeFound.hostPath + ":" + $volumeFound.containerPath
                $volumeSettings.Add($volumePathMapping) | Out-Null
            }
        }
    }

    if ($null -eq $service["namespace"]) {
        $service["namespace"] = "default"
    }
    if ($portSettings) {
        $service["ports"] = $portSettings
    }
    if ($volumeSettings -and $volumeSettings.Count -gt 0) {
        $service["volumes"] = @($volumeSettings)
    }
    elseif ($null -ne $service["volumes"]) {
        $service.Remove("volumes")
    }

    $serviceResources = $null
    $services.resources | ForEach-Object {
        $resources = $_
        if ($resources.name -eq $service.type) {
            $serviceResources = $resources
        }
    }
    if ($null -ne $serviceResources) {
        $service["resources"] = $serviceResources
    }

    $service["label"] = $ServiceName
    $service["dockerContext"] = $dockerContext.Replace("\", "/")
    $service["solutionFile"] = $solutionFile
    $service["solutionFolder"] = $solutionFolder.Replace("\", "/")
    $service["projectFile"] = $projectFile.Replace("\", "/")
    $service["projectFolder"] = $projectFolder.Replace("\", "/")
    $service["replicas"] = $(if ($null -ne $service["replicas"]) { $service["replicas"] } else { 1 })
    $service["isFrontEnd"] = $($null -ne $service["isFrontEnd"] -and $service["isFrontEnd"] -eq $true)
    $service["buildConfiguration"] = if ($IsLocal) { "Development" } else { "Release" }
    $service["hostName"] = "$($ServiceName)-$($bootstrapValues.global.productShortName)-$($bootstrapValues.global.location).$($bootstrapValues.dns.domain)"
    $service["internalHostName"] = "$($ServiceName).$($service.namespace).svc.cluster.local"

    $ServiceSetting = @{
        subscriptionId      = $azAccount.id
        acrName             = $bootstrapValues.acr.name
        externalServices    = $services["externalServices"]
        oAuthProvider       = $services["oAuthProvider"]
        baseAppSettingsFile = $services.baseAppSettingsFile
        service             = $service
    }
    if ($UsePodIdentity) {
        $serviceIdentity = EnsureServiceIentity -serviceName $ServiceName -bootstrapValues $bootstrapValues
        GrantAccessToUserAssignedIdentity -serviceIdentity $serviceIdentity -bootstrapValues $bootstrapValues
        $mcResourceGroupName = GetAksResourceGroupName -bootstrapValues $bootstrapValues
        $ServiceSetting.Add("serviceIdentity", @{
                clientId      = $serviceIdentity.clientId
                resourceGroup = $mcResourceGroupName
                id            = $serviceIdentity.id
            }) | Out-Null
    }

    if ($privateNugetFeed -and ($null -eq $ServiceSetting["privateNugetFeed"])) {
        $ServiceSetting.Add("privateNugetFeed", $privateNugetFeed) | Out-Null
    }

    return $ServiceSetting
}

function CreateAppSettings() {
    param(
        [string]$EnvName,
        [string]$SpaceName,
        [string]$ServiceTemplateFile,
        [object]$ServiceSetting,
        [object]$BootstrapValues,
        [string]$TemplateFolder,
        [string]$ScriptFolder
    )

    $serviceTemplates = Get-Content $ServiceTemplateFile -Raw | ConvertFrom-Yaml -Ordered
    $serviceSpaceTemplateFile = Join-Path (Split-Path $ServiceTemplateFile -Parent) "services.$SpaceName.yaml"
    if (Test-Path $serviceSpaceTemplateFile) {
        $serviceSpaceTemplates = Get-Content $serviceSpaceTemplateFile -Raw | ConvertFrom-Yaml
        Copy-YamlObject -FromObj $serviceSpaceTemplates -ToObj $serviceTemplates
    }
    $Services = $serviceTemplates.services

    $envAppSettingFile = Join-Path $ServiceSetting.service.projectFolder $ServiceSetting.baseAppSettingsFile
    if (-not (Test-Path $envAppSettingFile)) {
        throw "Unable to find '$envAppSettingFile'"
    }

    $yamlsFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item $yamlsFolder -ItemType Directory -Force | Out-Null
    }
    $svcOutputFolder = Join-Path $yamlsFolder $ServiceSetting.service.name
    if (-not (Test-Path $svcOutputFolder)) {
        New-Item $svcOutputFolder -ItemType Directory -Force | Out-Null
    }
    $spaceAppSettingFile = Join-Path $svcOutputFolder "appsettings.$SpaceName.json"
    Copy-Item -Path $envAppSettingFile -Destination $spaceAppSettingFile -Force | Out-Null

    $BootstrapValues["serviceSetting"] = $ServiceSetting
    $BootstrapValues["services"] = $Services
    $BootstrapValues.appInsights["instrumentationKey"] = $null
    if ($BootstrapValues.global.components.appInsights) {
        $instrumentationKeySecret = az keyvault secret show --name $BootstrapValues.appInsights.instrumentationKeySecret --vault-name $BootstrapValues.kv.name | ConvertFrom-Json
        $BootstrapValues.appInsights["instrumentationKey"] = $instrumentationKeySecret.value
    }
    $enableAadPodIdentity = $BootstrapValues.aks.keyVaultAccess -contains "podIdentity"
    $BootstrapValues.aks["enableAadPodIdentity"] = $enableAadPodIdentity

    $appSettingTempalteFile = Join-Path (Split-Path $ServiceTemplateFile -Parent) "appsettings.yaml"
    if (-not (Test-Path $appSettingTempalteFile)) {
        Write-Warning "Unable to find appsetting template file: '$appSettingTempalteFile'"
    }
    else {
        $appSettingsTemplate = Get-Content $appSettingTempalteFile -Raw
        $appSettingsTemplate = EvaluateEmbeddedFunctions -YamlContent $appSettingsTemplate -InputObject $BootstrapValues
        $appSettingsTemplate = Set-YamlValues -valueTemplate $appSettingsTemplate -settings $BootstrapValues
        $appSettings = $appSettingsTemplate | ConvertFrom-Yaml

        $serviceAppSettingTemplateFile = Join-Path (Split-Path $ServiceTemplateFile -Parent) "appsettings.$($ServiceSetting.service.name).yaml"
        if (Test-Path $serviceAppSettingTemplateFile) {
            $serviceAppSettingsTemplate = Get-Content $serviceAppSettingTemplateFile -Raw
            $serviceAppSettingsTemplate = EvaluateEmbeddedFunctions -YamlContent $serviceAppSettingsTemplate -InputObject $BootstrapValues
            $serviceAppSettingsTemplate = Set-YamlValues -valueTemplate $serviceAppSettingsTemplate -settings $BootstrapValues
            $serviceAppSettings = $serviceAppSettingsTemplate | ConvertFrom-Yaml
            Copy-YamlObject -fromObj $serviceAppSettings -toObj $appSettings
        }

        $spaceSettings = Get-Content $spaceAppSettingFile -Raw | ConvertFrom-Json
        $spaceSettings = $spaceSettings | ConvertTo-Yaml | ConvertFrom-Yaml -Ordered # force to hashtable
        Copy-YamlObject -fromObj $appSettings -toObj $spaceSettings

        ConvertYamlToJson -InputObject $spaceSettings | Out-File $spaceAppSettingFile -Encoding utf8 -Force | Out-Null
    }

    return $spaceAppSettingFile
}

function DeployServiceToAks() {
    param(
        [object] $ServiceSetting,
        [string] $TemplateFolder,
        [string] $ScriptFolder,
        [bool] $UsePodIdentity,
        [string] $BuildNumber,
        [object] $bootstrapValues
    )

    $yamlsFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }
    $svcOutputFolder = Join-Path $yamlsFolder $ServiceName
    if (-not (Test-Path $svcOutputFolder)) {
        New-Item $svcOutputFolder -ItemType Directory -Force | Out-Null
    }

    LogInfo -Message "Setup deployment yaml file..."
    $k8sTemplateFile = "k8s-api.yaml"
    if ($ServiceSetting.service.type -eq "web") {
        $k8sTemplateFile = "k8s-web.yaml"
    }
    elseif ($ServiceSetting.service.type -eq "job") {
        $k8sTemplateFile = "k8s-job.yaml"
    }
    if ($UsePodIdentity) {
        $k8sTemplateFile = $k8sTemplateFile.Substring(0, $k8sTemplateFile.Length - ".yaml".Length) + "-podidentity.yaml"
    }

    LogInfo -Message "Picked template '$k8sTemplateFile' for k8s deployment"
    $k8sDeploymentTemplateFile = Join-Path $TemplateFolder $k8sTemplateFile
    $k8sDeploymentTemplate = Get-Content $k8sDeploymentTemplateFile -Raw

    $k8sDeploymentTemplate = Set-YamlValues -valueTemplate $k8sDeploymentTemplate -settings $ServiceSetting
    $k8sDeploymentTemplate = Set-YamlValues -valueTemplate $k8sDeploymentTemplate -settings $bootstrapValues

    $deploymentYamlFile = Join-Path $svcOutputFolder "$($ServiceSetting.service.name)-Deployment.yaml"
    $k8sDeploymentTemplate | Out-File $deploymentYamlFile -Force -Encoding utf8 | Out-Null

    LogInfo -Message "deploy to k8s"
    kubectl apply -f $deploymentYamlFile

    if ($UsePodIdentity) {
        LogInfo -Message "Deploy pod identity..."
        $podIdentityTempFile = Join-Path $TemplateFolder "AadPodIdentity.tpl"
        $podIdentityYamlFile = Join-Path $svcOutputFolder "$($ServiceSetting.service.name)-AadPodIdentity.yaml"
        Copy-Item $podIdentityTempFile -Destination $podIdentityYamlFile -Force | Out-Null
        ReplaceValuesInYamlFile -YamlFile $podIdentityYamlFile -PlaceHolder "service.name" -Value $ServiceSetting.service.name
        ReplaceValuesInYamlFile -YamlFile $podIdentityYamlFile -PlaceHolder "serviceIdentity.id" -Value $ServiceSetting.serviceIdentity.id
        ReplaceValuesInYamlFile -YamlFile $podIdentityYamlFile -PlaceHolder "serviceIdentity.clientId" -Value $ServiceSetting.serviceIdentity.clientId
        kubectl apply -f $podIdentityYamlFile

        LogInfo -Message "Deploy pod identity binding..."
        $podIdentityBindingTempFile = Join-Path $TemplateFolder "AadPodIdentityBinding.tpl"
        $podIdentityBindingYamlFile = Join-Path $svcOutputFolder "$($ServiceSetting.service.name)-AadPodIdentityBinding.yaml"
        Copy-Item $podIdentityBindingTempFile -Destination $podIdentityBindingYamlFile -Force | Out-Null
        ReplaceValuesInYamlFile -YamlFile $podIdentityBindingYamlFile -PlaceHolder "service.name" -Value $ServiceSetting.service.name
        ReplaceValuesInYamlFile -YamlFile $podIdentityBindingYamlFile -PlaceHolder "service.label" -Value $ServiceSetting.service.label
        kubectl apply -f $podIdentityBindingYamlFile
    }

    LogInfo -Message "yaml file '$deploymentYamlFile' successfully applied to k8s cluster"
}

function UpdateServiceAuthRedirectUrl() {
    param(
        [object] $ServiceSetting,
        [object] $BootstrapValues
    )

    $signinRedirect = "/signin-oidc"
    if ($ServiceSetting.service.type -ne "job" -and $null -ne $ServiceSetting.service["appId"]) {
        if ($null -ne $ServiceSetting.service["authRedirectPath"]) {
            $signinRedirect = $ServiceSetting.service["authRedirectPath"]
        }
        $serviceSpn = az ad sp show --id $ServiceSetting.service.appId | ConvertFrom-Json
        if ($null -ne $serviceSpn) {
            throw "Unable to find aad app '$($ServiceSetting.service.name)' by id '$($ServiceSetting.service.appId)'"
        }

        # ingress rule: "{{.Values.service.name}}-{{.Values.global.productShortName}}-{{.Values.global.location}}.{{.Values.dns.domain}}"
        $replyUrl = "https://$($ServiceSetting.service.name)" +
            "-$($BootstrapValues.global.productShortName)" +
            "-$($BootstrapValues.global.location)" +
            ".$($BootstrapValues.dns.domain)$($signinRedirect)"
        if (-not ($serviceSpn.replyUrls -contains $replyUrl)) {
            $replyUrlList = New-Object System.Collections.ArrayList
            $replyUrlList.AddRange([array]$serviceSpn.replyUrls)
            $replyUrlList.Add($replyUrl) | Out-Null

            $newReplyUrls = ""
            $replyUrlList | ForEach-Object {
                $newReplyUrls += " " + $_
            }
            az ad app update --id $ServiceSetting.service.appId --reply-urls $newReplyUrls
        }
        else {
            LogInfo -Message "Reply url is already added to service '$($ServiceSetting.service.name)'"
        }
    }
    else {
        LogInfo "Service '$($ServiceSetting.service.name)' type doesn't need aad auth"
    }
}