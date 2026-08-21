variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "isolated_subnet_ids" {
  type        = list(string)
  description = "List of isolated subnet IDs for DB subnet group"
}

variable "database_security_group_id" {
  type        = string
  description = "Security group ID allowing port 5432 from compute nodes"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS CMK ARN for storage encryption"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (db.t4g.micro is Free Tier eligible)"
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage in GB"
  default     = 20
}

variable "database_name" {
  type        = string
  description = "Initial database name"
  default     = "devsecopsdb"
}

variable "admin_username" {
  type        = string
  description = "Database administrator username"
  default     = "dbadmin"
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ replication (false for low-cost lab, true for prod)"
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
