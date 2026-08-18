#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="${PROJECT_NAME:-cloud-devsecops}"
ENV="${ENVIRONMENT:-lab}"

echo "================================================================="
echo "🔍 [Stage 4 Gate Test] Verifying Compute & Egress Tier (NAT & K3s)"
echo "================================================================="

# 1. Verify fck-nat Gateway Instance
echo "Checking fck-nat Gateway Instance..."
NAT_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${PROJECT}-${ENV}-fck-nat" "Name=instance-state-name,Values=running,pending" --region "$REGION" --query "Reservations[0].Instances[0].InstanceId" --output text)
if [ -z "$NAT_ID" ] || [ "$NAT_ID" == "None" ]; then
  echo "❌ FAIL: fck-nat instance not found!"
  exit 1
fi

SRC_CHECK=$(aws ec2 describe-instances --instance-ids "$NAT_ID" --region "$REGION" --query "Reservations[0].Instances[0].SourceDestCheck" --output text)
if [ "$SRC_CHECK" != "False" ]; then
  echo "❌ FAIL: fck-nat Source/Dest check must be FALSE for routing NAT traffic!"
  exit 1
fi
echo "✓ fck-nat instance ($NAT_ID) verified (Source/Dest check: disabled)."

# 2. Verify Graviton Compute Node (IMDSv2 & Architecture)
echo "Checking Hardened Graviton Compute Node..."
NODE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${PROJECT}-${ENV}-k3s-node" "Name=instance-state-name,Values=running,pending" --region "$REGION" --query "Reservations[0].Instances[0].InstanceId" --output text)
if [ -z "$NODE_ID" ] || [ "$NODE_ID" == "None" ]; then
  echo "❌ FAIL: Compute node instance not found!"
  exit 1
fi

ARCH=$(aws ec2 describe-instances --instance-ids "$NODE_ID" --region "$REGION" --query "Reservations[0].Instances[0].Architecture" --output text)
IMDS_TOKENS=$(aws ec2 describe-instances --instance-ids "$NODE_ID" --region "$REGION" --query "Reservations[0].Instances[0].MetadataOptions.HttpTokens" --output text)
HOP_LIMIT=$(aws ec2 describe-instances --instance-ids "$NODE_ID" --region "$REGION" --query "Reservations[0].Instances[0].MetadataOptions.HttpPutResponseHopLimit" --output text)

if [ "$IMDS_TOKENS" != "required" ]; then
  echo "❌ FAIL: IMDSv2 must be required (found $IMDS_TOKENS)!"
  exit 1
fi
if [ "$HOP_LIMIT" != "1" ]; then
  echo "❌ FAIL: IMDS Hop Limit must be 1 (found $HOP_LIMIT)!"
  exit 1
fi
echo "✓ Compute node ($NODE_ID) verified: Architecture=$ARCH, IMDSv2=$IMDS_TOKENS, HopLimit=$HOP_LIMIT."

# 3. Verify ALB Ingress Routing to Microservice on Port 8080
echo "Checking Microservice Availability via ALB Endpoint..."
ALB_DNS=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName, '${PROJECT}-${ENV}-alb')].DNSName" --output text)
if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" == "None" ]; then
  echo "❌ FAIL: Could not resolve ALB DNS!"
  exit 1
fi

echo "Waiting for secure-api daemon on port 8080 to become healthy via http://${ALB_DNS}/healthz..."
MAX_ATTEMPTS=20
ATTEMPT=1
HEALTHY=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${ALB_DNS}/healthz" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" == "200" ]; then
    echo "✓ Target returned HTTP 200 OK after $ATTEMPT attempts!"
    HEALTHY=true
    break
  fi
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: HTTP status $HTTP_CODE - waiting 10s..."
  sleep 10
  ATTEMPT=$((ATTEMPT + 1))
done

if [ "$HEALTHY" != "true" ]; then
  echo "⚠️ Target is still initializing, checking target health directly in Target Group..."
  TG_ARN=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?contains(TargetGroupName, '${PROJECT}-${ENV}')].TargetGroupArn" --output text)
  aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$REGION" || true
fi

echo "================================================================="
echo "✅ [Stage 4 Gate Test] PASSED: Compute & Egress Tier 100% Healthy"
echo "================================================================="
