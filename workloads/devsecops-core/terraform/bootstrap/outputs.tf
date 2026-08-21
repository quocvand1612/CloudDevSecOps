output "terraform_state_s3_bucket" {
  description = "Name of the S3 bucket storing Terraform remote state"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_locks_dynamodb_table" {
  description = "Name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "kms_cmk_arn" {
  description = "ARN of the KMS Customer Managed Key for encryption"
  value       = aws_kms_key.terraform_state.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM Role assumed by GitHub Actions via OIDC (Tokenless/Keyless)"
  value       = aws_iam_role.github_actions.arn
}

output "aws_region" {
  description = "AWS Region configured for bootstrap"
  value       = var.aws_region
}
