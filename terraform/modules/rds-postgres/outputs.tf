output "endpoint" {
  description = "Database connection endpoint (hostname:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "address" {
  description = "Database hostname address"
  value       = aws_db_instance.postgres.address
}

output "port" {
  description = "Database listening port"
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.postgres.db_name
}

output "admin_username" {
  description = "Administrator username"
  value       = aws_db_instance.postgres.username
}

output "master_password" {
  description = "Generated master password"
  value       = random_password.master_password.result
  sensitive   = true
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.postgres.arn
}
