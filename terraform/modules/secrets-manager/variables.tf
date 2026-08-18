variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "secret_name" {
  type        = string
  description = "Name identifier for the secret"
  default     = "app-secrets"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN used for encrypting the secret"
}

variable "initial_secret_values" {
  type        = map(string)
  description = "Optional custom secret key-value pairs (if omitted, high-entropy random secrets are dynamically generated)"
  default     = {}
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
