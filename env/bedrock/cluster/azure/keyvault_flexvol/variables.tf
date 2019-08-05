variable "resource_group_name" {
  type = "string"
}

variable "service_principal_id" {
  type = "string"
}

variable "service_principal_secret" {
  type = "string"
}

variable "tenant_id" {
  type = "string"
}

variable "subscription_id" {
  type = "string"
}

variable "flexvol_role_assignment_role" {
  type = "string"
  description = "The role to give the AKS service principal to access the keyvault"
  default = "Reader"
}

variable "flexvol_keyvault_key_permissions" {
  type = "list"
  description = "Permissions that AKS cluster has for accessing keys from keyvault"
  default = ["create", "delete", "get"]
}

variable "flexvol_keyvault_secret_permissions" {
    description = "Permissions that the AKS cluster has for accessing secrets from KeyVault"
    type = "list"
    default = ["set", "delete", "get"]
}

variable "flexvol_keyvault_certificate_permissions" {
    description = "Permissions that the AKS cluster has for accessing certificates from KeyVault"
    type = "list"
    default = ["create", "delete", "get"]
}

variable "flexvol_deployment_url" {
  type = "string"
  description = "The url to the yaml file for deploying the keyvault flex volume."
  default = "https://raw.githubusercontent.com/Azure/kubernetes-keyvault-flexvol/31f593250045e8dc861e13a8e943284787b7f17e/deployment/kv-flexvol-installer.yaml"
}

variable "output_directory" {
  type = "string"
  default = "./output"
}

variable "enable_flexvol" {
  type = "string"
  default = "true"
}

variable "keyvault_name" {
  type = "string"
  description = "The name of the keyvault that will be associated with the flex volume"
}

variable "flexvol_recreate" {
  type = "string"
  description = "Make any change to this value to trigger the recreation of the flex volume execution script"
  default = ""
}

variable "kubeconfig_filename" {
  type = "string"
  description = "Name of kube config file saved to disk"
  default = "bedrock_kube_config"
}

variable "kubeconfig_complete" {
  type = "string"
  description = "Allows flex volume deployment to wait for the kubeconfig completion write to disk. Workaround for the fact that modules themselves cannot have dependencies."
}

