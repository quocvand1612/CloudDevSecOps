output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.cdn[0].domain_name : null
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.cdn[0].id : null
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
  value       = var.enable_cloudfront ? aws_wafv2_web_acl.cloudfront[0].arn : null
}

output "trusted_corporate_ip_set_arn" {
  description = "ARN of the trusted corporate WAF IP set"
  value       = var.enable_cloudfront ? aws_wafv2_ip_set.trusted_corporate[0].arn : null
}
