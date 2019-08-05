variable "keyvault_name" {
  type = "string"
  description = "Name of the keyvault to create"
  default = "bedrock-kv"
}

variable "keyvault_sku" {
  type = "string"
  description = "SKU of the keyvault to create"
  default = "standard"
}

variable "resource_group_name" {
  type = "string"
  description = "Default resource group name that the key vault will be created in"
}

variable "location" {
  type = "string"
  description = "The location/region where keyvault will be created in."
  default = "west us 2"
}
