
param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [string] $SpaceName = "rrdp"
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
$credentialFolder = Join-Path $envRootFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
Import-Module (Join-Path $moduleFolder "Common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "KubeUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AksUtil.psm1") -Force

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Setup-AksCluster"
LogStep -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$azAccount = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName

$aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
if (!$aksSpn) {
    throw "AKS service principal is not setup yet"
}
$aksClientApp = az ad app list --display-name $bootstrapValues.aks.clientAppName | ConvertFrom-Json
if (!$aksClientApp) {
    throw "AKS client app is not setup yet"
}
$aksSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
$aksSpnPwd = "$(az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksSpnPwdSecretName --query ""value"" -o tsv)"
az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | Out-Null


LogStep -Message "Ensure SSH key is present for linux vm access..."
EnsureSshCert `
    -VaultName $bootstrapValues.kv.name `
    -CertName $bootstrapValues.aks.ssh_private_key `
    -EnvName $EnvName `
    -EnvRootFolder $envRootFolder
$aksCertPublicKeyFile = Join-Path $envCredentialFolder "$($bootstrapValues.aks.ssh_private_key).pub"
$sshKeyData = Get-Content $aksCertPublicKeyFile


LogStep -Message "Ensure AKS cluster '$($bootstrapValues.aks.clusterName)' within resource group '$($bootstrapValues.aks.resourceGroup)' is created..."

# az aks delete `
#     --resource-group $bootstrapValues.aks.resourceGroup `
#     --name $bootstrapValues.aks.clusterName --yes
$aksClusters = az aks list `
    --resource-group $bootstrapValues.aks.resourceGroup `
    --query "[?name == '$($bootstrapValues.aks.clusterName)']" | ConvertFrom-Json

if ($null -eq $aksClusters -or $aksClusters.Count -eq 0) {
    LogInfo -Message "Creating AKS Cluster '$($bootstrapValues.aks.clusterName)'..."
    $aksClusterServicePrincipals = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
    if ($null -eq $aksClusterServicePrincipals -or $aksClusterServicePrincipals.Count -ne 1) {
        throw "Service principal '$($bootstrapValues.aks.clusterName)' is not created or have duplicates"
    }
    $aksClusterSpn = $aksClusterServicePrincipals[0]
    $aksClusterSpnPwdSecret = "$($bootstrapValues.aks.clusterName)-password"
    $aksClusterSpnPwd = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksClusterSpnPwdSecret | ConvertFrom-Json

    LogInfo -Message "AKS cluster creation started, this would take 10 - 30 min, Go grab a coffee"

    $currentUser = $env:USERNAME
    if (!$currentUser) {
        $currentUser = id -un
    }
    $currentMachine = $env:COMPUTERNAME
    if (!$currentMachine) {
        $currentMachine = hostname
    }
    $tags = @()
    $tags += "environment=$EnvName"
    $tags += "responsible=$($bootstrapValues.aks.ownerUpn)"
    $tags += "createdOn=$((Get-Date).ToString("yyyy-MM-dd"))"
    $tags += "createdBy=$currentUser"
    $tags += "fromWorkstation=$currentMachine"
    $tags += "purpose=$($bootstrapValues.aks.purpose)"
    $isWindowsOs = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq "Win32NT")
    $isUnix = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.Platform -eq "Unix")
    $isMac = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.OS.Contains("Darwin"))
    $osType = "unknown"
    if ($isWindowsOs) {
        $osType = "Windows"
    }
    elseif ($isUnix) {
        $osType = "Linux"
    }
    elseif ($isMac) {
        $osType = "Mac"
    }
    $tags += "workstationOS=$osType"

    if ($bootstrapValues.aks.useTerraform) {
        $tfFolder = Join-Path $envRootFolder "terraform"
        $aksTfFolder = Join-Path $tfFolder "aks"
        $terraformTemplateFile = Join-Path $aksTfFolder "terraform.tfvars.tpl"
        $terraformVarFile = Join-Path $aksTfFolder "terraform.tfvars"
        Copy-Item $terraformTemplateFile -Destination $terraformVarFile -Force
        Get-Content $terraformVarFile -Raw | ConvertFrom-Yaml -Ordered
        #TODO: implement teraform install
    }

    $aks = az aks create `
        --resource-group $bootstrapValues.aks.resourceGroup `
        --name $bootstrapValues.aks.clusterName `
        --kubernetes-version $bootstrapValues.aks.version `
        --admin-username $bootstrapValues.aks.adminUsername `
        --ssh-key-value $sshKeyData `
        --enable-rbac `
        --dns-name-prefix $bootstrapValues.aks.dnsPrefix `
        --node-count $bootstrapValues.aks.nodeCount `
        --node-vm-size $bootstrapValues.aks.vmSize `
        --service-principal $aksClusterSpn.appId `
        --client-secret $aksClusterSpnPwd.value `
        --aad-server-app-id $aksSpn.appId `
        --aad-server-app-secret $aksSpnPwd `
        --aad-client-app-id $aksClientApp.appId `
        --aad-tenant-id $azAccount.tenantId `
        --tags $tags | ConvertFrom-Json

    LogInfo -Message "AKS cluster is created: $($aks.id)"
    LogInfo -Message ($aks | ConvertTo-Json)

    $aksCluster = az aks show --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | ConvertFrom-Json
    if ($null -eq $aksCluster) {
        throw "Failed to create aks cluster '$($bootstrapValues.aks.clusterName)'"
    }
    else {
        LogInfo -Message "Successfully created aks cluster '$($bootstrapValues.aks.clusterName)'"
    }
}
else {
    LogInfo -Message "AKS cluster '$($bootstrapValues.aks.clusterName)' is already created."
}


# LogStep -Message "Manually add aks cluster spn client secret..."
# $aksClusterSpnClientId = $(az aks show --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --query servicePrincipalProfile.clientId -o tsv)
# $aksClusterSpnPwd = Read-Host "Enter password for service principal $($aksClusterSpnClientId): '$($bootstrapValues.aks.clusterName)'"
# $aksClusterSpnPwd = $aksClusterSpnPwd.Replace("-", "`-").Replace("$","`$")
# $aksClusterSpnPwdSecret = "$($bootstrapValues.aks.clusterName)-password"
# az keyvault secret set --vault-name $bootstrapValues.kv.name --name $aksClusterSpnPwdSecret --value $aksClusterSpnPwd | Out-Null


<#
when this command failed with the following error:
    Operation failed with status: 'Bad Request'.
    Details: Service principal clientID: *** not found in Active Directory tenant ***,
    Please see https://aka.ms/aks-sp-help for more details.
check credential file cached here and make sure it's the same:
    ls -la $HOME/.azure/aksServicePrincipal.json
#>

LogStep -Message "Set AKS context..."
# rm -rf /Users/xiaodongli/.kube/config
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin
LogInfo -Message "Grant dashboard access..."
$templatesFolder = Join-Path $envRootFolder "templates"
$yamlsFolder = Join-Path $scriptFolder "yamls"
if (-not (Test-Path $yamlsFolder)) {
    New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
}
$dashboardAuthYamlFile = Join-Path $templatesFolder "dashboard-admin.yaml"
kubectl apply -f $dashboardAuthYamlFile

LogInfo -Message "Grant current user as cluster admin..."
$currentPrincipalName = $(az ad signed-in-user show | ConvertFrom-Json).userPrincipalName
$aadUser = az ad user show --upn-or-object-id $currentPrincipalName | ConvertFrom-Json
$userAuthTplFile = Join-Path $templatesFolder "user-admin.tpl"
$userAuthYamlFile = Join-Path $yamlsFolder "user-admin.yaml"
Copy-Item -Path $userAuthTplFile -Destination $userAuthYamlFile -Force
ReplaceValuesInYamlFile -YamlFile $userAuthYamlFile -PlaceHolder "ownerUpn" -Value $aadUser.objectId
kubectl apply -f $userAuthYamlFile

LogInfo -Message "Ensure user ($currentPrincipalName) has admin rights to the cluster '$($bootstrapValues.aks.clusterName)'..."
$aksCluster = az aks show --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | ConvertFrom-Json
$existingAssignments = az role assignment list --assignee $aadUser.objectId --role owner --scope $aksCluster.id | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --assignee $aadUser.objectId --role owner --scope $aksCluster.id | Out-Null
}
else {
    LogInfo -Message "Assignment already exists"
}

LogInfo -Message "Set access control to cluster '$($bootstrapValues.aks.clusterName)'..."
$aksOwnerUsers = New-Object System.Collections.ArrayList
$aksOwnerGroups = New-Object System.Collections.ArrayList
if ($null -ne $bootstrapValues.aks.access.owners -and $bootstrapValues.aks.access.owners.Count -gt 0) {
    $bootstrapValues.aks.access.owners | ForEach-Object {
        if ($_.type -eq "user") {
            $aksOwnerUsers.Add($_.name) | Out-Null
        }
        else {
            $aksOwnerGroups.Add($_.name) | Out-Null
        }
    }
    AddAksRoleAssignment `
        -Users $aksOwnerUsers `
        -Groups $aksOwnerGroups `
        -RoleName owner `
        -AksResourceId $aksCluster.id `
        -TemplatesFolder $templatesFolder `
        -ScriptFolder $scriptFolder
}

$aksContributorUsers = New-Object System.Collections.ArrayList
$aksContributorGroups = New-Object System.Collections.ArrayList
if ($null -ne $bootstrapValues.aks.access.contributors -and $bootstrapValues.aks.access.contributors.Count -gt 0) {
    $bootstrapValues.aks.access.contributors | ForEach-Object {
        if ($_.type -eq "user") {
            $aksContributorUsers.Add($_.name) | Out-Null
        }
        else {
            $aksContributorGroups.Add($_.name) | Out-Null
        }
    }
    AddAksRoleAssignment `
        -Users $aksContributorUsers `
        -Groups $aksContributorGroups `
        -RoleName contributor `
        -AksResourceId $aksCluster.id `
        -TemplatesFolder $templatesFolder `
        -ScriptFolder $scriptFolder
}

$aksReaderUsers = New-Object System.Collections.ArrayList
$aksReaderGroups = New-Object System.Collections.ArrayList
if ($null -ne $bootstrapValues.aks.access.readers -and $bootstrapValues.aks.access.readers.Count -gt 0) {
    $bootstrapValues.aks.access.readers | ForEach-Object {
        if ($_.type -eq "user") {
            $aksReaderUsers.Add($_.name) | Out-Null
        }
        else {
            $aksReaderGroups.Add($_.name) | Out-Null
        }
    }
    AddAksRoleAssignment `
        -Users $aksReaderUsers `
        -Groups $aksReaderGroups `
        -RoleName reader `
        -AksResourceId $aksCluster.id `
        -TemplatesFolder $templatesFolder `
        -ScriptFolder $scriptFolder
}


$kubeContextName = "$(kubectl config current-context)"
LogInfo -Message "You are now connected to kubenetes context: '$kubeContextName'"


LogStep -Message "Setup helm integration..."
# we can also apply file env/templates/helm-rbac.yaml
kubectl -n kube-system create sa tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --upgrade


LogStep -Message "Set addons...(will take a few minutes)"

LogInfo -Message "Enable monitoring on AKS cluster..."
az aks enable-addons `
    --resource-group $bootstrapValues.aks.resourceGroup `
    --name $bootstrapValues.aks.clusterName `
    --addons monitoring | Out-Null

LogInfo -Message "Enable devspaces on AKS cluster..."
az aks use-dev-spaces `
    --resource-group $bootstrapValues.aks.resourceGroup `
    --name $bootstrapValues.aks.clusterName `
    -s $SpaceName -y | Out-Null

LogInfo -Message "Map devspace to K8S namespace"
kubectl create namespace $SpaceName

LogInfo -Message "Enable http_application_routing on AKS cluster (required by istio) ..."
az aks enable-addons `
    --resource-group $bootstrapValues.aks.resourceGroup `
    --name $bootstrapValues.aks.clusterName `
    --addons http_application_routing | Out-Null


LogStep -Message "Setup k8s ingress..."
if ($bootstrapValues.aks.ingress -contains "nginx") {
    LogInfo "Setting up k8s ingress ..."
    & "$scriptFolder\Setup-DNS.ps1" -EnvName $EnvName -SpaceName $SpaceName
}
else {
    LogInfo "nginx is not enabled"
}


LogStep -Message "Ensure aks service principal has access to ACR..."
$acrName = $bootstrapValues.acr.name
$acrResourceGroup = $bootstrapValues.acr.resourceGroup
$acrFound = "$(az acr list -g $acrResourceGroup --query ""[?contains(name, '$acrName')]"" --query [].name -o tsv)"
if (!$acrFound) {
    throw "Please setup ACR first by running Setup-ContainerRegistry.ps1 script"
}
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
$aksSpnName = $bootstrapValues.aks.servicePrincipal
$aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
$existingAssignments = az role assignment list --assignee $aksSpn.appId --scope $acrId --role contributor | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --assignee $aksSpn.appId --scope $acrId --role contributor | Out-Null
}
else {
    LogInfo -Message "Assignment already exists."
}

$aksClusterSpn = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
if ($null -eq $aksClusterSpn -or $aksClusterSpn.Count -ne 1) {
    throw "Unable to find service principal for aks cluster"
}
$aksClusterSpnAppId = $aksClusterSpn[0].appId
$existingAssignments = az role assignment list --assignee $aksClusterSpnAppId --scope $acrId --role contributor | ConvertFrom-Json
if ($existingAssignments.Count -eq 0) {
    az role assignment create --assignee $aksClusterSpnAppId --scope $acrId --role contributor | Out-Null
}
else {
    LogInfo -Message "Assignment already exists."
}


LogInfo -Message "Creating kube secret to store docker repo credential..."
$acr = az acr show -g $bootstrapValues.acr.resourceGroup -n $acrName | ConvertFrom-Json
$acrUsername = $acrName
$acrPassword = "$(az acr credential show -n $acrName --query ""passwords[0].value"")"
$acrLoginServer = $acr.loginServer
$acrEmail = $bootstrapValues.acr.email
$allNamespaces = @("azds", "default", $SpaceName, "monitoring", "ingress-nginx")
$k8sNamespaces = kubectl get ns -o json | ConvertFrom-Json
$allNamespaces | ForEach-Object {
    $ns = $_
    $k8sNs = $k8sNamespaces.items | Where-Object { $_.metadata.name -eq $ns }
    if ($null -eq $k8sNs) {
        LogInfo -Message "Creating k8s namespace '$ns'..."
        kubectl create namespace $ns
    }

    LogInfo -Message "Ensure k8s secret for acr is created in namespace '$ns'..."
    kubectl create secret docker-registry acr-auth `
        -n $ns `
        --docker-server=$acrLoginServer `
        --docker-username=$acrUsername `
        --docker-password=$acrPassword `
        --docker-email=$acrEmail | Out-Null
}


LogStep -Message "Create k8s secrets..."
if ($bootstrapValues.aks.keyVaultAccess -contains "podIdentity") {
    LogInfo -Message "Setting up pod id
    entity..."
    kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
}

if ($bootstrapValues.aks.secrets.addKeyVaultAccess) {
    $spnName = $bootstrapValues.aks.servicePrincipal
    $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
    $vaultName = $bootstrapValues.kv.name
    $spPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
    $spnPwd = (az keyvault secret show --vault-name $vaultName --name $spPwdSecretName | ConvertFrom-Json).value
    $clientId = $sp.appId
    $vaultUrl = "https://$vaultName.vault.azure.net/"

    LogInfo -Message "Creating config map for key vault settings..."
    SetConfigMap -Key "vault" -name "vault" -Value $vaultName -Namespace $SpaceName -ScriptFolder $scriptFolder -EnvRootFolder $envRootFolder
    SetConfigMap -Key "kvuri" -name "kvuri" -Value $vaultUrl -Namespace $SpaceName -ScriptFolder $scriptFolder -EnvRootFolder $envRootFolder
    SetConfigMap -Key "clientid" -name "clientid" -Value $clientId -Namespace $SpaceName -ScriptFolder $scriptFolder -EnvRootFolder $envRootFolder

    LogInfo -Message "Create k8s secret for key vault access..."
    SetSecret -Key "clientsecret" -name "clientsecret" -Value $spnPwd -Namespace $SpaceName -ScriptFolder $scriptFolder -EnvRootFolder $envRootFolder
}

if ($null -ne $bootstrapValues.aks.certs -and $bootstrapValues.aks.certs.Count -gt 0) {
    LogInfo "Install certificates to k8s..."
    & "$scriptFolder\Setup-AksCertificate.ps1" -EnvName $EnvName -SpaceName $SpaceName
}


LogStep -Message "Bootstrap keyvault access..."
if ($bootstrapValues.aks.keyVaultAccess -contains "secretBroker") {
    LogInfo -Message "Install secret broker to k8s..."
    & "$scriptFolder\Setup-SecretBroker.ps1" -EnvName $EnvName -SpaceName $SpaceName -UseOldImage $false

    LogInfo -Message "Ensure cluster spn have read access to key vault (required by secret-broker)..."
    $aksClusterServicePrincipals = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
    if ($null -ne $aksClusterServicePrincipals -and $aksClusterServicePrincipals.Count -eq 1) {
        $aksSpn = $aksClusterServicePrincipals[0]
        az keyvault set-policy `
            --name $($bootstrapValues.kv.name) `
            --resource-group $bootstrapValues.kv.resourceGroup `
            --object-id $aksSpn.objectId `
            --spn $aksSpn.displayName `
            --certificate-permissions get list `
            --secret-permissions get list | Out-Null
    }
    else {
        throw "Failed to find aks cluster spn by name '$($bootstrapValues.aks.clusterName)'"
    }
}
if ($bootstrapValues.aks.keyVaultAccess -contains "podIdentity") {
    LogInfo "Install aad pod identity to k8s..."
    & "$scriptFolder\Setup-AadPodIdentity.ps1" -EnvName $EnvName -SpaceName $SpaceName
}


LogStep -Message "Setup geneva hot path..."
if ($bootstrapValues.aks.metrics -contains "geneva") {
    LogInfo "Setting up geneva mdm..."
    & "$scriptFolder\Setup-GenevaMetrics.ps1" -EnvName $EnvName -SpaceName $SpaceName
}
else {
    LogInfo "geneva mdm is disabled"
}


LogStep -Message "Setup geneva warm path..."
if ($bootstrapValues.aks.logging -contains "geneva") {
    LogInfo "Setting up geneva mds..."
    & "$scriptFolder\Setup-GenevaService.ps1" -EnvName $EnvName -SpaceName $SpaceName
}
else {
    LogInfo "geneva mds is disabled"
}




# if ($bootstrapValues.aks.useCertManager) {
#     LogStep -Message "Setup cert-manager..."
#     & "$scriptFolder\Setup-CertManager.ps1" -EnvName $EnvName -SpaceName $SpaceName
#     & "$scriptFolder\Setup-LetsEncrypt.ps1" -EnvName $EnvName -SpaceName $SpaceName
# }


LogStep -Message "Setup monitoring infrastructure..."
if ($bootstrapValues.aks.metrics -contains "prometheus" -or $bootstrapValues.aks.logging -contains "prometheus") {
    LogInfo "Setting up prometheus..."
    & "$scriptFolder\Setup-Prometheus.ps1" -EnvName $EnvName -SpaceName $SpaceName
}
else {
    LogInfo -Message "prometheus is disabled"
}
