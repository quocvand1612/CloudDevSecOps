output "github_oidc_role_arn" {
  value       = module.oidc.github_actions_role_arn
  description = "IAM Role ARN for GitHub Actions workflows"
}

output "webhook_endpoint_url" {
  value       = module.webhook_scaler.webhook_url
  description = "API Gateway Webhook URL to add to GitHub Org Webhooks"
}

output "asg_name" {
  value       = module.asg_runner.asg_name
  description = "Auto Scaling Group Name"
}

output "secretsmanager_token_name" {
  value       = aws_secretsmanager_secret.runner_token.name
  description = "Secrets Manager secret name where runner token should be stored"
}
