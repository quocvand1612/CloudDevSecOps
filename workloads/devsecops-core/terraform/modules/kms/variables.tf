variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. lab, prod)"
}

variable "description" {
  type        = string
  description = "Description for the KMS Customer Managed Key"
  default     = "DevSecOps KMS Customer Managed Key"
}

variable "deletion_window_in_days" {
  type        = number
  description = "Duration in days after which the key is deleted upon destruction"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for the KMS key"
  default     = {}
}
