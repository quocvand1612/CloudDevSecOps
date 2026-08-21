variable "project_name" {
  type        = string
  description = "Project identifier"
  default     = "cloud-devsecops"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "runners-mgmt"
}

variable "asg_name" {
  type        = string
  description = "Name of the target Auto Scaling Group to scale"
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
  default     = "self-hosted,aws-spot"
}
