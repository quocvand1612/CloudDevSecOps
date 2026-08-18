output "alb_security_group_id" {
  description = "Security group ID for Public Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "compute_security_group_id" {
  description = "Security group ID for Kubernetes Compute Nodes"
  value       = aws_security_group.compute.id
}

output "database_security_group_id" {
  description = "Security group ID for Database Tier"
  value       = aws_security_group.database.id
}
