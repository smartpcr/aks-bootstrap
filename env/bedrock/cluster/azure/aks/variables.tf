variable "resource_group_name" {
  type = "string"
}

variable "resource_group_location" {
  type = "string"
}

variable "cluster_name" {
  type    = "string"
  default = "bedrockaks"
}

variable "dns_prefix" {
  type = "string"
}

variable "service_principal_id" {
  type = "string"
}

variable "service_principal_secret" {
  type = "string"
}

variable "agent_vm_count" {
  type    = "string"
  default = "2"
}

variable "agent_vm_size" {
  type    = "string"
  default = "Standard_D2s_v3"
}

variable "kubernetes_version" {
  type    = "string"
  default = "1.12.6"
}

variable "admin_user" {
  type    = "string"
  default = "k8sadmin"
}

variable "ssh_public_key" {
  type = "string"
}

variable "output_directory" {
  type    = "string"
  default = "./output"
}

variable "vnet_subnet_id" {
  type = "string"
}

variable "enable_virtual_node_addon" {
  type    = "string"
  default = "false"
}

variable "kubeconfig_to_disk" {
  type        = "string"
  description = "The disables or enables the kube config file from being written to disk"
  default     = "true"
}

variable "kubeconfig_recreate" {
  type        = "string"
  description = "Make any change to this value to trigger the recreation of the kube config file"
  default     = ""
}

variable "kubeconfig_filename" {
  type        = "string"
  description = "Name of the kube config file saved to disk"
  default     = "bedrock_kube_config"
}

variable "service_cidr" {
  type        = "string"
  description = "Used to assign internal services in the AKS cluster an IP address. This IP address range should be an address space that isn't in use elsewhere in your network environment. This includes any on-premises network ranges if you connect, or plan to connect, your azure virtual networks using Epress Route or a site-to-site VPN connections."
  default     = "10.0.0.0/16"
}

variable "dns_ip" {
  type        = "string"
  description = "Should be the .10 address of your service IP address range"
  default     = "10.0.0.10"
}

variable "docker_cidr" {
  type        = "string"
  description = "IP address (in CIDR notation) used as the docker bridge IP address on nodes. Default of 172.17.0.1/16"
  default     = "172.17.0.1/16"
}
