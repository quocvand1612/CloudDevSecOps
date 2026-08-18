variable "aws_region" {
  type        = string
  description = "AWS region for lab deployment"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
  default     = "cloud-devsecops"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "lab"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the Lab VPC"
  default     = "10.0.0.0/16"
}

variable "origin_verify_token" {
  type        = string
  description = "Origin verification token (X-Origin-Verify). If null, dynamically generated with high entropy."
  default     = null
  sensitive   = true
}

variable "use_spot_instance" {
  type        = bool
  description = "Use EC2 Spot instances for ~70% cost reduction"
  default     = true
}

variable "enable_cloudfront" {
  type        = bool
  description = "Enable CloudFront CDN distribution and Global WAF (requires verified account in AWS)"
  default     = false
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "Allowed public CIDR blocks permitted to access public endpoints"
  default = [
    "103.111.244.0/22",
    "103.111.245.228/32"
  ]
}
