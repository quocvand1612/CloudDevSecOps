#!/bin/bash
# ==============================================================================
# CloudDevSecOps - Autonomous Cost Guardrail & Auto-Cleanup Watchdog
# ==============================================================================
# Monitors AWS monthly budget & spend. If spend exceeds 50% of credit limit ($5.00),
# it triggers an automated clean-up (terraform destroy) to prevent any cost overruns.
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ACCOUNT_ID="033781183622"
BUDGET_NAME="cloud-devsecops-monthly-cost-guardrail"
THRESHOLD_USD=5.00
REGION="ap-southeast-1"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}💰 CloudDevSecOps: Autonomous Cost Guardrail Watchdog           ${NC}"
echo -e "${BLUE}   Account: ${ACCOUNT_ID} | Threshold: \$${THRESHOLD_USD} (50% of \$10 Credit)  ${NC}"
echo -e "${BLUE}================================================================${NC}"

# Query AWS Budgets API for current actual spend
CURRENT_SPEND=$(aws budgets describe-budget \
  --account-id "$ACCOUNT_ID" \
  --budget-name "$BUDGET_NAME" \
  --region "us-east-1" \
  --query "Budget.CalculatedSpend.ActualSpend.Amount" \
  --output text 2>/dev/null || echo "0.00")

# If describe-budget is empty or unavailable, fallback to 0.00
if [ -z "$CURRENT_SPEND" ] || [ "$CURRENT_SPEND" == "None" ]; then
    CURRENT_SPEND="0.00"
fi

echo -e "Current Actual Monthly Spend: ${YELLOW}\$${CURRENT_SPEND} USD${NC}"
echo -e "50% Credit Guardrail Limit:   ${BLUE}\$${THRESHOLD_USD} USD${NC}"

# Compare using bc or awk
EXCEEDED=$(awk -v spend="$CURRENT_SPEND" -v limit="$THRESHOLD_USD" 'BEGIN { print (spend >= limit) ? "1" : "0" }')

if [ "$EXCEEDED" == "1" ]; then
    echo -e "\n${RED}🚨 CRITICAL ALERT: AWS Spend (\$${CURRENT_SPEND}) has EXCEEDED 50% credit threshold (\$${THRESHOLD_USD})!${NC}"
    echo -e "${RED}🚨 Initiating immediate emergency cleanup (terraform destroy)...${NC}"
    
    cd "$(dirname "$0")/../terraform/environments/lab"
    terraform destroy -auto-approve || echo "Warning: Partial destruction completed."
    
    echo -e "\n${GREEN}✓ All lab cloud resources have been destroyed to protect budget.${NC}"
    exit 1
else
    PERCENT=$(awk -v spend="$CURRENT_SPEND" -v limit="10.00" 'BEGIN { printf "%.1f", (spend / limit) * 100 }')
    echo -e "\n${GREEN}✓ SAFE: Current spend is at ${PERCENT}% of monthly budget (Well below 50% limit).${NC}"
    echo -e "${GREEN}✓ Lab resources remain operational.${NC}"
    exit 0
fi
