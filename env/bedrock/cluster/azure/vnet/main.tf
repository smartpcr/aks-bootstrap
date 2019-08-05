resource "azurerm_resource_group" "vnet" {
  name = "${var.resource_group_name}"
  location = "${var.resource_group_location}"
}

resource "azurerm_virtual_network" "vnet" {
  name = "${var.vnet_name}"
  location = "${azurerm_resource_group.vnet.location}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"
  address_space = "${var.address_space}"
  dns_servers = "${var.dns_servers}"
  tags = "${var.tags}"
}

resource "azurerm_subnet" "subnet" {
  name = "${var.subnet_names[count.index]}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  resource_group_name = "${azurerm_resource_group.vnet.name}"
  address_prefix = "${var.subnet_prefixes[count.index]}"
  count = "${length(var.subnet_names)}"
}
