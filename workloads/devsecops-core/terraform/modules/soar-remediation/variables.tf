variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for encrypting Lambda environment and logs"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
