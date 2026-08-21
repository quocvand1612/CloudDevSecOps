output "oidc_provider_arn" {
  value       = local.oidc_provider_arn
  description = "The ARN of the GitHub OIDC Provider in AWS IAM"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "The IAM Role ARN for GitHub Actions workflows to assume"
}
