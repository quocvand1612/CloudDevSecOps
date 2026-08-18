#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="${PROJECT_NAME:-cloud-devsecops}"
ENV="${ENVIRONMENT:-lab}"

echo "================================================================="
echo "🔍 [Stage 2 Gate Test] Verifying Security & Data Tier (RDS & SM)  "
echo "================================================================="

# 1. Verify Security Groups
echo "Checking Security Groups..."
for sg_name in "${PROJECT}-${ENV}-compute-sg" "${PROJECT}-${ENV}-alb-sg" "${PROJECT}-${ENV}-database-sg"; do
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg_name" --region "$REGION" --query "SecurityGroups[0].GroupId" --output text)
  if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "❌ FAIL: Security Group $sg_name not found!"
    exit 1
  fi
  echo "✓ Security Group $sg_name ($SG_ID) verified."
done

# 2. Verify Secrets Manager
echo "Checking Secrets Manager Secret..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${PROJECT}/${ENV}/app-secrets" --region "$REGION" --query "ARN" --output text 2>/dev/null || true)
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" == "None" ]; then
  echo "❌ FAIL: Secret ${PROJECT}/${ENV}/app-secrets not found!"
  exit 1
fi

SECRET_KMS=$(aws secretsmanager describe-secret --secret-id "${PROJECT}/${ENV}/app-secrets" --region "$REGION" --query "KmsKeyId" --output text)
if [ -z "$SECRET_KMS" ] || [ "$SECRET_KMS" == "None" ]; then
  echo "❌ FAIL: Secret is not KMS encrypted!"
  exit 1
fi
echo "✓ Secrets Manager secret verified (KMS Key: $SECRET_KMS)."

# 3. Verify RDS Subnet Group & Database
echo "Checking RDS PostgreSQL DB Subnet Group..."
DB_SUBNET_GROUP=$(aws rds describe-db-subnet-groups --db-subnet-group-name "${PROJECT}-${ENV}-db-subnet-group" --region "$REGION" --query "DBSubnetGroups[0].DBSubnetGroupName" --output text)
if [ -z "$DB_SUBNET_GROUP" ] || [ "$DB_SUBNET_GROUP" == "None" ]; then
  echo "❌ FAIL: DB Subnet Group ${PROJECT}-${ENV}-db-subnet-group not found!"
  exit 1
fi
echo "✓ DB Subnet Group ($DB_SUBNET_GROUP) verified."

echo "Checking RDS PostgreSQL Instance..."
DB_STATUS=$(aws rds describe-db-instances --db-instance-identifier "${PROJECT}-${ENV}-postgres" --region "$REGION" --query "DBInstances[0].DBInstanceStatus" --output text)
if [ -z "$DB_STATUS" ] || [ "$DB_STATUS" == "None" ]; then
  echo "❌ FAIL: RDS DB Instance ${PROJECT}-${ENV}-postgres not found!"
  exit 1
fi

IS_PUBLIC=$(aws rds describe-db-instances --db-instance-identifier "${PROJECT}-${ENV}-postgres" --region "$REGION" --query "DBInstances[0].PubliclyAccessible" --output text)
if [ "$IS_PUBLIC" != "False" ]; then
  echo "❌ FAIL: RDS DB instance must NOT be publicly accessible (PubliclyAccessible=$IS_PUBLIC)!"
  exit 1
fi

IS_ENCRYPTED=$(aws rds describe-db-instances --db-instance-identifier "${PROJECT}-${ENV}-postgres" --region "$REGION" --query "DBInstances[0].StorageEncrypted" --output text)
if [ "$IS_ENCRYPTED" != "True" ]; then
  echo "❌ FAIL: RDS DB instance storage must be KMS encrypted!"
  exit 1
fi
echo "✓ RDS DB Instance verified (Status: $DB_STATUS, Public: No, Encrypted: Yes)."

echo "================================================================="
echo "✅ [Stage 2 Gate Test] PASSED: Security & Data Tier 100% Healthy"
echo "================================================================="
