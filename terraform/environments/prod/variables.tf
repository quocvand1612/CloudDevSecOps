variable "aws_region" {
  type        = string
  description = "AWS region for production deployment"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
  default     = "cloud-devsecops"
}

variable "environment" {
  type        = string
  description = "Environment identifier"
  default     = "prod"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the Production Workload VPC"
  default     = "10.0.0.0/16"
}

variable "origin_verify_token" {
  type        = string
  description = "Cryptographic secret token shared between CloudFront and ALB (X-Origin-Verify)"
  default     = "ZeroTrustOriginVerificationToken2026SecOpsProd"
  sensitive   = true
}
