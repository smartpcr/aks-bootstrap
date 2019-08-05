variable "flux_repo_url" {
  type = "string"
  default = "ttps://github.com/weaveworks/flux.git"
}

variable "gitops_path" {
  type = "string"
}

variable "gitops_poll_interval" {
  type = "string"
  default = "5m"
}

variable "gitops_ssh_url" {
  type = "string"
  description = "ssh git clone repository url with kubernetes manifests including services which runs in the cluster. Flux monitors this repo for kubernetes manifest additions/changes preriodically and apply them in the cluster"
}

variable "gitops_url_branch" {
  type = "string"
  description = "Git branch associated with the gitops_ssh_url where flux checks for the raw kubernetes yaml files to deploy to the cluster"
  default = "master"
}

variable "acr_enabled" {
  type = "string"
  default = "true"
}

# generate a SSH key named identity: ssh-keygen -q -N "" -f ./identity
# or use existing ssh public/private key pair
# add deploy key in gitops repo using public key with read/write access
# assign/specify private key to "gitops_ssh_key" variable that will be used to cretae kubernetes secret object
# flux use this key to read manifests in the git repo
variable "gitops_ssh_key" {
  type = "string"
}

variable "output_directory" {
  type = "string"
  default = "./output"
}

variable "enable_flux" {
  type = "string"
  default = "true"
}

variable "kubeconfig_filename" {
  type = "string"
  description = "name of kube config file saved to disk"
  default = "bedrock_kube_config"
}


variable "flux_recreate" {
    description = "Make any change to this value to trigger the recreation of the flux execution script."
    type = "string"
    default = ""
}

variable "kubeconfig_complete" {
    description = "Allows flux to wait for the kubeconfig completion write to disk. Workaround for the fact that modules themselves cannot have dependencies."
    type = "string"
}

variable "flux_clone_dir" {
    description = "Name of the directory to clone flux repo and deploy in the cluster."
    type = "string"
}
