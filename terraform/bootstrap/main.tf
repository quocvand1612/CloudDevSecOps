terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "bootstrap"
      ManagedBy   = "Terraform"
      Security    = "ZeroTrust-OIDC"
      Owner       = var.github_org
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ==============================================================================
# 1. KMS Customer Managed Key (CMK) for Terraform State & Artifacts
# ==============================================================================
resource "aws_kms_key" "terraform_state" {
  description             = "KMS CMK for Terraform remote state and artifact encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowGitHubActionsOIDCRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.github_actions.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ==============================================================================
# 2. S3 Remote State Bucket (Hardened with KMS, Versioning, TLS 1.2 Enforced)
# ==============================================================================
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "enforce_tls_only" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# 3. DynamoDB State Lock Table
# ==============================================================================
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-tflocks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }
}

# ==============================================================================
# 4. GitHub Actions OIDC Identity Provider (Keyless & Tokenless CI/CD)
# ==============================================================================
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = distinct(concat(
    [for cert in data.tls_certificate.github_actions.certificates : cert.sha1_fingerprint],
    ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c5876a972c729e8c39e31d4f0d3674681647414"]
  ))
}

# ==============================================================================
# 5. GitHub Actions CI/CD IAM Role with Scoped Repository Trust Policy
# ==============================================================================
resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-role"
  description = "Role assumed via OIDC by GitHub Actions CI/CD runners (Tokenless/Keyless)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubActionsOIDCAssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_org}/${var.github_repo}:*",
              "repo:${var.github_org}/cloudseclab-aws:*",
              "repo:${var.github_org}/*"
            ]
          }
        }
      }
    ]
  })
}

# Policy for Terraform State Management & General Deployments
resource "aws_iam_policy" "github_actions_policy" {
  name        = "${var.project_name}-github-actions-policy"
  description = "Permissions required for GitHub Actions to execute Terraform and DevSecOps pipelines"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "TerraformLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
      {
        Sid    = "InfrastructureProvisioning"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "vpc:*",
          "kms:*",
          "iam:*",
          "eks:*",
          "rds:*",
          "cloudfront:*",
          "wafv2:*",
          "secretsmanager:*",
          "events:*",
          "lambda:*",
          "logs:*",
          "cloudwatch:*",
          "ssm:*",
          "budgets:*",
          "sns:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_attach" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

# ==============================================================================
# 6. AWS Budget Guardrail ($10/month Lab Cost Protection)
# ==============================================================================
resource "aws_sns_topic" "budget_alerts" {
  name              = "${var.project_name}-budget-alerts"
  kms_master_key_id = aws_kms_key.terraform_state.id
}

resource "aws_sns_topic_subscription" "budget_email" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.budget_alert_email
}

resource "aws_budgets_budget" "monthly_cost_guardrail" {
  name              = "${var.project_name}-monthly-cost-guardrail"
  budget_type       = "COST"
  limit_amount      = tostring(var.monthly_budget_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}
