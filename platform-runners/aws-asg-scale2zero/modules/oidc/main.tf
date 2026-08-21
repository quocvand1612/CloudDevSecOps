# ==============================================================================
# AWS IAM OIDC Provider & GitHub Actions Role
# ==============================================================================

data "aws_caller_identity" "current" {}

# Fetch GitHub OIDC thumbprint dynamically if creating provider
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# AWS only allows 1 OIDC Provider per URL per AWS Account.
# If provider already exists in the account, create_oidc_provider should be false.
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "${var.project_name}-github-oidc"
    Environment = var.environment
  }
}

locals {
  # Deterministic OIDC ARN for GitHub in the current AWS account
  account_oidc_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (var.existing_oidc_provider_arn != "" ? var.existing_oidc_provider_arn : local.account_oidc_arn)
}

# Trust policy for GitHub Actions
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/*"]
    }
  }
}

# IAM Role assumed by GitHub Actions Workflows
resource "aws_iam_role" "github_actions" {
  name                 = "${var.project_name}-${var.environment}-github-actions-role"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600

  tags = {
    Name        = "${var.project_name}-github-actions-role"
    Environment = var.environment
  }
}

# Allow GitHub Actions to interact with AWS resources securely
resource "aws_iam_role_policy" "github_actions_policy" {
  name = "${var.project_name}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudOperations"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "autoscaling:Describe*",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "*"
      }
    ]
  })
}
