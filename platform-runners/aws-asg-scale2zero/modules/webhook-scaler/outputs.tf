output "webhook_url" {
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/webhook"
  description = "The public Webhook URL to configure in GitHub Organization Webhooks"
}

output "lambda_function_name" {
  value       = aws_lambda_function.scaler.function_name
  description = "The Lambda scaler function name"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.scaler.arn
  description = "The Lambda scaler function ARN"
}
