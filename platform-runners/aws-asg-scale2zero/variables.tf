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

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-southeast-1"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization name"
  default     = "QuocVanD-DevSecOpsLab"
}

variable "create_oidc_provider" {
  type        = bool
  description = "Whether to create IAM OIDC provider or use existing in AWS account"
  default     = false
}

variable "github_webhook_secret" {
  type        = string
  description = "Secret used to sign GitHub webhook payloads"
  sensitive   = true

  validation {
    condition     = length(var.github_webhook_secret) >= 32
    error_message = "github_webhook_secret must be at least 32 characters and match the GitHub webhook configuration."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 Spot instance type"
  default     = "t3.medium"
}

variable "max_runners" {
  type        = number
  description = "Max number of parallel runner instances"
  default     = 5
}

variable "use_golden_image" {
  type        = bool
  description = "Use the newest self-baked runner AMI when available"
  default     = false
}
