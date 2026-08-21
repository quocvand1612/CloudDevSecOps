variable "project_name" {
  type        = string
  description = "Project identifier"
  default     = "cloud-devsecops"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. runners-mgmt, prod)"
  default     = "runners-mgmt"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization or User name for OIDC subject claim scoping"
  default     = "QuocVanD-DevSecOpsLab"
}

variable "create_oidc_provider" {
  type        = bool
  description = "Whether to create the AWS IAM OIDC Provider for GitHub Actions"
  default     = false
}

variable "existing_oidc_provider_arn" {
  type        = string
  description = "Existing GitHub OIDC Provider ARN if create_oidc_provider is false"
  default     = ""
}
