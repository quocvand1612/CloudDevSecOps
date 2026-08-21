output "cloudfront_url" {
  description = "Production Entry Point URL (CloudFront CDN or Direct ALB)"
  value       = module.edge_ingress.cloudfront_domain_name != null ? "https://${module.edge_ingress.cloudfront_domain_name}" : "http://${module.edge_ingress.alb_dns_name}"
}

output "eks_cluster_endpoint" {
  description = "EKS Control Plane Endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "OIDC Provider ARN for IRSA / Pod Identity"
  value       = module.eks.oidc_provider_arn
}

output "database_endpoint" {
  description = "Multi-AZ PostgreSQL endpoint"
  value       = module.database.endpoint
}
