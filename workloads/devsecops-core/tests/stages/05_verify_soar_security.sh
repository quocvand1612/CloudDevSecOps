#!/bin/bash
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-1}"
PROJECT="${PROJECT_NAME:-cloud-devsecops}"
ENV="${ENVIRONMENT:-lab}"

echo "================================================================="
echo "🔍 [Stage 5 Gate Test] Verifying SOAR Automation & Threat Defense"
echo "================================================================="

# 1. Verify SOAR Lambda Function
echo "Checking SOAR Remediation Lambda Function..."
LAMBDA_ARN=$(aws lambda get-function --function-name "${PROJECT}-${ENV}-soar-remediation" --region "$REGION" --query "Configuration.FunctionArn" --output text 2>/dev/null || true)
if [ -z "$LAMBDA_ARN" ] || [ "$LAMBDA_ARN" == "None" ]; then
  echo "❌ FAIL: Lambda function ${PROJECT}-${ENV}-soar-remediation not found!"
  exit 1
fi
echo "✓ SOAR Lambda verified: $LAMBDA_ARN"

# 2. Verify EventBridge Rule & Targets
echo "Checking EventBridge Security Finding Rule..."
RULE_STATE=$(aws events describe-rule --name "${PROJECT}-${ENV}-security-rule" --region "$REGION" --query "State" --output text)
if [ "$RULE_STATE" != "ENABLED" ]; then
  echo "❌ FAIL: EventBridge rule is $RULE_STATE (expected ENABLED)!"
  exit 1
fi

TARGET_COUNT=$(aws events list-targets-by-rule --rule "${PROJECT}-${ENV}-security-rule" --region "$REGION" --query "length(Targets)" --output text)
if [ "$TARGET_COUNT" -lt 1 ]; then
  echo "❌ FAIL: EventBridge rule has 0 targets!"
  exit 1
fi
echo "✓ EventBridge Rule verified: $RULE_STATE ($TARGET_COUNT active targets)."

# 3. Run Live Security Attack Simulation Suite
echo "Executing Full 5/5 Live Threat Simulation Suite..."
./tests/security/simulate_attack.sh

echo "================================================================="
echo "✅ [Stage 5 Gate Test] PASSED: End-to-End DevSecOps Verification!"
echo "================================================================="
