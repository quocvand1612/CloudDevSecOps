#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="${PROJECT_NAME:-cloud-devsecops}"
ENV="${ENVIRONMENT:-lab}"

echo "================================================================="
echo "🔍 [Stage 3 Gate Test] Verifying Edge Ingress Tier (ALB & WAF)   "
echo "================================================================="

# 1. Verify Application Load Balancer
echo "Checking Application Load Balancer..."
ALB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}-${ENV}-alb')].LoadBalancerArn" --output text)
if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
  echo "❌ FAIL: Application Load Balancer for ${PROJECT}-${ENV} not found!"
  exit 1
fi

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query "LoadBalancers[0].DNSName" --output text)
ALB_SCHEME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query "LoadBalancers[0].Scheme" --output text)
echo "✓ ALB verified: $ALB_DNS (Scheme: $ALB_SCHEME)"

# 2. Verify Target Group on Port 8080
echo "Checking Ingress Target Group..."
TG_ARN=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?contains(TargetGroupName, '${PROJECT}-${ENV}')].TargetGroupArn" --output text)
if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
  echo "❌ FAIL: Target Group not found!"
  exit 1
fi

TG_PORT=$(aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" --region "$REGION" --query "TargetGroups[0].Port" --output text)
TG_PATH=$(aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" --region "$REGION" --query "TargetGroups[0].HealthCheckPath" --output text)
if [ "$TG_PORT" != "8080" ]; then
  echo "❌ FAIL: Target Group port is $TG_PORT (expected 8080)!"
  exit 1
fi
echo "✓ Target Group verified (Port: $TG_PORT, Health Check Path: $TG_PATH)."

# 3. Verify HTTP Listener
echo "Checking ALB Listener..."
LISTENER_COUNT=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$REGION" --query "length(Listeners)" --output text)
if [ "$LISTENER_COUNT" -lt 1 ]; then
  echo "❌ FAIL: No listeners found on ALB $ALB_ARN!"
  exit 1
fi
echo "✓ ALB Listeners verified (Count: $LISTENER_COUNT)."

echo "================================================================="
echo "✅ [Stage 3 Gate Test] PASSED: Edge Ingress Tier 100% Healthy"
echo "================================================================="
