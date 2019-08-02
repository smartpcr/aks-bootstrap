function SyncHelmChartBetweenAcrs() {
    param(
        [string]$FromSubscription = "Compliance_Tools_Eng",
        [string]$FromAcr = "oneesdevacr",
        [string]$ToSubscription = "RRD MSDN Premium",
        [string]$ToAcr = "rrdpdevacr",
        [string]$scriptFolder = "C:\work\my\userspace\scripts"
    )

    $chartsFolder = Join-Path $scriptFolder "charts"
    if (-not (Test-Path $chartsFolder)) {
        New-Item -Path $chartsFolder -ItemType Directory -Force | Out-Null
    }

    LoginAzureAsUser -SubscriptionName $FromSubscription | Out-Null
    az acr login -n $FromAcr | Out-Null
    az acr update -n $FromAcr --admin-enabled true | Out-Null
    # $acrPasswords = az acr credential show -n $FromAcr | ConvertFrom-Json
    # $acrPassword = $acrPasswords.passwords[0].value
    # $acrPassword = $acrPassword
    # $acr = az acr show --name $FromAcr | ConvertFrom-Json
    az acr helm repo add --name $FromAcr
    $helmCharts = az acr helm list -n $FromAcr | ConvertFrom-Json

    $chartFiles = New-Object System.Collections.ArrayList
    $helmCharts | Get-Member -MemberType NoteProperty | ForEach-Object {
        $chartName = $_.Name
        Write-Host "Pulling chart '$chartName'..."
        helm fetch "$FromAcr/$ChartName" --destination $chartsFolder
        [System.IO.FileSystemInfo]$chartFile = Get-ChildItem -Path $chartsFolder -Filter "$ChartName*.tgz"
        if ($null -eq $chartFile) {
            throw "Failed to get chart '$FromRepoName/$ChartName'"
        }
        $chartFiles.Add($chartFile.FullName) | Out-Null
    }

    LoginAzureAsUser -SubscriptionName $ToSubscription | Out-Null
    az acr login -n $ToAcr | Out-Null
    az acr update -n $ToAcr --admin-enabled true | Out-Null
    az acr helm repo add --name $ToAcr
    $chartFiles | ForEach-Object {
        $chartFilePath = $_
        Write-Host "Pussing chart '$chartFilePath'.."
        az acr helm push --name $ToAcr $chartFilePath | Out-Null
        Remove-Item $chartFilePath -Force | Out-Null
    }
}

function PushHelmChartToAcr() {
    param(
        [string]$FromRepoName = "stable",
        [string]$FromRepoUrl = "https://kubernetes-charts.storage.googleapis.com",
        [string]$ChartName = "prometheus-operator",
        [string]$TargetSubscription = "Compliance_Tools_Eng",
        [string]$TargetAcr = "oneesdevacr",
        [string]$scriptFolder = "C:\work\my\userspace\scripts"
    )

    LoginAzureAsUser -SubscriptionName $TargetSubscription | Out-Null
    az acr login -n $TargetAcr | Out-Null
    az acr update -n $TargetAcr --admin-enabled true | Out-Null
    az acr helm repo add --name $TargetAcr

    $helmConfigFile = Join-Path (Join-Path (Join-Path $HOME ".helm") "repository") "repositories.yaml"
    if (-not (Test-Path $helmConfigFile)) {
        helm init
    }
    $helmRepos = Get-Content -Path $helmConfigFile -Raw | ConvertFrom-Yaml2 -Ordered
    $repoFound = $helmRepos.repositories | Where-Object { $_.name -eq $FromRepoName }
    if ($null -eq $repoFound) {
        helm repo add $FromRepoName $FromRepoUrl
        helm repo update
    }

    $chartsFolder = Join-Path $scriptFolder "charts"
    if (-not (Test-Path $chartsFolder)) {
        New-Item -Path $chartsFolder -ItemType Directory -Force | Out-Null
    }
    helm fetch "$FromRepoName/$ChartName" --destination $chartsFolder
    [System.IO.FileSystemInfo]$chartFile = Get-ChildItem -Path $chartsFolder -Filter "$ChartName*.tgz"
    if ($null -eq $chartFile) {
        throw "Failed to get chart '$FromRepoName/$ChartName'"
    }
    az acr helm push --name $TargetAcr $chartFile.FullName | Out-Null
    Remove-Item $chartFile.FullName -Force | Out-Null
}