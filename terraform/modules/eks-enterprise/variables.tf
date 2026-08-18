variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes Version"
  default     = "1.30"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private compute subnet IDs for EKS worker nodes"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for EKS envelope secret encryption and CloudWatch logs"
}

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for Bottlerocket node group"
  default     = ["t4g.medium"]
}

variable "desired_size" {
  type        = number
  description = "Desired number of worker nodes"
  default     = 2
}

variable "min_size" {
  type        = number
  description = "Minimum number of worker nodes"
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Maximum number of worker nodes"
  default     = 4
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
