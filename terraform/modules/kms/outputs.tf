output "key_arn" {
  description = "The ARN of the KMS Customer Managed Key"
  value       = aws_kms_key.primary.arn
}

output "key_id" {
  description = "The globally unique identifier for the key"
  value       = aws_kms_key.primary.key_id
}

output "alias_name" {
  description = "The display name of the alias"
  value       = aws_kms_alias.primary.name
}

output "alias_arn" {
  description = "The ARN of the key alias"
  value       = aws_kms_alias.primary.arn
}
