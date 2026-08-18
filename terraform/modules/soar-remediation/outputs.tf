output "lambda_function_arn" {
  description = "ARN of the SOAR remediation Lambda function"
  value       = aws_lambda_function.soar_remediation.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge security rule"
  value       = aws_cloudwatch_event_rule.security_findings.arn
}
