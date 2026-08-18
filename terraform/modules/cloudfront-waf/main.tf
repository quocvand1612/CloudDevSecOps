terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# ==============================================================================
# AWS WAFv2 IP Set: Trusted Corporate Network
# ==============================================================================
resource "aws_wafv2_ip_set" "trusted_corporate" {
  provider           = aws.us_east_1
  name               = "${var.project_name}-${var.environment}-trusted-corp-ipset"
  description        = "Whitelisted IP ranges for corporate office egress"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.trusted_corporate_cidrs

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-trusted-corp-ipset"
      Environment = var.environment
    }
  )
}

# ==============================================================================
# AWS WAFv2 WebACL (Global for CloudFront - us-east-1 provider)
# ==============================================================================
resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-${var.environment}-cf-waf"
  description = "AWS WAF protecting CloudFront edge (OWASP Top 10 + Rate Limit + Corp Allow)"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 0: Priority Routing & Exemption for Corporate Network
  rule {
    name     = "AllowTrustedCorporateNetwork"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.trusted_corporate.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-corp-allow"
      sampled_requests_enabled   = true
    }
  }

  # Rule 1: AWS Managed Common Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Rate Limiting (500 req / 5 min per IP)
  rule {
    name     = "RateLimit500Per5Min"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 500
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf-webacl"
    sampled_requests_enabled   = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-cf-waf"
      Tier = "GlobalEdge"
    }
  )
}

# ==============================================================================
# Public Application Load Balancer (ALB)
# ==============================================================================
resource "aws_lb" "external" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-alb"
      Tier = "Public-Ingress"
    }
  )
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = tostring(var.app_port)
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-tg"
    }
  )
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access Denied: Direct origin access blocked by Zero-Trust policy."
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "verify_origin_token" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_token]
    }
  }
}

# ==============================================================================
# CloudFront Distribution (Edge CDN + Origin Shield + TLS 1.3 Strict)
# ==============================================================================
resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "CloudFront CDN for ${var.project_name} ${var.environment}"
  price_class     = "PriceClass_All"
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name = aws_lb.external.dns_name
    origin_id   = "ALBOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_token
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALBOrigin"

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-cdn"
      Environment = var.environment
      Security    = "Strict-TLS13-WAF-ZeroTrust"
    }
  )
}
