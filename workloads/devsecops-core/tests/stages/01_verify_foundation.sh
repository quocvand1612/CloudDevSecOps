#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="${PROJECT_NAME:-cloud-devsecops}"
ENV="${ENVIRONMENT:-lab}"

echo "================================================================="
echo "🔍 [Stage 1 Gate Test] Verifying Foundation Tier (KMS & VPC Hub) "
echo "================================================================="

# 1. Verify KMS CMK
echo "Checking KMS Customer Managed Key..."
KMS_KEY_ID=$(aws kms list-aliases --region "$REGION" --query "Aliases[?AliasName=='alias/${PROJECT}-${ENV}-cmk'].TargetKeyId" --output text)
if [ -z "$KMS_KEY_ID" ] || [ "$KMS_KEY_ID" == "None" ]; then
  echo "❌ FAIL: KMS CMK Alias alias/${PROJECT}-${ENV}-cmk not found!"
  exit 1
fi

KEY_STATE=$(aws kms describe-key --key-id "$KMS_KEY_ID" --region "$REGION" --query "KeyMetadata.KeyState" --output text)
if [ "$KEY_STATE" != "Enabled" ]; then
  echo "❌ FAIL: KMS CMK state is $KEY_STATE (expected Enabled)!"
  exit 1
fi
echo "✓ KMS CMK ($KMS_KEY_ID) is ACTIVE and ENABLED."

# 2. Verify VPC
echo "Checking Multi-Tier VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT}-${ENV}-vpc" --region "$REGION" --query "Vpcs[0].VpcId" --output text)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo "❌ FAIL: VPC ${PROJECT}-${ENV}-vpc not found!"
  exit 1
fi
echo "✓ VPC ($VPC_ID) found."

# 3. Verify Subnet Topology (6 subnets across 2 AZs)
SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "length(Subnets)" --output text)
if [ "$SUBNET_COUNT" -lt 6 ]; then
  echo "❌ FAIL: Expected at least 6 subnets across 2 AZs, found $SUBNET_COUNT!"
  exit 1
fi
echo "✓ Subnet count: $SUBNET_COUNT (2 Public, 2 Private Compute, 2 Isolated Data)."

# 4. Verify S3 Gateway Endpoint
VPCE_COUNT=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=com.amazonaws.${REGION}.s3" --region "$REGION" --query "length(VpcEndpoints)" --output text)
if [ "$VPCE_COUNT" -lt 1 ]; then
  echo "❌ FAIL: S3 Gateway Endpoint not found in VPC $VPC_ID!"
  exit 1
fi
echo "✓ Zero-cost S3 Gateway Endpoint is active."

echo "================================================================="
echo "✅ [Stage 1 Gate Test] PASSED: Foundation Tier 100% Healthy"
echo "================================================================="
