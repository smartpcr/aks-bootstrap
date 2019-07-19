resource_group_name = "{{.Values.global.resourceGroup}}"

location = "{{.Values.global.location}}"

tags = {
  Responsible = "{{.Values.global.owner}}"
  Environment = "{{.Values.runtime.env}}"
  Space = "{{.Values.runtime.spacename}}"
}

# aks
aks_resource_group_name = "{{.Values.aks.resourceGroup}}"

aks_name = "{{.Values.aks.clusterName}}"

aks_agent_vm_count = "{{.Values.aks.nodeCount}}"

aks_agent_vm_size = "{{.Values.aks.vmSize}}"

k8s_version = "{{.Values.aks.version}}"

aks_service_principal_app_id = "{{.Values.runtime.aksServicePrincipalAppId}}"

dns_prefix = "{{.Values.aks.dnsPrefix}}"

aks_ssh_public_key = "{{.Values.runtime.aksSshPublicKeyFile}}"

acr_name = "{{.Values.acr.name}}"

acr_resource_group_name = "{{.Values.acr.resourceGroup}}"