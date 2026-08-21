variable "project_name" {
  type        = string
  description = "Project identifier"
  default     = "devsecops-runners"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "mgmt"
}

variable "location" {
  type        = string
  description = "Azure Region (East US with high capacity)"
  default     = "eastus"
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
  default     = "7d3746c5-7456-498a-b9ea-088c845d696d"
}

variable "tenant_id" {
  type        = string
  description = "Azure Entra ID Tenant ID"
  default     = "fdf0b2be-d187-4753-92db-b35388d55676"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization name"
  default     = "QuocVanD-DevSecOpsLab"
}

variable "github_runner_token" {
  type        = string
  description = "GitHub Runner registration token"
  default     = ""
  sensitive   = true
}

variable "github_webhook_secret" {
  type        = string
  description = "GitHub Webhook HMAC SHA256 secret"
  default     = ""
  sensitive   = true
}

variable "vm_sku" {
  type        = string
  description = "Azure VM SKU for Ephemeral runners (Standard_D2als_v7 in eastus)"
  default     = "Standard_D2als_v7"
}
