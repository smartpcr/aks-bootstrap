
function AddAdditionalAksProperties() {
    param(
        [object]$bootstrapValues
    )

    $bootstrapValues.aks["nodeResourceGroup"] = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $bootstrapValues.aks["networkSecurityGroup"] = (GetNetworkSecurityGroup -bootstrapValues $bootstrapValues).name
    $bootstrapValues.aks["virtualNetwork"] = (GetVirtualNetwork -bootstrapValues $bootstrapValues).name
    $bootstrapValues.aks["routeTable"] = (GetRouteTable -bootstrapValues $bootstrapValues).name
    $bootstrapValues.aks["availabilitySet"] = (GetAvailabilitySet -bootstrapValues $bootstrapValues).name

    [array]$aksClusterSpns = az ad sp list --display-name $bootstrapValues.aks.clusterName | ConvertFrom-Json
    if ($null -eq $aksClusterSpns -or $aksClusterSpns.Count -ne 1) {
        throw "Unable to find aks cluster spn '$($bootstrapValues.aks.clusterName)'"
    }
    $aksClusterSpnPwdSecret = "$($bootstrapValues.aks.clusterName)-password"
    $aksClusterSpnPwd = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksClusterSpnPwdSecret | ConvertFrom-Json
    $aksClusterSpn = @{
        appId        = $aksClusterSpns[0].appId
        clientSecret = $aksClusterSpnPwd.value
    }
    $bootstrapValues.aks["clusterSpn"] = $aksClusterSpn

    $aksPublicSshKey = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $bootstrapValues.aks.ssh_pubblic_key | ConvertFrom-Json
    # az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.aks.ssh_pubblic_key --value $aksPublicSshKey.value
    $bootstrapValues.aks["nodePublicSshKey"] = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($aksPublicSshKey.value))).Trim()
}


function GetAksResourceGroupName() {
    param(
        [object] $bootstrapValues
    )

    $defaultResourceGroupName = $bootstrapValues.global.resourceGroup
    $aksClusterName = $bootstrapValues.aks.clusterName
    $location = $bootstrapValues.aks.location
    $mcResourceGroupName = "MC_$($defaultResourceGroupName)_$($aksClusterName)_$($location)"

    return $mcResourceGroupName
}

function EnsureServiceIentity() {
    param(
        [string] $serviceName,
        [object] $bootstrapValues
    )

    $serviceIdentity = $null
    $mcResourceGroupName = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $msiArray = az identity list --resource-group $mcResourceGroupName --query "[?name=='$serviceName']" | ConvertFrom-Json
    if (!$msiArray -or ([array]$msiArray).Count -eq 0) {
        LogInfo -Message "Creating MSI '$serviceName'..."
        $serviceIdentity = az identity create -g $mcResourceGroupName -n $serviceName | ConvertFrom-Json
        LogInfo -Message "Waiting for msi '$serviceName' to become available..."
        Start-Sleep -Seconds 10
        $serviceIdentity = az identity show --resource-group $mcResourceGroupName --name $serviceName | ConvertFrom-Json
    }
    else {
        $serviceIdentity = az identity show --resource-group $mcResourceGroupName --name $serviceName | ConvertFrom-Json
        LogInfo -Message "MSI '$serviceName' is already created."
    }

    return $serviceIdentity
}

function GrantAccessToUserAssignedIdentity() {
    param(
        [object] $serviceIdentity,
        [object] $bootstrapValues
    )

    $scopeIds = New-Object System.Collections.ArrayList

    $defaultResourceGroupName = $bootstrapValues.global.resourceGroup
    $rg = az group show --name $defaultResourceGroupName | ConvertFrom-Json
    $scopeIds.Add($rg.id) | Out-Null

    $mcResourceGroupName = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $mcRG = az group show --name $mcResourceGroupName | ConvertFrom-Json
    $scopeIds.Add($mcRG.id) | Out-Null

    $vaultName = $bootstrapValues.kv.name
    $kv = az keyvault show --resource-group $defaultResourceGroupName --name $vaultName | ConvertFrom-Json
    $scopeIds.Add($kv.id) | Out-Null
    LogInfo -Message "Set key vault access policy to include managed identity '$($serviceIdentity.name)'..."
    az keyvault set-policy -n $vaultName --secret-permissions get list --spn $serviceIdentity.clientId | Out-Null
    az keyvault set-policy -n $vaultName --certificate-permissions get list --spn $serviceIdentity.clientId | Out-Null

    $scopeIds | ForEach-Object {
        $scopeId = $_
        LogInfo -Message "Grant permission for managed identity '$($serviceIdentity.name)' to scope '$scopeId'..."
        $existingAssignments = az role assignment list --role Reader --assignee $serviceIdentity.principalId --scope $scopeId | ConvertFrom-Json
        if ($null -eq $existingAssignments -or $existingAssignments.Count -eq 0) {
            az role assignment create --role Reader --assignee $serviceIdentity.principalId --scope $scopeId | Out-Null
        }
        else {
            LogInfo "Assignment already exists"
        }
    }

    $aksSpnName = $bootstrapValues.aks.servicePrincipal
    $aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
    LogInfo -Message "Grant permission for aks spn '$($aksSpnName)' to service identity '$($serviceIdentity.name)'..."
    $existingAssignments = az role assignment list --role "Managed Identity Operator" --assignee $aksSpn.appId --scope $serviceIdentity.id | ConvertFrom-Json
    if ($null -eq $existingAssignments -or $existingAssignments.Count -eq 0) {
        az role assignment create --role "Managed Identity Operator" --assignee $aksSpn.appId --scope $serviceIdentity.id | Out-Null
    }
    else {
        LogInfo "Assignment already exists"
    }
}

function GetRouteTable() {
    param(
        [HashTable] $bootstrapValues
    )

    $nodeResourceGroup = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $routeTables = az network route-table list -g $nodeResourceGroup | ConvertFrom-Json
    return $routeTables[0]
}

function GetNetworkSecurityGroup() {
    param(
        [HashTable] $bootstrapValues
    )

    $nodeResourceGroup = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $nsgs = az network nsg list -g $nodeResourceGroup | ConvertFrom-Json
    return $nsgs[0]
}

function GetVirtualNetwork() {
    param(
        [HashTable] $bootstrapValues
    )

    $nodeResourceGroup = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $vnets = az network vnet list -g $nodeResourceGroup | ConvertFrom-Json
    return $vnets[0]
}

function GetAvailabilitySet() {
    param(
        [HashTable] $bootstrapValues
    )

    $nodeResourceGroup = GetAksResourceGroupName -bootstrapValues $bootstrapValues
    $availabilitySets = az vm availability-set list -g $nodeResourceGroup | ConvertFrom-Json
    return $availabilitySets[0]
}

function AddAksRoleAssignment() {
    param(
        [string[]] $Users,
        [string[]] $Groups,
        [ValidateSet("owner", "contributor", "reader")]
        [string] $RoleName,
        [string] $AksResourceId,
        [string] $TemplatesFolder,
        [string] $ScriptFolder
    )

    $subjects = New-Object System.Collections.ArrayList
    if ($null -ne $Users -and $Users.Count -gt 0) {
        $Users | ForEach-Object {
            $DisplayName = $_
            $ownerUsers = az ad user list --upn $DisplayName | ConvertFrom-Json
            if ($null -eq $ownerUsers -or $ownerUsers.Count -eq 0) {
                LogInfo -Message "User '$DisplayName' cannot be found"
            }
            else {
                if ($RoleName -eq "owner") {
                    $subjects.Add(@{
                        apiGroup  = "rbac.authorization.k8s.io"
                        kind      = "User"
                        name      = $ownerUsers[0].objectId
                    }) | Out-Null
                }
                else {
                    $subjects.Add(@{
                        apiGroup  = "rbac.authorization.k8s.io"
                        kind      = "User"
                        namespace = "default"
                        name      = $ownerUsers[0].objectId
                    }) | Out-Null
                }

            }
        }
    }
    if ($null -ne $Groups -and $Groups.Count -gt 0) {
        $Groups | ForEach-Object {
            $DisplayName = $_
            $ownerGroups = az ad group list --display-name $DisplayName | ConvertFrom-Json
            if ($null -eq $ownerGroups -or $ownerGroups.Count -eq 0) {
                LogInfo -Message "User '$DisplayName' cannot be found"
            }
            else {
                if ($RoleName -eq "owner") {
                    $subjects.Add(@{
                        apiGroup  = "rbac.authorization.k8s.io"
                        kind      = "Group"
                        name      = $ownerGroups[0].objectId
                    }) | Out-Null
                }
                else {
                    $subjects.Add(@{
                        apiGroup  = "rbac.authorization.k8s.io"
                        kind      = "Group"
                        namespace = "default"
                        name      = $ownerGroups[0].objectId
                    }) | Out-Null
                }
            }
        }
    }

    $yamlsFolder = Join-Path $scriptFolder "yamls"
    if (-not (Test-Path $yamlsFolder)) {
        New-Item -Path $yamlsFolder -ItemType Directory -Force | Out-Null
    }
    $accessControlYamlFile = Join-Path $yamlsFolder "Aks-Access-$RoleName.yaml"
    $accessControlTemplateFile = Join-Path $templatesFolder "k8s-$($RoleName)s.yaml"
    $accessControlTemplate = Get-Content $accessControlTemplateFile -Raw
    $accessControl = $accessControlTemplate | ConvertFrom-Yaml -Ordered
    if ($RoleName -eq "owner") {
        $accessControl.subjects = $subjects
    }
    $accessControlTemplate = $accessControl | ConvertTo-Yaml
    $accessControlTemplate | Out-File $accessControlYamlFile -Encoding utf8 -Force | Out-Null
    kubectl apply -f $accessControlYamlFile

    $roleBindingYaml = $null
    if ($RoleName -eq "contributor") {
        $roleBindingYaml = @"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: contributors-default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: contributor-default
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  namespace: default
  name: {{ .Values.aadObjectId }}
"@
    }
    elseif ($RoleName -eq "reader") {
        $roleBindingYaml = @"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: readers-default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: reader-default
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  namespace: default
  name: {{ .Values.aadObjectId }}
"@
    }

    if ($null -ne $roleBindingYaml) {
        $roleBindingYamlFile = Join-Path $yamlsFolder "RoleBinding-$RoleName.yaml"
        $roleBinding = $roleBindingYaml | ConvertFrom-Yaml -Ordered
        $roleBinding.subjects = $subjects
        $roleBindingYaml = $roleBinding | ConvertTo-Yaml
        $roleBindingYaml | Out-File $roleBindingYamlFile -Encoding utf8 -Force | Out-Null
        kubectl apply -f $roleBindingYamlFile
    }
}