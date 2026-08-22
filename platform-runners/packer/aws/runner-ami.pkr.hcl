packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

# GitHub Actions runner architecture must match the ASG launch template's
# `architecture` variable (aws-asg-scale2zero/variables.tf).
variable "architecture" {
  type    = string
  default = "x64" # x64 | arm64
}

locals {
  ami_arch  = var.architecture == "arm64" ? "arm64" : "amd64"
  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
}

# Same source AMI lookup as aws-asg-scale2zero/modules/asg-runner/main.tf
# (data "aws_ami" "ubuntu") - kept identical so the golden image is a strict
# superset of the base OS already in use.
source "amazon-ebs" "runner" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = "ubuntu"

  source_ami_filter {
    filters = {
      name                = local.ami_arch == "arm64" ? "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*" : "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  ami_name        = "devsecops-runner-golden-aws-${local.ami_arch}-${local.timestamp}"
  ami_description = "Golden image for devsecops ephemeral GitHub Actions runners (AWS ASG). Pre-baked: docker, aws-cli, terraform, tflint, kubectl, helm, trivy, checkov, semgrep, cosign, syft, grype, GH runner v2.336.0."

  tags = {
    Name          = "devsecops-runner-golden-aws"
    Architecture  = local.ami_arch
    RunnerVersion = "2.336.0"
    BuiltBy       = "packer"
    Project       = "devsecops-runners"
  }
}

build {
  name    = "devsecops-runner-aws"
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    environment_vars = ["CLOUD=aws"]
    script           = "../scripts/provision-common.sh"
  }
}
