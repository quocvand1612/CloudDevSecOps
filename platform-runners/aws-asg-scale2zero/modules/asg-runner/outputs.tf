output "asg_name" {
  value       = aws_autoscaling_group.runner_asg.name
  description = "Name of the Runner Auto Scaling Group"
}

output "asg_arn" {
  value       = aws_autoscaling_group.runner_asg.arn
  description = "ARN of the Runner Auto Scaling Group"
}

output "security_group_id" {
  value       = aws_security_group.runner_sg.id
  description = "Security group ID attached to runner instances"
}
