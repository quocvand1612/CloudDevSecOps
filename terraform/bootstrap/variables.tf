variable "aws_region" {
  type        = string
  description = "AWS region for provisioning bootstrap resources"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
  default     = "cloud-devsecops"
}

variable "github_org" {
  type        = string
  description = "GitHub username or organization owning the repository"
  default     = "quocvand1612"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name (or * for all repos in org)"
  default     = "CloudDevSecOps"
}

variable "monthly_budget_usd" {
  type        = number
  description = "Monthly cost guardrail budget in USD"
  default     = 10.00
}

variable "budget_alert_email" {
  type        = string
  description = "Email address for AWS Budget limit alerts"
  default     = "quocvand1612@example.com"
}
