resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.project_name}/${var.environment}/${var.secret_name}"
  description             = "Application secrets for ${var.project_name} in ${var.environment}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0 # Lab cleanup friendly

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-${var.secret_name}"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode(var.initial_secret_values)
}
