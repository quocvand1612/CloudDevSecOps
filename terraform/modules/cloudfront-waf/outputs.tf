output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cdn.id
}

output "alb_dns_name" {
  description = "DNS name of the Public ALB"
  value       = aws_lb.external.dns_name
}

output "alb_target_group_arn" {
  description = "Target group ARN for instance registration"
  value       = aws_lb_target_group.app.arn
}

output "waf_web_acl_arn" {
  description = "ARN of the AWS WAFv2 WebACL"
  value       = aws_wafv2_web_acl.cloudfront.arn
}

output "trusted_corporate_ip_set_arn" {
  description = "ARN of the trusted corporate WAF IP set"
  value       = aws_wafv2_ip_set.trusted_corporate.arn
}
