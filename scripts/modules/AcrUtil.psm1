
function SetAcrCredential() {
    param(
        [string]$SubscriptionName = "Compliance_Tools_Eng",
        [string]$AcrName = "linuxgeneva-microsoft",
        [string]$VaultSubscriptionName = "xiaodoli",
        [string]$VaultName = "xiaodoli-kv",
        [string]$AcrSecret = "linuxgeneva-credentials",
        [string]$SpnAppId = "9beb98b0-4b0d-4989-b4ea-625d28b7d98a",
        [string]$SpnPwdSecret = "xiaodoli-acr-sp-pwd"
    )

    $azAccount = az account show | ConvertFrom-Json
    if ($null -ne $azAccount -and $azAccount.name -ine $SubscriptionName) {
        az login | Out-Null
        az account set -s $SubscriptionName
        $azAccount = az account show | ConvertFrom-Json
    }

    $acr = $null
    $acrPassword = $null
    $acrUsername = $null
    $acrLoginServer = $null
    if ($SpnAppId -ne $null -and $SpnPwdSecret -ne $null -and $SpnAppId -ne "" -and $SpnPwdSecret -ne "") {
        $spnPwd = az keyvault secret show --name $SpnPwdSecret --vault-name $VaultName | ConvertFrom-Json
        # az login `
        #     --service-principal `
        #     --username $SpnAppId `
        #     --password $spnPwd.value `
        #     --tenant $azAccount.tenantId `
        #     --allow-no-subscriptions | Out-Null

        # $acr = az acr show --name $AcrName | ConvertFrom-Json
        # az acr login --name $AcrName --username $SpnAppId --password $spnPwd.value | Out-Null
        # $acrLoginServer = "$($AcrName).azurecr.io"
        # $spnPwd.value | docker login $acrLoginServer --username $SpnAppId --password-stdin | Out-Null
        $acrPassword = $spnPwd.value
        # az account set -s $SubscriptionName
        $acrUsername = $SpnAppId
        $acrLoginServer = "$($AcrName).azurecr.io"
    }
    else {
        az acr login -n $AcrName | Out-Null
        az acr update -n $AcrName --admin-enabled true | Out-Null
        $acrPasswords = az acr credential show -n $acrName | ConvertFrom-Json
        $acrPassword = $acrPasswords.passwords[0].value
        $acrPassword = $acrPassword
        $acr = az acr show --name $AcrName | ConvertFrom-Json
        $acrUsername = $AcrName
        $acrLoginServer = $acr.loginServer
    }

    $acrCredential = @{
        loginServer = $acrLoginServer
        username    = $acrUsername
        password    = $acrPassword
    }
    $acrCredentialJson = $acrCredential | ConvertTo-Json
    $base64encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($acrCredentialJson))

    $azAccount = az account show | ConvertFrom-Json
    if ($null -ne $azAccount -and $azAccount.name -ine $VaultSubscriptionName) {
        az login | Out-Null
        az account set -s $VaultSubscriptionName
        $azAccount = az account show | ConvertFrom-Json
    }
    az keyvault secret set --name $AcrSecret --vault-name $VaultName --value $base64encoded | Out-Null

    return $acrCredential
}

function SyncDockerImageWithTag() {
    param(
        [string]$SourceAcrName = "oneesdevacr",
        [object]$SourceAcrCredential,
        [string]$TargetAcrName = "rrdpdevacr",
        [object]$TargetAcrCredential,
        [string]$ImageName = "1es/policy-engine",
        [string]$Tag
    )

    Write-Host "Login to source ACR '$SourceAcrName'..." -ForegroundColor Green
    $SourceAcrCredential.password | docker login $SourceAcrCredential.loginServer --username $SourceAcrCredential.username --password-stdin | Out-Null
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($SourceAcrCredential.username):$($SourceAcrCredential.password)"))

    Write-Host "Pulling image '$($ImageName):$($Tag)' from '$($SourceAcrCredential.loginServer)'..."
    $sourceImage = "$($SourceAcrCredential.loginServer)/$($ImageName):$($Tag)"
    $targetImage = "$($TargetAcrName).azurecr.io/$($ImageName):$($Tag)"
    docker pull $sourceImage
    docker tag $sourceImage $targetImage

    Write-Host "Pushing image '$($ImageName):$($Tag)' to '$($TargetAcrCredential.loginServer)'..."
    $TargetAcrCredential.password | docker login $TargetAcrCredential.loginServer --username $TargetAcrCredential.username --password-stdin | Out-Null
    docker push $targetImage

    Write-Host "Clearing image '$($ImageName):$($Tag)'..."
    $targetImageId = $(docker images -q --filter "reference=$targetImage")
    if ($targetImageId) {
        docker image rm $targetImageId -f
    }
    $sourceImageId = $(docker images -q --filter "reference=$sourceImage")
    if ($sourceImageId) {
        docker image rm $sourceImageId -f
    }
}

function GetAllDockerImages() {
    param(
        [string] $AcrSecret = "linuxgeneva-microsoft-credentials",
        [string] $VaultName = "xiaodoli-kv"
    )

    $acrCredentialSecret = az keyvault secret show --name $AcrSecret --vault-name $VaultName | ConvertFrom-Json
    $acrSpnCredential = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($acrCredentialSecret.value)) | ConvertFrom-Json
    docker login $acrSpnCredential.loginServer --username $acrSpnCredential.username --password $acrSpnCredential.password | Out-Null
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($acrSpnCredential.username):$($acrSpnCredential.password)"))
    $imageCatalog = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } -Method Get -Uri "https://$($acrSpnCredential.loginServer)/v2/_catalog"
    return $imageCatalog.repositories
}

function SyncDockerImage() {
    param(
        [string]$SourceAcrName = "oneesdevacr",
        [object]$SourceAcrCredential,
        [string]$TargetAcrName = "rrdpdevacr",
        [object]$TargetAcrCredential,
        [string]$ImageName = "1es/policy-engine"
    )

    Write-Host "Login to source ACR '$SourceAcrName'..." -ForegroundColor Green
    $SourceAcrCredential.password | docker login $SourceAcrCredential.loginServer --username $SourceAcrCredential.username --password-stdin | Out-Null
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($SourceAcrCredential.username):$($SourceAcrCredential.password)"))

    Write-Host "Getting source image '$imageName'..." -ForegroundColor Green
    $imageTags = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } -Method Get -Uri "https://$($SourceAcrCredential.loginServer)/v2/$($imageName)/tags/list"
    $tag = ""
    [Int64] $lastTag = 0
    $imageTags.tags | ForEach-Object {
        if ($_ -eq "latest" -and $tag -ne $_) {
            $tag = $_
        }
        elseif ($_ -ne "latest" -and $tag -ne "latest") {
            $currentTag = $_
            if ($currentTag -match "(\d+)$") {
                $tagNum = [Int64] $Matches[1]
                if ($tagNum -gt $lastTag) {
                    $lastTag = $tagNum
                    $tag = $currentTag
                }
            }
        }
    }
    if ($tag -eq "") {
        throw "Failed to get image tag"
    }

    SyncDockerImageWithTag `
        -SourceAcrName $SourceAcrName `
        -SourceAcrCredential $SourceAcrCredential `
        -TargetAcrName $TargetAcrName `
        -TargetAcrCredential $TargetAcrCredential `
        -ImageName $ImageName `
        -Tag $tag
}

function ClearLocalDockerImages() {
    param(
        [string[]] $ImagesToKeep = @(
            "oneesdevacr.azurecr.io/dotnetcore-sdk",
            "oneesdevacr.azurecr.io/aspnetcore-runtime",
            "node"
        )
    )

    LogInfo -Message "Stop running docker containers..."
    (& docker ps --quiet --filter 'status=exited' ) | Foreach-Object {
        & docker rm $_ | out-null
    }

    LogInfo -Message "Remove dangling images..."
    (& docker images --all --quiet --filter 'dangling=true') | Foreach-Object {
        & docker rmi $_ | out-null
    }

    LogInfo -Message "Stop and remove running containers..."
    (& docker ps --all --quiet) | Foreach-Object {
        & docker stop $_ | out-null
        & docker rm $_ | out-null
    }

    # Remove images that match $ImagesPattern
    (& docker images) | ForEach-Object {
        $dockerImageDetails = $_.Split(' ', 4, 'RemoveEmptyEntries')
        $imageName = $dockerImageDetails[0]
        $imageTag = $dockerImageDetails[1]
        $imageId = $dockerImageDetails[2]
        if ($imageName -ine "REPOSITORY") {
            if (-not ($ImagesToKeep -ccontains $imageName)) {
                LogInfo -Message "Removing image '$imageName' with tag '$imageTag'..."
                docker rmi -f $imageId
            }
            else {
                LogInfo -Message "Keeping image '$imageName'"
            }
        }
    }

    # Remove any unused volumes and networks
    & docker volume prune -f
    & docker network prune -f
}

function CheckImageExistance() {
    param(
        [object] $bootstrapValues,
        [string] $ImageName,
        [string] $ImageTag
    )

    $acr = az acr show -g $bootstrapValues.acr.resourceGroup -n $bootstrapValues.acr.name | ConvertFrom-Json
    az acr login -n $bootstrapValues.acr.name

    $repository = $ImageName
    if ($ImageName.StartsWith($acr.loginServer)) {
        $repository = $ImageName.Substring($acr.loginServer.Length)
        $repository = $repository.Trim("/")
    }

    $tags = az acr repository show-tags --name $bootstrapValues.acr.name --repository $repository | ConvertFrom-Json
    $foundImageTag = $tags | Where-Object { $_ -eq $ImageTag }
    return ($null -ne $foundImageTag)
}

function GetLatestImageTag() {
    param(
        [object] $bootstrapValues,
        [string] $ImageName
    )

    $acr = az acr show -g $bootstrapValues.acr.resourceGroup -n $bootstrapValues.acr.name | ConvertFrom-Json
    az acr login -n $bootstrapValues.acr.name | Out-Null

    $repository = $ImageName
    if ($ImageName.StartsWith($acr.loginServer)) {
        $repository = $ImageName.Substring($acr.loginServer.Length)
        $repository = $repository.Trim("/")
    }

    $tags = az acr repository show-tags --name $bootstrapValues.acr.name --repository $repository | ConvertFrom-Json
    $tag = ""
    [Int64] $lastTag = 0
    $tags | ForEach-Object {
        if ($_ -eq "latest" -and $tag -ne $_) {
            $tag = $_
        }
        elseif ($_ -ne "latest" -and $tag -ne "latest") {
            $currentTag = $_
            if ($currentTag -match "(\d+)$") {
                $tagNum = [Int64] $Matches[1]
                if ($tagNum -gt $lastTag) {
                    $lastTag = $tagNum
                    $tag = $currentTag
                }
            }
        }
    }

    return $tag
}