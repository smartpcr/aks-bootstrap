variable subscription_id {
  description = "ID of azure subscription"
}

variable tenant_id {
  description = "ID of AAD directory tenant"
}

variable client_id {
  description = "Application Id of terraform service principal"
}

variable client_secret {
  description = "Password of terraform service principal"
}

variable "location" {
  type = "string"
  default = "west us 2"
}


variable "aks_service_principal_app_id" {
  type = "string"
}

variable "aks_service_principal_password" {
  type = "string"
}

variable "aks_ssh_public_key" {
  type = "string"
}

variable "dns_prefix" {
  type = "string"
  default = "test"
}


variable "resource_group_name" {
  type = "string"
}

variable "aks_resource_group_name" {
  type = "string"
}

variable "tags" {
  type = "map"

  default = {
    Environment = "dev"
    Responsible = "Xiaodong Li"
  }
}

variable "aks_name" {
  type = "string"
}

variable "aks_agent_vm_size" {
  type    = "string"
  default = "Standard_D2_v2"
}

variable "aks_agent_vm_count" {
  type    = "string"
  default = "2"
}

variable "k8s_version" {
  type    = "string"
  default = "1.9.6"
}