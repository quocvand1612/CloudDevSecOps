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
  description = "VPC ID where fck-nat is deployed"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block allowed to route traffic through fck-nat"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID for fck-nat deployment"
}

variable "private_route_table_id" {
  type        = string
  description = "Route table ID for private subnets that need outbound NAT routing"
}

variable "instance_type" {
  type        = string
  description = "Instance type for fck-nat (t4g.nano or t4g.micro recommended)"
  default     = "t4g.nano"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for EBS volume encryption"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
