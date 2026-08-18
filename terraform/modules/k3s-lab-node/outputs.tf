output "instance_id" {
  description = "ID of the Kubernetes compute node instance"
  value       = aws_instance.node.id
}

output "private_ip" {
  description = "Private IP address of the compute node"
  value       = aws_instance.node.private_ip
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the compute node"
  value       = aws_iam_role.node.arn
}
