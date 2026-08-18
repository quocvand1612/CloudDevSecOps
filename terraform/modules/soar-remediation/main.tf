# ==============================================================================
# IAM Role for SOAR Lambda Remediation Function
# ==============================================================================
resource "aws_iam_role" "soar_lambda" {
  name = "${var.project_name}-${var.environment}-soar-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-soar-remediation"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

resource "aws_iam_policy" "soar_lambda" {
  name        = "${var.project_name}-${var.environment}-soar-lambda-policy"
  description = "Permissions for automated security incident quarantine and alerting"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LogsPermissions"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      },
      {
        Sid    = "SecurityQuarantineAction"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "XRayTelemetry"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "soar_lambda" {
  role       = aws_iam_role.soar_lambda.name
  policy_arn = aws_iam_policy.soar_lambda.arn
}

# ==============================================================================
# Lambda Function Archive (Python SOAR Responder)
# ==============================================================================
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/soar_handler.zip"

  source {
    content  = <<-PYTHON
import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    logger.info("Security Finding Received: %s", json.dumps(event))
    
    detail = event.get('detail', {})
    finding_type = detail.get('type', 'Custom-DevSecOps-Alert')
    severity = detail.get('severity', 0)
    resource = detail.get('resource', {})
    
    logger.warning(f"ALERT: High-Severity Finding [{finding_type}] detected! Severity={severity}")
    
    instance_id = resource.get('instanceDetails', {}).get('instanceId')
    if instance_id:
        logger.info(f"Applying automated quarantine tag to instance: {instance_id}")
        ec2.create_tags(
            Resources=[instance_id],
            Tags=[{'Key': 'SecurityStatus', 'Value': 'Quarantined-By-SOAR-Lambda'}]
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Security incident evaluated and quarantine applied.',
            'finding_type': finding_type
        })
    }
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "soar_remediation" {
  function_name                  = "${var.project_name}-${var.environment}-soar-remediation"
  description                    = "Automated incident response & pod/instance quarantine"
  runtime                        = "python3.11"
  handler                        = "lambda_function.lambda_handler"
  role                           = aws_iam_role.soar_lambda.arn
  filename                       = data.archive_file.lambda_zip.output_path
  source_code_hash               = data.archive_file.lambda_zip.output_base64sha256
  timeout                        = 30
  memory_size                    = 128
  kms_key_arn                    = var.kms_key_arn
  reserved_concurrent_executions = 5

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-soar-lambda"
      Environment = var.environment
      Role        = "Security-Automation"
    }
  )

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}

# ==============================================================================
# EventBridge Rule for Security Anomaly Detection
# ==============================================================================
resource "aws_cloudwatch_event_rule" "security_findings" {
  name        = "${var.project_name}-${var.environment}-security-rule"
  description = "Captures GuardDuty / SecurityHub / Falco anomaly findings"

  event_pattern = jsonencode({
    source = ["aws.guardduty", "custom.devsecops.falco"]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-security-rule"
    }
  )
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.security_findings.name
  target_id = "TriggerSOARLambda"
  arn       = aws_lambda_function.soar_remediation.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.soar_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_findings.arn
}
