output "cluster_id" {
  description = "The name / ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "The endpoint for your EKS Kubernetes API"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with your cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IAM Roles for Service Accounts (IRSA)"
  value       = aws_iam_openid_connect_provider.eks.arn
}
