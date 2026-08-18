output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_secrets.name
}
