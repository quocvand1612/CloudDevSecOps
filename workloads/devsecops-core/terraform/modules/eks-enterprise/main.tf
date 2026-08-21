# ==============================================================================
# EKS Cluster IAM Role
# ==============================================================================
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSClusterAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "vpc_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ==============================================================================
# CloudWatch Log Group for EKS Audit & Authenticator Logs
# ==============================================================================
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-${var.environment}-cluster/cluster"
  retention_in_days = 7
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

# ==============================================================================
# EKS Cluster (Bottlerocket, KMS Envelope Encryption, Full Auditing)
# ==============================================================================
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true # Set to false in air-gapped environments
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  # Hardened KMS Envelope Encryption for Kubernetes Secrets
  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_controller,
    aws_cloudwatch_log_group.eks
  ]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eks"
      Environment = var.environment
      Security    = "Envelope-Encrypted"
    }
  )
}

# ==============================================================================
# OIDC Provider for EKS (IRSA - IAM Roles for Service Accounts)
# ==============================================================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ==============================================================================
# EKS Worker Node IAM Role
# ==============================================================================
resource "aws_iam_role" "node" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSNodeAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_registry" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ==============================================================================
# Hardened Bottlerocket Managed Node Group
# ==============================================================================
resource "aws_eks_node_group" "bottlerocket_nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-bottlerocket-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = "BOTTLEROCKET_ARM_64"
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-bottlerocket-node"
      Environment = var.environment
      OS          = "Bottlerocket-Hardened"
    }
  )
}
