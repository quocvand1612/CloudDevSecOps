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

variable "vpc_id" {
  type        = string
  description = "VPC ID where runner instances will be deployed"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the ASG"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-southeast-1"
}

variable "github_org" {
  type        = string
  description = "GitHub Organization or username"
  default     = "QuocVanD-DevSecOpsLab"
}

variable "token_secret_name" {
  type        = string
  description = "AWS Secrets Manager secret name holding the runner registration token"
  default     = "github-runner-registration-token"
}

variable "runner_labels" {
  type        = string
  description = "Comma-separated labels to assign to runner"
  default     = "self-hosted,aws-spot,linux,x64"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for runner"
  default     = "t3.medium"
}

variable "architecture" {
  type        = string
  description = "Architecture: amd64 or arm64"
  default     = "amd64"
}

variable "use_golden_image" {
  type        = bool
  description = "Use a self-baked runner AMI when one is available; false keeps the Canonical Ubuntu fallback."
  default     = false
}

variable "disk_size_gb" {
  type        = number
  description = "Root EBS disk size in GB"
  default     = 30
}

variable "kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for EBS encryption"
  default     = ""
}

variable "max_runners" {
  type        = number
  description = "Maximum number of simultaneous runners"
  default     = 5
}
