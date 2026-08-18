terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Security    = "ZeroTrust-Bottlerocket-eBPF"
      Tier        = "Enterprise-Production"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# KMS Customer Managed Key
# ==============================================================================
module "kms" {
  source       = "../../modules/kms"
  project_name = var.project_name
  environment  = var.environment
  description  = "CMK for Production Enterprise encryption"
}

# ==============================================================================
# Multi-Tier VPC
# ==============================================================================
module "vpc" {
  source             = "../../modules/vpc"
  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  kms_key_arn        = module.kms.key_arn
}

# ==============================================================================
# HA fck-nat Gateway
# ==============================================================================
module "fck_nat" {
  source                 = "../../modules/fck-nat"
  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.vpc_cidr_block
  public_subnet_id       = module.vpc.public_subnet_ids[0]
  private_route_table_id = module.vpc.private_compute_route_table_id
  kms_key_arn            = module.kms.key_arn
}

# ==============================================================================
# Security Groups
# ==============================================================================
module "security_groups" {
  source       = "../../modules/security-groups"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  app_port     = 8080
}

# ==============================================================================
# Secrets Manager
# ==============================================================================
module "secrets" {
  source       = "../../modules/secrets-manager"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.kms.key_arn
}

# ==============================================================================
# CloudFront + WAF + ALB Origin Token
# ==============================================================================
module "edge_ingress" {
  source                = "../../modules/cloudfront-waf"
  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  app_port              = 8080
  origin_verify_token   = var.origin_verify_token

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# ==============================================================================
# Production EKS Cluster (Bottlerocket OS + Envelope KMS Encryption)
# ==============================================================================
module "eks" {
  source              = "../../modules/eks-enterprise"
  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_compute_subnet_ids
  kms_key_arn         = module.kms.key_arn
  node_instance_types = ["t4g.medium"]
  desired_size        = 2
  min_size            = 2
  max_size            = 4
}

# ==============================================================================
# Multi-AZ PostgreSQL Database
# ==============================================================================
module "database" {
  source                     = "../../modules/rds-postgres"
  project_name               = var.project_name
  environment                = var.environment
  isolated_subnet_ids        = module.vpc.isolated_data_subnet_ids
  database_security_group_id = module.security_groups.database_security_group_id
  kms_key_arn                = module.kms.key_arn
  instance_class             = "db.t4g.medium"
  multi_az                   = true
  deletion_protection        = true
}

# ==============================================================================
# SOAR Automated Remediation
# ==============================================================================
module "soar" {
  source       = "../../modules/soar-remediation"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.kms.key_arn
}
