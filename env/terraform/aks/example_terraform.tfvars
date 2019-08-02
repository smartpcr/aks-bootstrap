# this is an example of output generated based on env settings and template

resource_group_name = "helloworld-dev-xd-wus2-rg"

location = "westus2"

tags = {
  Responsible = "Xiaodong Li"
  Environment = "Dev"
}

# aks
aks_resource_group_name = "helloworld-dev-xd-k8s-rg"

aks_name = "helloworld-dev-xd-k8s-cluster"

aks_agent_vm_count = "2"

aks_agent_vm_size = "Standard_D2_v2"

k8s_version = "1.11.1"

aks_service_principal_app_id = "831e0d3c-26ee-4ba5-a073-59402b1d442e"

dns_prefix = "hw-aks-xd"

aks_ssh_public_key = "C:\\work\\github\\container\\helloworld\\scripts\\env\\credential\\dev\\helloworld-dev-xd-k8s-ssh-key.pub"

acr_name = "xddevacr"

acr_resource_group_name = "xd-acr-rg"