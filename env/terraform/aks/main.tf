provider "azurerm" {
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
  subscription_id = "${var.subscription_id}"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}"
  location = "${var.location}"
  tags     = "${var.tags}"
}

resource "azurerm_resource_group" "rg-aks" {
  name     = "${var.aks_resource_group_name}"
  location = "${var.location}"
  tags     = "${var.tags}"
}

# this creates a cluster without RBAC support, useless!!
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.aks_name}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg-aks.name}"
  kubernetes_version  = "${var.k8s_version}"

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = "${file("${var.aks_ssh_public_key}")}"
    }
  }

  dns_prefix = "${var.dns_prefix}"

  agent_pool_profile {
    name    = "default"
    count   = "${var.aks_agent_vm_count}"
    vm_size = "${var.aks_agent_vm_size}"
    os_type = "Linux"
  }

  service_principal {
    client_id     = "${var.aks_service_principal_app_id}"
    client_secret = "${var.aks_service_principal_password}"
  }

  tags = "${var.tags}"
}
