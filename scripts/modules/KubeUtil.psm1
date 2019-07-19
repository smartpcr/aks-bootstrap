function SetConfigMap {
    param(
        [string] $Key,
        [string] $Name,
        [string] $Value,
        [string] $Namespace,
        [string] $ScriptFolder,
        [string] $EnvRootFolder 
    )

    $templateFolder = Join-Path $EnvRootFolder "templates"
    $configMapTemplateFile = Join-Path $templateFolder "configmap.tpl"
    $yamlDataFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlDataFolder)) {
        New-Item -Path $yamlDataFolder -ItemType Directory -Force | Out-Null
    }
    $configMapYamlFile = Join-Path $yamlDataFolder "configmap.yaml"
    Copy-Item -Path $configMapTemplateFile -Destination $configMapYamlFile -Force
    ReplaceValuesInYamlFile -YamlFile $configMapYamlFile -PlaceHolder "key" -Value $Key
    ReplaceValuesInYamlFile -YamlFile $configMapYamlFile -PlaceHolder "name" -Value $Name
    ReplaceValuesInYamlFile -YamlFile $configMapYamlFile -PlaceHolder "value" -Value $Value
    kubectl apply -f $configMapYamlFile -n $Namespace
}

function SetSecret {
    param(
        [string] $Key,
        [string] $Name,
        [string] $Value,
        [string] $Namespace,
        [string] $ScriptFolder,
        [string] $EnvRootFolder 
    )

    $templateFolder = Join-Path $EnvRootFolder "templates"
    $secretTemplateFile = Join-Path $templateFolder "secret.tpl"
    $yamlDataFolder = Join-Path $ScriptFolder "yamls"
    if (-not (Test-Path $yamlDataFolder)) {
        New-Item -Path $yamlDataFolder -ItemType Directory -Force | Out-Null
    }
    $secretYamlFile = Join-Path $yamlDataFolder "secret.yaml"
    Copy-Item -Path $secretTemplateFile -Destination $secretYamlFile -Force
    ReplaceValuesInYamlFile -YamlFile $secretYamlFile -PlaceHolder "key" -Value $Key
    ReplaceValuesInYamlFile -YamlFile $secretYamlFile -PlaceHolder "name" -Value $Name
    $secretValue = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))

    ReplaceValuesInYamlFile -YamlFile $secretYamlFile -PlaceHolder "value" -Value $secretValue
    kubectl apply -f $secretYamlFile -n $Namespace
}