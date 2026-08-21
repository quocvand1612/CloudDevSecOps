resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.project_name}/${var.environment}/${var.secret_name}"
  description             = "Application secrets for ${var.project_name} in ${var.environment}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0 # Immediate deletion upon terraform destroy

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-${var.secret_name}"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Security    = "ZeroHardcodedSecrets"
    }
  )
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode(length(var.initial_secret_values) > 0 ? var.initial_secret_values : {
    DATABASE_USER     = "db_admin_sec"
    DATABASE_PASSWORD = random_password.db_password.result
    JWT_SECRET_KEY    = random_password.jwt_secret.result
    API_KEY           = random_password.api_key.result
  })
}
