
function SetupGlobalEnvironmentVariables() {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptFolder,
        [Parameter(Mandatory = $true)]
        [string] $ScriptName
    )

    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version Latest

    try {
        if ($null -eq $Global:ScriptName) {
            $Global:ScriptName = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } else { $ScriptName }
            InitializeLogger
        }
    }
    catch {
        $Global:ScriptName = if ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } else { $ScriptName }
        InitializeLogger
    }

    $scriptFolderName = Split-Path $ScriptFolder -Leaf
    if ($null -eq $scriptFolderName -or $scriptFolderName -ne "scripts") {
        throw "Invalid script folder: '$ScriptFolder'"
    }
    $logFolder = Join-Path $ScriptFolder "log"
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    $timeString = (Get-Date).ToString("yyyy-MM-dd-HHmmss")
    $logFile = Join-Path $logFolder "$($timeString).log"
    $Global:LogFile = $logFile
}

function LogVerbose() {
    param(
        [string] $Message,
        [int] $IndentLevel = 0)

    if (-not (Test-Path $Global:LogFile)) {
        New-Item -Path $Global:LogFile -ItemType File -Force | Out-Null
    }

    $timeString = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $formatedMessage = ""
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    $formatedMessage += "$timeString $Message"
    Add-Content -Path $Global:LogFile -Value $formatedMessage
}

function LogInfo() {
    param(
        [string] $Message,
        [int] $IndentLevel = 1
    )

    $formatedMessage = ""
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    $formatedMessage += $Message
    LogVerbose -Message $formatedMessage -IndentLevel $IndentLevel

    Write-Host $formatedMessage -ForegroundColor Yellow
}

function LogTitle() {
    param(
        [string] $Message
    )

    Write-Host "`n"
    Write-Host "`t`t***** $Message *****" -ForegroundColor Green
    Write-Host "`n"
}

function Get-OrCreatePasswordInVault2 {
    param(
        [string] $VaultName,
        [string] $SecretName
    )

    $secretsFound = az keyvault secret list `
        --vault-name $VaultName `
        --query "[?id=='https://$($VaultName).vault.azure.net/secrets/$SecretName']" | ConvertFrom-Json
    if (!$secretsFound) {
        $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $bytes = New-Object Byte[] 30
        $prng.GetBytes($bytes)
        $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
        az keyvault secret set --vault-name $VaultName --name $SecretName --value $password
        $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $res
    }

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }
}


function Get-OrCreateServicePrincipalUsingPassword {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName
    )

    $spFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spFound) {
        $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
        LogInfo -Message "Service principal '$ServicePrincipalName' is already installed, reset its password..."
        az ad sp credential reset --name $ServicePrincipalName --password $servicePrincipalPwd.value
        return $spFound
    }

    LogInfo -Message "Creating service principal '$ServicePrincipalName' with password..."
    $sp = az ad sp create-for-rbac `
        --name $ServicePrincipalName | ConvertFrom-Json

    LogInfo -Message "Store spn password to key vault"
    az keyvault secret set --vault-name $VaultName --name $ServicePrincipalPwdSecretName --value $sp.password | Out-Null

    return $sp
}

function Get-OrCreateAksServicePrincipal {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName,
        [string] $EnvRootFolder,
        [string] $EnvName,
        [string] $SpaceName,
        [bool] $ForceResetSpn
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvRootFolder -SpaceName $SpaceName
    $templatesFolder = Join-Path $EnvRootFolder "templates"
    $spnAuthJsonFile = Join-Path $templatesFolder "aks-spn-auth.json"

    $aksRg = az group show --name $bootstrapValues.aks.resourceGroup | ConvertFrom-Json
    $spFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json

    if ($spFound) {
        LogInfo -Message "Service principal '$ServicePrincipalName' is already created."
        if ($ForceResetSpn) {
            LogInfo -Message "Resetting password for service principal '$ServicePrincipalName'..."
            $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
            az ad sp credential reset --name $ServicePrincipalName --password $servicePrincipalPwd.value | Out-Null
        }
        else {
            LogInfo -Message "Skipping reset password for service principal '$ServicePrincipalName'"
        }

        $aksSpn = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
        if ($ForceResetSpn) {
            LogInfo -Message "Updating aks auth for spn..."
            az ad app update --id $aksSpn.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
        }

        LogInfo -Message "Grant contributor access to resource group '$($bootstrapValues.aks.resourceGroup)' for service principal '$ServicePrincipalName'..."
        $existingAssignments = az role assignment list --role Contributor --assignee $aksSpn.appId --scope $aksRg.id | ConvertFrom-Json
        if ($existingAssignments.Count -eq 0) {
            az role assignment create --role Contributor --assignee $aksSpn.appId --scope $aksRg.id | Out-Null
        }
        else {
            LogInfo "Assignment already exists"
        }

        if ($ForceResetSpn) {
            LogInfo -Message "Updating reply urls for service principal '$ServicePrincipalName'..."
            az ad app update --id $aksSpn.appId --reply-urls "http://$($ServicePrincipalName)" | Out-Null
        }

        $aksSpn = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json

        return $aksSpn
    }


    $rgName = $bootstrapValues.aks.resourceGroup
    $azAccount = az account show | ConvertFrom-Json
    $subscriptionId = $azAccount.id
    $scopes = "/subscriptions/$subscriptionId/resourceGroups/$($rgName)"

    LogInfo -Message "Granting spn '$ServicePrincipalName' 'Contributor' role to resource group '$rgName'"
    $aksSpn = az ad sp create-for-rbac `
        --name $ServicePrincipalName `
        --role="Contributor" `
        --scopes=$scopes | Out-Null

    LogInfo -Message "Store aks server spn password to key vault"
    az keyvault secret set --vault-name $VaultName --name $ServicePrincipalPwdSecretName --value $aksSpn.password | Out-Null

    LogInfo -Message "Grant required resource access for aad app..."
    az ad app update --id $aksSpn.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
    az ad app update --id $aksSpn.appId --reply-urls "http://$($ServicePrincipalName)" | Out-Null

    return $aksSpn
}


function Get-OrCreateAksClientApp {
    param(
        [string] $EnvRootFolder,
        [string] $EnvName,
        [string] $SpaceName,
        [bool] $ForceResetSpn
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvRootFolder -SpaceName $SpaceName
    $ClientAppName = $bootstrapValues.aks.clientAppName

    $aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
    if ($null -eq $aksSpn -or $aksSpn.Length -eq 0) {
        throw "Cannot create client app when server app with name '$($bootstrapValues.aks.servicePrincipal)' is not found!"
    }

    LogInfo -Message "Retrieving replyurl from server app..."
    $serverAppReplyUrls = $aksSpn.replyUrls
    $clientAppRedirectUrl = $serverAppReplyUrls
    if ($serverAppReplyUrls -is [array] -and ([array]$serverAppReplyUrls).Length -gt 0) {
        $clientAppRedirectUrl = [array]$serverAppReplyUrls[0]
    }

    $spFound = az ad app list --display-name $ClientAppName | ConvertFrom-Json
    if ($spFound -and $spFound -is [array]) {
        if (([array]$spFound).Count -gt 1) {
            throw "Duplicated client app found for '$ClientAppName'"
        }
    }
    if ($spFound) {
        LogInfo -Message "Client app '$ClientAppName' already exists."
        if ($ForceResetSpn) {
            LogInfo -Message "Updating reply url for client aks app '$ClientAppName'..."
            az ad app update --id $spFound.appId --reply-urls "$clientAppRedirectUrl"
        }

        return $sp
    }

    LogInfo -Message "Creating client app '$ClientAppName'..."
    LogInfo -Message "Granting client app '$ClientAppName' access to server app '$($bootstrapValues.aks.servicePrincipal)'"
    $resourceAccess = "[{`"resourceAccess`": [{`"id`": `"318f4279-a6d6-497a-8c69-a793bda0d54f`", `"type`": `"Scope`"}],`"resourceAppId`": `"$($aksSpn.appId)`"}]"
    $scriptFolder = Join-Path (Split-Path $EnvRootFolder -Parent) "scripts"
    $yamlsFolder = Join-Path $scriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }
    $clientAppResourceAccessJsonFile = Join-Path $yamlsFolder "aks-client-auth.json"
    $resourceAccess | Out-File $clientAppResourceAccessJsonFile -Encoding ascii

    az ad app create `
        --display-name $ClientAppName `
        --native-app `
        --reply-urls "$clientAppRedirectUrl" `
        --required-resource-accesses @$clientAppResourceAccessJsonFile | Out-Null

    $sp = az ad sp list --display-name $ClientAppName | ConvertFrom-Json
    return $sp
}

function LoginAzureAsUser {
    param (
        [string] $SubscriptionName
    )

    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ine $SubscriptionName) {
        az login | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }
    elseif ($azAccount.user.type -eq "servicePrincipal") {
        az login | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }

    $currentAccount = az account show | ConvertFrom-Json
    return $currentAccount
}

function LoginAsServicePrincipal {
    param (
        [string] $EnvName = "dev",
        [string] $SpaceName = "xiaodoli",
        [string] $EnvRootFolder
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -SpaceName $SpaceName -EnvRootFolder $EnvRootFolder
    $azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
    $vaultName = $bootstrapValues.kv.name
    $spnName = $bootstrapValues.global.servicePrincipal
    $certName = $spnName
    $tenantId = $azAccount.tenantId

    $privateKeyFilePath = "$EnvRootFolder/credential/$certName.key"
    if (-not (Test-Path $privateKeyFilePath)) {
        LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
        DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -EnvRootFolder $EnvRootFolder
    }

    LogInfo -Message "Login as service principal '$spnName'"
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $tenantId | Out-Null
}