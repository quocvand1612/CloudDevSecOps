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
  description = "Azure region"
  default     = "southeastasia"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "vmss_name" {
  type        = string
  description = "VMSS name to scale"
}

variable "webhook_secret" {
  type        = string
  description = "GitHub Webhook HMAC SHA256 secret"
  default     = ""
  sensitive   = true
}

variable "runner_labels" {
  type        = string
  description = "Comma-separated labels to match against workflow jobs"
  default     = "self-hosted,azure-spot"
}
