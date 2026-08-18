# ==============================================================================
# Security Group 1: Public ALB (Ingress Tier)
# ==============================================================================
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for Public Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTPS from CloudFront / External clients"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP for redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-alb-sg"
      Tier = "Public-Ingress"
    }
  )
}

# ==============================================================================
# Security Group 2: Private Compute Tier (Kubernetes Nodes)
# ==============================================================================
resource "aws_security_group" "compute" {
  name        = "${var.project_name}-${var.environment}-compute-sg"
  description = "Security group for Kubernetes Compute Nodes"
  vpc_id      = var.vpc_id

  # Inbound traffic ONLY from ALB SG
  ingress {
    description     = "Allow traffic from ALB to application port"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Node-to-node internal communication (Cilium / K8s overlay)
  ingress {
    description = "Allow internal node-to-node cluster communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Outbound to all (Egress controlled via fck-nat and subnet routing)
  egress {
    description = "Allow outbound to internet via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-compute-sg"
      Tier = "Private-Compute"
    }
  )
}

# Add outbound rule from ALB to Compute SG
resource "aws_security_group_rule" "alb_to_compute" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.compute.id
  description              = "Allow ALB to route traffic to compute instances"
}

# ==============================================================================
# Security Group 3: Isolated Database Tier (RDS / Redis)
# ==============================================================================
resource "aws_security_group" "database" {
  name        = "${var.project_name}-${var.environment}-database-sg"
  description = "Security group for Isolated Database Tier (PostgreSQL / Redis)"
  vpc_id      = var.vpc_id

  # Inbound PostgreSQL (5432) ONLY from Compute SG
  ingress {
    description     = "Allow PostgreSQL access strictly from Compute SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.compute.id]
  }

  # Inbound Redis (6379) ONLY from Compute SG
  ingress {
    description     = "Allow Redis access strictly from Compute SG"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.compute.id]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-database-sg"
      Tier = "Isolated-Data"
    }
  )
}
