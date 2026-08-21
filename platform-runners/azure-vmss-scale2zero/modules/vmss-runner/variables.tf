variable "project_name" {
  type        = string
  description = "Project identifier"
  default     = "cloud-devsecops"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "mgmt"
}

variable "location" {
  type        = string
  description = "Azure Region (e.g. eastus)"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the runner VNet"
  default     = "10.100.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the runner subnet"
  default     = "10.100.1.0/24"
}

variable "vm_sku" {
  type        = string
  description = "VM SKU for Ephemeral instances"
  default     = "Standard_D2als_v7"
}

variable "disk_size_gb" {
  type        = number
  description = "OS Disk size in GB"
  default     = 30
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key for admin user"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization or username"
  default     = "QuocVanD-DevSecOpsLab"
}

variable "runner_labels" {
  type        = string
  description = "Comma-separated labels for runner"
  default     = "self-hosted,azure-spot,linux,x64"
}

variable "key_vault_name" {
  type        = string
  description = "Key Vault name holding the runner token"
}

variable "key_vault_secret_name" {
  type        = string
  description = "Secret name in Key Vault"
  default     = "github-runner-token"
}
