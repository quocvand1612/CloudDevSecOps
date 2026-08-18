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

  backend "s3" {
    bucket         = "cloud-devsecops-tfstate-033781183622-ap-southeast-1"
    key            = "lab/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "cloud-devsecops-tflocks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Security    = "ZeroTrust-eBPF"
      CostProfile = "Ultra-Low-Cost-Lab"
    }
  }
}

# CloudFront & WAF provider (Global / us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# Module 1: KMS Customer Managed Key (CMK)
# ==============================================================================
module "kms" {
  source       = "../../modules/kms"
  project_name = var.project_name
  environment  = var.environment
  description  = "CMK for ${var.project_name} ${var.environment} encryption"
}

# ==============================================================================
# Module 2: Multi-Tier Zero-Trust VPC
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
# Module 3: fck-nat (90% Cost Saving Egress Routing)
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
# Module 4: Least-Privilege Security Groups
# ==============================================================================
module "security_groups" {
  source       = "../../modules/security-groups"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  app_port     = 8080
}

# ==============================================================================
# Module 5: Secrets Manager (Encrypted with KMS CMK)
# ==============================================================================
module "secrets" {
  source       = "../../modules/secrets-manager"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.kms.key_arn
}

# ==============================================================================
# Module 6: CloudFront + AWS WAF + ALB Origin Token Verification
# ==============================================================================
module "edge_ingress" {
  source                = "../../modules/cloudfront-waf"
  project_name          = var.project_name
  environment           = var.environment
  enable_cloudfront     = var.enable_cloudfront
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
# Module 7: Hardened Low-Cost Kubernetes Compute Node (Spot Graviton)
# ==============================================================================
module "compute_node" {
  source                    = "../../modules/k3s-lab-node"
  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_id         = module.vpc.private_compute_subnet_ids[0]
  compute_security_group_id = module.security_groups.compute_security_group_id
  alb_target_group_arn      = module.edge_ingress.alb_target_group_arn
  kms_key_arn               = module.kms.key_arn
  secret_arn                = module.secrets.secret_arn
  use_spot                  = var.use_spot_instance
}

# ==============================================================================
# Module 8: Isolated RDS PostgreSQL (Free Tier Eligible)
# ==============================================================================
module "database" {
  source                     = "../../modules/rds-postgres"
  project_name               = var.project_name
  environment                = var.environment
  isolated_subnet_ids        = module.vpc.isolated_data_subnet_ids
  database_security_group_id = module.security_groups.database_security_group_id
  kms_key_arn                = module.kms.key_arn
  instance_class             = "db.t4g.micro"
  multi_az                   = false
  deletion_protection        = false
}

# ==============================================================================
# Module 9: SOAR Automated Incident Remediation (EventBridge + Lambda)
# ==============================================================================
module "soar" {
  source       = "../../modules/soar-remediation"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.kms.key_arn
}
