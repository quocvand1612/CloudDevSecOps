# ==============================================================================
# Random Password Generation for Master DB User
# ==============================================================================
resource "random_password" "master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ==============================================================================
# DB Subnet Group (Isolated Subnets - No Internet Routing)
# ==============================================================================
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Isolated database subnet group for ${var.project_name}"
  subnet_ids  = var.isolated_subnet_ids

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-db-subnet-group"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# RDS PostgreSQL Instance (Encrypted with KMS CMK, Private Only)
# ==============================================================================
resource "aws_db_instance" "postgres" {
  identifier                          = "${var.project_name}-${var.environment}-postgres"
  engine                              = "postgres"
  engine_version                      = "16.3"
  instance_class                      = var.instance_class
  allocated_storage                   = var.allocated_storage
  max_allocated_storage               = var.allocated_storage * 2
  storage_type                        = "gp3"
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  publicly_accessible                 = false
  multi_az                            = var.multi_az
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [var.database_security_group_id]
  db_name                             = var.database_name
  username                            = var.admin_username
  password                            = random_password.master_password.result
  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = false
  skip_final_snapshot                 = true
  deletion_protection                 = var.deletion_protection
  copy_tags_to_snapshot               = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-postgres"
      Environment = var.environment
      Tier        = "Isolated-Data"
      Security    = "KMS-Encrypted-Private"
    }
  )
}
