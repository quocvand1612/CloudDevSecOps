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

variable "github_org" {
  type        = string
  description = "GitHub Organization or username"
  default     = "QuocVanD-DevSecOpsLab"
}

variable "subscription_scope" {
  type        = string
  description = "Target Azure Subscription resource ID for Contributor role assignment"
}

variable "owner_object_id" {
  type        = string
  description = "Object ID of Entra ID admin owner"
  default     = ""
}
