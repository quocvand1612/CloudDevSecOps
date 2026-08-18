variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_id" {
  type        = string
  description = "Private compute subnet ID where node is placed"
}

variable "compute_security_group_id" {
  type        = string
  description = "Security group ID for compute nodes"
}

variable "alb_target_group_arn" {
  type        = string
  description = "Target group ARN to attach the compute instance to"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for EBS storage encryption"
}

variable "secret_arn" {
  type        = string
  description = "Secrets Manager ARN allowed to be read by instance IAM profile"
}

variable "instance_type" {
  type        = string
  description = "EC2 Instance type (t4g.small or t4g.medium recommended)"
  default     = "t4g.small"
}

variable "use_spot" {
  type        = bool
  description = "Deploy as Spot instance for ultra-low cost (saves ~70%)"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
