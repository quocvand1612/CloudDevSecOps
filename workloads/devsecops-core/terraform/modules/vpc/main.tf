# ==============================================================================
# VPC Core (Multi-Tier Zero-Trust Architecture)
# ==============================================================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc"
      Environment = var.environment
      Tier        = "Network-Hub"
    }
  )
}

# ==============================================================================
# Internet Gateway
# ==============================================================================
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-igw"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# Subnet Tier 1: Public Ingress Tier (ALB & NAT)
# ==============================================================================
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false # Security best practice: Explicitly disable auto public IP

  tags = merge(
    var.tags,
    {
      Name                     = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
      Tier                     = "Public-Ingress"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

# ==============================================================================
# Subnet Tier 2: Private Compute Tier (Kubernetes Nodes / Pods)
# ==============================================================================
resource "aws_subnet" "private_compute" {
  count                   = length(var.private_compute_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_compute_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name                              = "${var.project_name}-${var.environment}-compute-${var.availability_zones[count.index]}"
      Tier                              = "Private-Compute"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

# ==============================================================================
# Subnet Tier 3: Isolated Data Tier (RDS, Redis - Strict Zero-Internet)
# ==============================================================================
resource "aws_subnet" "isolated_data" {
  count                   = length(var.isolated_data_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.isolated_data_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-data-${var.availability_zones[count.index]}"
      Tier = "Isolated-Data"
    }
  )
}

# ==============================================================================
# Route Tables & Associations
# ==============================================================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-public-rt"
      Tier = "Public"
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Compute Route Table (Egress via NAT instance / Gateway)
resource "aws_route_table" "private_compute" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-compute-rt"
      Tier = "Private-Compute"
    }
  )
}

resource "aws_route_table_association" "private_compute" {
  count          = length(aws_subnet.private_compute)
  subnet_id      = aws_subnet.private_compute[count.index].id
  route_table_id = aws_route_table.private_compute.id
}

# Isolated Data Route Table (Local VPC routing ONLY - ZERO internet routes)
resource "aws_route_table" "isolated_data" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-data-isolated-rt"
      Tier = "Isolated-Data"
    }
  )
}

resource "aws_route_table_association" "isolated_data" {
  count          = length(aws_subnet.isolated_data)
  subnet_id      = aws_subnet.isolated_data[count.index].id
  route_table_id = aws_route_table.isolated_data.id
}

# ==============================================================================
# S3 Gateway Endpoint ($0.00 Fixed Cost - Zero Latency Internal S3 Access)
# ==============================================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private_compute.id,
    aws_route_table.isolated_data.id
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-s3-gw-endpoint"
    }
  )
}

data "aws_region" "current" {}

# ==============================================================================
# VPC Flow Logs (Continuous Network Auditing with KMS Encryption)
# ==============================================================================
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.project_name}-${var.environment}-flow-logs"
  retention_in_days = 7
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-${var.environment}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCFlowLogsAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-${var.environment}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowFlowLogsPublish"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
