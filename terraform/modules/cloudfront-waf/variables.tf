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
  description = "VPC ID for ALB target group"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for ALB deployment"
}

variable "alb_security_group_id" {
  type        = string
  description = "Security group ID for Public ALB"
}

variable "app_port" {
  type        = number
  description = "Application backend target port"
  default     = 8080
}

variable "origin_verify_token" {
  type        = string
  description = "Secret token header validated between CloudFront and ALB (X-Origin-Verify)"
  default     = "ZeroTrustOriginVerificationToken2026SecOps"
  sensitive   = true
}

variable "trusted_corporate_cidrs" {
  type        = list(string)
  description = "Whitelisted corporate egress/office IP prefixes for priority ingress access"
  default = [
    "103.111.244.0/22"
  ]
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
