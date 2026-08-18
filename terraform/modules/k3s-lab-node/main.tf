# ==============================================================================
# Amazon Linux 2023 ARM64 AMI
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
# Node IAM Role & Profile (Keyless Access via IAM / SSM / Secrets)
# ==============================================================================
resource "aws_iam_role" "node" {
  name = "${var.project_name}-${var.environment}-k8s-node-role"

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
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.project_name}-${var.environment}-node-secrets-policy"
  description = "Allows k8s node to read designated application secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secret_arn
      },
      {
        Sid    = "DecryptWithKMS"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = aws_iam_role.node.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-${var.environment}-node-profile"
  role = aws_iam_role.node.name
}

# ==============================================================================
# Hardened EC2 Instance (Spot / On-Demand with Detailed Monitoring & EBS Optimized)
# ==============================================================================
resource "aws_instance" "node" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.compute_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  monitoring    = true
  ebs_optimized = true

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              cat << 'SYSCTL' > /etc/sysctl.d/99-hardened.conf
              fs.protected_hardlinks = 1
              fs.protected_symlinks = 1
              fs.suid_dumpable = 0
              kernel.randomize_va_space = 2
              net.ipv4.conf.all.rp_filter = 1
              net.ipv4.conf.default.rp_filter = 1
              net.ipv4.conf.all.accept_source_route = 0
              net.ipv4.conf.default.accept_source_route = 0
              SYSCTL
              sysctl -p /etc/sysctl.d/99-hardened.conf

              curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --disable traefik --disable servicelb" sh -

              sleep 10
              export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

              cat << 'K8S' | /usr/local/bin/kubectl apply -f -
              apiVersion: v1
              kind: Namespace
              metadata:
                name: prod-workload
                labels:
                  pod-security.kubernetes.io/enforce: restricted
              ---
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: secure-api
                namespace: prod-workload
                labels:
                  app: secure-api
              spec:
                replicas: 2
                selector:
                  matchLabels:
                    app: secure-api
                template:
                  metadata:
                    labels:
                      app: secure-api
                  spec:
                    securityContext:
                      runAsNonRoot: true
                      runAsUser: 10001
                      runAsGroup: 10001
                      fsGroup: 10001
                      seccompProfile:
                        type: RuntimeDefault
                    containers:
                    - name: secure-api
                      image: public.ecr.aws/docker/library/busybox:latest
                      command: ["/bin/sh", "-c"]
                      args:
                        - |
                          while true; do
                            printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{"status":"healthy","service":"CloudDevSecOps","zero_trust":true,"runtime_security":"active"}\n' | nc -l -p 8080
                          done
                      ports:
                      - containerPort: 8080
                      securityContext:
                        allowPrivilegeEscalation: false
                        readOnlyRootFilesystem: true
                        capabilities:
                          drop:
                          - ALL
                      resources:
                        limits:
                          cpu: 100m
                          memory: 64Mi
                        requests:
                          cpu: 50m
                          memory: 32Mi
              ---
              apiVersion: v1
              kind: Service
              metadata:
                name: secure-api-svc
                namespace: prod-workload
              spec:
                type: NodePort
                selector:
                  app: secure-api
                ports:
                - port: 8080
                  targetPort: 8080
                  nodePort: 30080
              K8S
              EOF

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-node"
      Environment = var.environment
      Role        = "Kubernetes-Compute"
      Security    = "IMDSv2-Hardened"
    }
  )
}

resource "aws_lb_target_group_attachment" "node" {
  target_group_arn = var.alb_target_group_arn
  target_id        = aws_instance.node.id
  port             = 8080
}
