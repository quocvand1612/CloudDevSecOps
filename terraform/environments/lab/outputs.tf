output "cloudfront_url" {
  description = "Secure Public Entry Point URL via CloudFront CDN"
  value       = "https://${module.edge_ingress.cloudfront_domain_name}"
}

output "alb_direct_url_blocked" {
  description = "Direct ALB URL (Access is blocked with 403 Forbidden by Zero Trust origin policy)"
  value       = "http://${module.edge_ingress.alb_dns_name}"
}

output "fck_nat_public_ip" {
  description = "Egress Public IP assigned to fck-nat proxy"
  value       = module.fck_nat.public_ip
}

output "database_endpoint" {
  description = "Private RDS PostgreSQL endpoint (Accessible only within Private Compute subnet)"
  value       = module.database.endpoint
}

output "kms_cmk_arn" {
  description = "KMS Customer Managed Key ARN used for all resource encryption"
  value       = module.kms.key_arn
}

output "secrets_manager_arn" {
  description = "Secrets Manager Secret ARN synced via IAM without static credentials"
  value       = module.secrets.secret_arn
}
