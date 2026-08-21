variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Environment identifier (e.g. lab, prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to deploy subnets into"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public ingress subnets (2 AZs)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_compute_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private compute subnets (2 AZs)"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "isolated_data_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for isolated data subnets (2 AZs)"
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for VPC Flow Logs CloudWatch encryption"
}

variable "tags" {
  type        = map(string)
  description = "Additional resource tags"
  default     = {}
}
