variable "vnet_name" {
  type        = "string"
  description = "name of vnet"
}

variable "resource_group_name" {
  type        = "string"
  default     = "bedrock_rg"
  description = "default resource group name for vnet"
}

variable "resource_group_location" {
  type        = "string"
  description = "Default resource group location for vnet"
}

variable "address_space" {
  type        = "string"
  description = "address space that is used by vnet"
  default     = "10.10.0.0/16"
}

variable "dns_servers" {
  type        = "list"
  description = "DNS servers to be used with vnet"
  default     = []
}

variable "subnet_prefixes" {
  type        = "list"
  description = "address previx to use for the subnet"
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "subnet_names" {
  type        = "list"
  description = "list of public subnets inside vnet"
  default     = ["subnet1", "subnet2"]
}

variable "tags" {
  type        = "map"
  description = "tags associated with vnet"

  default = {
    tag1 = ""
    tag2 = ""
  }
}
