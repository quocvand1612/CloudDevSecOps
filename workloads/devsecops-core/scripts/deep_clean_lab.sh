#!/bin/bash
set -x
REGION="ap-southeast-1"
ACCOUNT_ID="033781183622"

echo "=== 1. Terminate EC2 Instances ==="
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=cloud-devsecops" "Name=instance-state-name,Values=running,pending,stopped,stopping" --region $REGION --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$INSTANCES" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCES --region $REGION || true
  aws ec2 wait instance-terminated --instance-ids $INSTANCES --region $REGION || true
fi

echo "=== 2. Delete Load Balancers & Target Groups ==="
ALB_ARNS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?contains(LoadBalancerName, 'cloud-devsecops')].LoadBalancerArn" --output text)
for alb in $ALB_ARNS; do
  aws elbv2 delete-load-balancer --load-balancer-arn $alb --region $REGION || true
done
sleep 5

TG_ARNS=$(aws elbv2 describe-target-groups --region $REGION --query "TargetGroups[?contains(TargetGroupName, 'cloud-devsecops')].TargetGroupArn" --output text)
for tg in $TG_ARNS; do
  aws elbv2 delete-target-group --target-group-arn $tg --region $REGION || true
done

echo "=== 3. Delete RDS & Subnet Groups ==="
aws rds delete-db-instance --db-instance-identifier "cloud-devsecops-lab-postgres" --skip-final-snapshot --delete-automated-backups --region $REGION || true
aws rds wait db-instance-deleted --db-instance-identifier "cloud-devsecops-lab-postgres" --region $REGION 2>/dev/null || true
aws rds delete-db-subnet-group --db-subnet-group-name "cloud-devsecops-lab-db-subnet-group" --region $REGION || true

echo "=== 4. Delete Lambda & EventBridge ==="
aws lambda delete-function --function-name "cloud-devsecops-lab-soar-remediation" --region $REGION || true
aws events remove-targets --rule "cloud-devsecops-lab-security-rule" --ids "TriggerSOARLambda" "1" --region $REGION || true
aws events delete-rule --name "cloud-devsecops-lab-security-rule" --region $REGION || true

echo "=== 5. Delete CloudWatch Logs ==="
aws logs delete-log-group --log-group-name "/aws/lambda/cloud-devsecops-lab-soar-remediation" --region $REGION || true
aws logs delete-log-group --log-group-name "/aws/vpc/cloud-devsecops-lab-flow-logs" --region $REGION || true

echo "=== 6. Delete Secrets Manager Secret ==="
aws secretsmanager delete-secret --secret-id "cloud-devsecops/lab/app-secrets" --force-delete-without-recovery --region $REGION || true

echo "=== 7. Delete KMS Alias ==="
aws kms delete-alias --alias-name "alias/cloud-devsecops-lab-cmk" --region $REGION || true

echo "=== 8. Delete IAM Roles & Instance Profiles ==="
# k8s node profile & role
aws iam remove-role-from-instance-profile --instance-profile-name "cloud-devsecops-lab-node-profile" --role-name "cloud-devsecops-lab-k8s-node-role" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "cloud-devsecops-lab-node-profile" 2>/dev/null || true
aws iam detach-role-policy --role-name "cloud-devsecops-lab-k8s-node-role" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
for pol in $(aws iam list-attached-role-policies --role-name "cloud-devsecops-lab-k8s-node-role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name "cloud-devsecops-lab-k8s-node-role" --policy-arn $pol || true
done
for pol in $(aws iam list-role-policies --role-name "cloud-devsecops-lab-k8s-node-role" --query "PolicyNames[]" --output text 2>/dev/null); do
  aws iam delete-role-policy --role-name "cloud-devsecops-lab-k8s-node-role" --policy-name $pol || true
done
aws iam delete-role --role-name "cloud-devsecops-lab-k8s-node-role" 2>/dev/null || true

# fck-nat profile & role
aws iam remove-role-from-instance-profile --instance-profile-name "cloud-devsecops-lab-fck-nat-profile" --role-name "cloud-devsecops-lab-fck-nat-role" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "cloud-devsecops-lab-fck-nat-profile" 2>/dev/null || true
aws iam detach-role-policy --role-name "cloud-devsecops-lab-fck-nat-role" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
for pol in $(aws iam list-attached-role-policies --role-name "cloud-devsecops-lab-fck-nat-role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name "cloud-devsecops-lab-fck-nat-role" --policy-arn $pol || true
done
for pol in $(aws iam list-role-policies --role-name "cloud-devsecops-lab-fck-nat-role" --query "PolicyNames[]" --output text 2>/dev/null); do
  aws iam delete-role-policy --role-name "cloud-devsecops-lab-fck-nat-role" --policy-name $pol || true
done
aws iam delete-role --role-name "cloud-devsecops-lab-fck-nat-role" 2>/dev/null || true

# soar lambda role
for pol in $(aws iam list-attached-role-policies --role-name "cloud-devsecops-lab-soar-lambda-role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name "cloud-devsecops-lab-soar-lambda-role" --policy-arn $pol || true
done
for pol in $(aws iam list-role-policies --role-name "cloud-devsecops-lab-soar-lambda-role" --query "PolicyNames[]" --output text 2>/dev/null); do
  aws iam delete-role-policy --role-name "cloud-devsecops-lab-soar-lambda-role" --policy-name $pol || true
done
aws iam delete-role --role-name "cloud-devsecops-lab-soar-lambda-role" 2>/dev/null || true
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/cloud-devsecops-lab-soar-lambda-policy" 2>/dev/null || true
aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/cloud-devsecops-lab-node-secrets-policy" 2>/dev/null || true

# flow logs role
for pol in $(aws iam list-attached-role-policies --role-name "cloud-devsecops-lab-flow-logs-role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null); do
  aws iam detach-role-policy --role-name "cloud-devsecops-lab-flow-logs-role" --policy-arn $pol || true
done
for pol in $(aws iam list-role-policies --role-name "cloud-devsecops-lab-flow-logs-role" --query "PolicyNames[]" --output text 2>/dev/null); do
  aws iam delete-role-policy --role-name "cloud-devsecops-lab-flow-logs-role" --policy-name $pol || true
done
aws iam delete-role --role-name "cloud-devsecops-lab-flow-logs-role" 2>/dev/null || true

echo "=== 9. Delete VPC, Endpoints, IGW, Subnets, Route Tables, SGs ==="
VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=cloud-devsecops" --region $REGION --query "Vpcs[].VpcId" --output text)
for vpc in $VPC_IDS; do
  # VPC Endpoints
  VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "VpcEndpoints[].VpcEndpointId" --output text)
  for ep in $VPC_ENDPOINTS; do
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep --region $REGION || true
  done

  # Flow logs
  FLOW_LOGS=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$vpc" --region $REGION --query "FlowLogs[].FlowLogId" --output text)
  for fl in $FLOW_LOGS; do
    aws ec2 delete-flow-logs --flow-log-ids $fl --region $REGION || true
  done

  # Network Interfaces
  ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
  for eni in $ENIS; do
    aws ec2 delete-network-interface --network-interface-id $eni --region $REGION || true
  done

  # IGW
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region $REGION --query "InternetGateways[].InternetGatewayId" --output text)
  for igw in $IGWS; do
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc --region $REGION || true
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION || true
  done

  # Subnets
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "Subnets[].SubnetId" --output text)
  for sn in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $sn --region $REGION || true
  done

  # Route Tables (non-main)
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text)
  for rt in $RTS; do
    aws ec2 delete-route-table --route-table-id $rt --region $REGION || true
  done

  # Security Groups (non-default)
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $SGS; do
    # clear ingress/egress rules first
    aws ec2 revoke-security-group-ingress --group-id $sg --protocol all --port -1 --source-group $sg --region $REGION 2>/dev/null || true
  done
  for sg in $SGS; do
    aws ec2 delete-security-group --group-id $sg --region $REGION || true
  done

  # Delete VPC
  aws ec2 delete-vpc --vpc-id $vpc --region $REGION || true
done

# Release EIPs
EIPS=$(aws ec2 describe-addresses --filters "Name=tag:Project,Values=cloud-devsecops" --region $REGION --query "Addresses[].AllocationId" --output text)
for eip in $EIPS; do
  aws ec2 release-address --allocation-id $eip --region $REGION || true
done

echo "=== 10. Clear Terraform S3 State & DynamoDB Lock ==="
aws s3 rm s3://cloud-devsecops-tfstate-${ACCOUNT_ID}-${REGION}/lab/terraform.tfstate --region $REGION || true
aws dynamodb delete-item --table-name cloud-devsecops-tflocks --key '{"LockID": {"S": "cloud-devsecops-tfstate-'${ACCOUNT_ID}'-'${REGION}'/lab/terraform.tfstate-md5"}}' --region $REGION 2>/dev/null || true

echo "=== Complete Purge Finished! ==="
