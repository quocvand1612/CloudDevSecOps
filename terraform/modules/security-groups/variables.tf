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
  description = "VPC ID for security group associations"
}

variable "app_port" {
  type        = number
  description = "Application listening port on compute nodes"
  default     = 8080
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "Allowed public CIDR blocks permitted to access the ALB"
  default = [
    "103.111.244.0/22",
    "103.111.245.228/32"
  ]
}

variable "tags" {
  type        = map(string)
  description = "Additional resource tags"
  default     = {}
}
