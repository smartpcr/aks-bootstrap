output "vnet_id" {
  value = "${azurerm_virtual_network.vnet.id}"
  description = "id of vnet"
}

output "vnet_name" {
  value = "${azurerm_virtual_network.vnet.name}"
}

output "vnet_location" {
  value = "${azurerm_virtual_network.vnet.location}"
}

output "vnet_address_space" {
  value = "${azurerm_virtual_network.vnet.address_space}"
}

output "vnet_subnet_ids" {
  value = "${azurerm_subnet.subnet.*.id}"
}
