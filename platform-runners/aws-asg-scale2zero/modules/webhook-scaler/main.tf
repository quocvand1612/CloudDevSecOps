# ==============================================================================
# AWS Webhook Scaler Lambda + API Gateway (Scale-to-Zero Controller)
# ==============================================================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/scaler.py"
  output_path = "${path.module}/lambda/scaler.zip"
}

# IAM Role for Lambda Scaler
resource "aws_iam_role" "lambda_scaler" {
  name = "${var.project_name}-${var.environment}-webhook-scaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-webhook-scaler-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "lambda_scaler_policy" {
  name = "${var.project_name}-webhook-scaler-policy"
  role = aws_iam_role.lambda_scaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "ManageASGCapacity"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:SetDesiredCapacity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "scaler" {
  function_name    = "${var.project_name}-${var.environment}-webhook-scaler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_scaler.arn
  handler          = "scaler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ASG_NAME       = var.asg_name
      WEBHOOK_SECRET = var.webhook_secret
      RUNNER_LABELS  = var.runner_labels
    }
  }

  tags = {
    Name        = "${var.project_name}-webhook-scaler"
    Environment = var.environment
  }
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "webhook_api" {
  name          = "${var.project_name}-${var.environment}-runner-webhook-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.project_name}-runner-webhook-api"
    Environment = var.environment
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.webhook_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.scaler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook_route" {
  api_id    = aws_apigatewayv2_api.webhook_api.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook_api.execution_arn}/*/*"
}
