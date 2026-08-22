terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket       = "cloud-devsecops-tfstate-033781183622-ap-southeast-1"
    key          = "platform-runners/aws/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Role        = "GitHub-Actions-Runner-Platform"
      CostProfile = "Scale-to-Zero-Spot"
    }
  }
}

# 1. AWS IAM OIDC Provider & GitHub Actions Role
module "oidc" {
  source               = "./modules/oidc"
  project_name         = var.project_name
  environment          = var.environment
  github_org           = var.github_org
  create_oidc_provider = var.create_oidc_provider
}

# 2. Secrets Manager for GitHub Runner Token
resource "aws_secretsmanager_secret" "runner_token" {
  name                    = "${var.project_name}-${var.environment}-runner-token"
  description             = "GitHub Actions Runner registration token or GitHub App private key for ${var.github_org}"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.project_name}-runner-token"
    Environment = var.environment
  }
}

# Default VPC & Subnets data sources (or custom VPC)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 3. Scale-to-Zero Spot Auto Scaling Group
module "asg_runner" {
  source            = "./modules/asg-runner"
  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  vpc_id            = data.aws_vpc.default.id
  subnet_ids        = data.aws_subnets.default.ids
  github_org        = "${var.github_org}/platform-runners"
  token_secret_name = aws_secretsmanager_secret.runner_token.name
  runner_labels     = "self-hosted,aws-spot,linux,x64"
  instance_type     = var.instance_type
  max_runners       = var.max_runners
  use_golden_image  = var.use_golden_image
}

# 4. Webhook Scaler (Lambda + API Gateway)
module "webhook_scaler" {
  source         = "./modules/webhook-scaler"
  project_name   = var.project_name
  environment    = var.environment
  asg_name       = module.asg_runner.asg_name
  webhook_secret = var.github_webhook_secret
  runner_labels  = "self-hosted,aws-spot"
}
