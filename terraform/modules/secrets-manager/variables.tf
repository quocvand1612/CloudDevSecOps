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
  description = "Initial secret key-value pairs (placeholder/bootstrap)"
  default = {
    DATABASE_USER     = "db_admin_sec"
    DATABASE_PASSWORD = "ChangeMePromptlyViaSecretsManagerRotation123!"
    JWT_SECRET_KEY    = "DevSecOpsZeroTrustSecretKey2026SignatureValidation"
    API_KEY           = "devsecops-live-lab-api-key-tokenless"
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
