# ==============================================================================
# fck-nat AMI (Amazon Linux 2023 ARM64)
# ==============================================================================
data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ==============================================================================
# IAM Role & SSM Profile (Keyless Access - No SSH Keys Needed)
# ==============================================================================
resource "aws_iam_role" "fck_nat" {
  name = "${var.project_name}-${var.environment}-fck-nat-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.fck_nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "fck_nat" {
  name = "${var.project_name}-${var.environment}-fck-nat-profile"
  role = aws_iam_role.fck_nat.name
}

# ==============================================================================
# Security Group for fck-nat (Egress Proxy)
# ==============================================================================
resource "aws_security_group" "fck_nat" {
  name        = "${var.project_name}-${var.environment}-fck-nat-sg"
  description = "Security group for fck-nat egress routing instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow inbound traffic from private subnets for NAT translation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound NTP"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-fck-nat-sg"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# Elastic IP for fck-nat
# ==============================================================================
resource "aws_eip" "fck_nat" {
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-fck-nat-eip"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# fck-nat EC2 Instance (Hardened with IMDSv2, KMS EBS, Detailed Monitoring)
# ==============================================================================
resource "aws_instance" "fck_nat" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.fck_nat.id]
  iam_instance_profile   = aws_iam_instance_profile.fck_nat.name

  source_dest_check           = false
  monitoring                  = true
  ebs_optimized               = true
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              dnf install -y iptables iptables-services
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/custom-ip-forwarding.conf
              sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf
              PRIMARY_IF=$(ip route | grep default | awk '{print $5}')
              iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE
              iptables-save > /etc/sysconfig/iptables
              systemctl enable iptables
              EOF

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-fck-nat"
      Environment = var.environment
      Role        = "NAT-Proxy"
      Security    = "IMDSv2-Enforced"
    }
  )
}

resource "aws_eip_association" "fck_nat" {
  instance_id   = aws_instance.fck_nat.id
  allocation_id = aws_eip.fck_nat.id
}

resource "aws_route" "private_nat" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.fck_nat.primary_network_interface_id
}
