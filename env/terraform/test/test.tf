provider "azurerm" {
}

resource "azurerm_resource_group" "rg" {
  name = "testing-terraform"
  location="west us 2"
}
