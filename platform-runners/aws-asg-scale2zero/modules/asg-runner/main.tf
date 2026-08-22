# ==============================================================================
# AWS EC2 Auto Scaling Group for Scale-to-Zero GitHub Runners
# ==============================================================================

# Data source for latest Ubuntu 22.04 LTS AMI (fallback / base image that the
# golden image in packer/aws/runner-ami.pkr.hcl is built from)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [var.architecture == "arm64" ? "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*" : "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Latest self-baked golden image (docker, aws-cli, terraform, tflint, kubectl,
# helm, trivy, checkov, semgrep, cosign, syft, grype, GH runner pre-extracted).
# See packer/README.md. Only queried when var.use_golden_image = true.
data "aws_ami" "golden_runner" {
  count       = var.use_golden_image ? 1 : 0
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = ["devsecops-runner-golden-aws"]
  }

  filter {
    name   = "tag:Architecture"
    values = [var.architecture == "arm64" ? "arm64" : "amd64"]
  }
}

locals {
  runner_ami_id = var.use_golden_image ? data.aws_ami.golden_runner[0].id : data.aws_ami.ubuntu.id
}

# 1. Security Group: Egress Only (No Ingress Needed for GH Runners)
resource "aws_security_group" "runner_sg" {
  name        = "${var.project_name}-${var.environment}-runner-sg"
  description = "Egress-only security group for self-hosted GitHub Actions runners"
  vpc_id      = var.vpc_id

  egress {
    description      = "Allow all outbound HTTPS and traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_name}-runner-sg"
    Environment = var.environment
  }
}

# 2. IAM Instance Profile & Role for Runner Instances
resource "aws_iam_role" "runner_instance_role" {
  name = "${var.project_name}-${var.environment}-runner-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-runner-instance-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "runner_instance_policy" {
  name = "${var.project_name}-runner-instance-policy"
  role = aws_iam_role.runner_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSelfTerminationInASG"
        Effect = "Allow"
        Action = [
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "autoscaling:DescribeAutoScalingInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowFetchSecretAndSSM"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "runner_profile" {
  name = "${var.project_name}-${var.environment}-runner-profile"
  role = aws_iam_role.runner_instance_role.name
}

# 3. Launch Template (Spot Instances)
resource "aws_launch_template" "runner_lt" {
  name_prefix   = "${var.project_name}-${var.environment}-runner-lt-"
  image_id      = local.runner_ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner_profile.arn
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  vpc_security_group_ids = [aws_security_group.runner_sg.id]

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh.tpl", {
    token_secret_name = var.token_secret_name
    aws_region        = var.aws_region
    github_org        = var.github_org
    runner_labels     = var.runner_labels
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 Enforced
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.disk_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-spot-runner"
      Environment = var.environment
      Role        = "GitHub-Ephemeral-Runner"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 4. Auto Scaling Group (Scale-to-Zero: Min=0, Desired=0)
resource "aws_autoscaling_group" "runner_asg" {
  name_prefix         = "${var.project_name}-${var.environment}-asg-"
  vpc_zone_identifier = var.subnet_ids

  min_size         = 0
  desired_capacity = 0
  max_size         = var.max_runners

  launch_template {
    id      = aws_launch_template.runner_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-runner"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
