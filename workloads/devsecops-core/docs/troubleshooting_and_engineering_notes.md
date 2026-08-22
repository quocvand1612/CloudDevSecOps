# Engineering & Troubleshooting Post-Mortem & Changelog

This document provides a comprehensive, production-grade reference for all technical challenges encountered, root-cause analyses, security implications, diagnostic steps, resolutions, and the corresponding git commits across the platform engineering lifecycle.

---

## Quick Reference: Issue & Fixing Commit Matrix

| # | Issue Summary | Impact Area | Diagnostic Tool | Fixing Commit | Modified Files |
| :-: | :--- | :--- | :--- | :-: | :--- |
| **1** | IAM OIDC Subject Claim Anti-Spoofing | IAM / CI/CD Auth | AWS STS OIDC JWT Inspection | `72edc73` | `terraform/bootstrap/main.tf` |
| **2** | Elimination of Hardcoded Plaintext Secrets | Secrets Management | Checkov / tfsec SAST | `72edc73` | `terraform/modules/secrets-manager/` |
| **3** | DynamoDB State Lock Contention in CI | Terraform State | AWS DynamoDB Scan | `a55f513` | `.github/workflows/03-terraform-oidc-deploy.yml` |
| **4** | Spot EC2 Modification (`StopInstances` Error) | EC2 Spot Compute | Terraform Apply Log | `8891d9c` | `terraform/modules/k3s-lab-node/main.tf`, `fck-nat/main.tf` |
| **5** | AL2023 Minimal AMI Missing `iptables` | NAT & Egress Proxy | AWS SSM Shell / `iptables` | `d8bad18` | `terraform/modules/fck-nat/main.tf` |
| **6** | Heredoc Indentation `execve()` Format Error | Cloud-Init / User-Data | `/var/log/cloud-init.log` via SSM | `12e68e9` | `terraform/modules/k3s-lab-node/main.tf`, `fck-nat/main.tf` |
| **7** | Deployment Pipeline Race Conditions | CI/CD Queue | GitHub Actions Run History | `06f6122` | `.github/workflows/03-terraform-oidc-deploy.yml` |
| **8** | Single Handler for All Microservice Paths | Microservice API | `curl` / ALB Response | `511631a` | `terraform/modules/k3s-lab-node/main.tf` |
| **9** | Public Perimeter IP Restriction & Whitelisting | Network Edge / WAF | Security Group / `checkip` | `00131b2`, `7b9c559` | `terraform/modules/security-groups/`, `lab/variables.tf` |
| **10**| Stage Gate Name Filter Alignment | Automated Verification | Stage Gate Bash Scripts | `eb125ce`, `69c2ffb` | `tests/stages/02_*.sh`, `tests/stages/04_*.sh` |
| **17**| Azure Scaler Auth Level & Auto Scale Trigger | Azure VMSS Runner | Azure Functions Log / Webhook | `HEAD` | `modules/webhook-scaler/function_app/` |
| **18**| AWS Multi-VM Scale-Out via Loose Label Matching | AWS ASG Runner | AWS Lambda CloudWatch Logs | `HEAD` | `modules/webhook-scaler/lambda/scaler.py` |
| **19**| Gitleaks Action Organization Commercial License Gate | CI/CD Security | GitHub Actions Workflow Logs | `HEAD` | `.github/workflows/01-security-lint.yml` |

---

## Detailed Root Cause Analyses & Resolutions

### 1. IAM OIDC Subject Claim Matching & Anti-Spoofing Protection
- **Commit**: `72edc73`
- **Symptom**: `sts:AssumeRoleWithWebIdentity` failed with `Not authorized to perform sts:AssumeRoleWithWebIdentity`.
- **Root Cause**: GitHub Actions token payload contains deterministic repo and org IDs (`repo:quocvand1612@317749204/CloudDevSecOps@1338120979`). Loose wildcards (`*CloudDevSecOps*`) are vulnerable to cross-tenant identity spoofing.
- **Resolution**: Anchored the IAM trust policy strictly to `repo:quocvand1612/CloudDevSecOps:*` and account-anchored sub claims.

---

### 2. Elimination of Hardcoded Secrets & Dynamic Cryptographic Generation
- **Commit**: `72edc73`
- **Symptom**: Checkov / tfsec flagged default password strings in `variables.tf`.
- **Root Cause**: Static fallback strings committed to git violate CIS AWS Benchmark 1.14.
- **Resolution**: Replaced fallback variables with native Terraform `random_password` resources (32-character high entropy with special character overrides) and marked interfaces `sensitive = true`.

---

### 3. DynamoDB State Lock Contention in Sequential CI/CD
- **Commit**: `a55f513` (`fix(ci): add -lock-timeout=60s to all tiered terraform apply jobs`)
- **Symptom**: Sequential workflow jobs failed with:
  ```
  Error: Error acquiring the state lock: ConditionalCheckFailedException
  Lock Info: ID: aa6728fc-...
  ```
- **Root Cause**: When Stage 1 completed and Stage 2 started immediately (~1-2s gap), DynamoDB had a momentary lock release propagation lag.
- **Resolution**: Added `-lock-timeout=60s` to all `terraform apply` commands in `.github/workflows/03-terraform-oidc-deploy.yml`.

---

### 4. EC2 Spot Instance Modification (`StopInstances` Not Supported on Spot)
- **Commit**: `8891d9c` (`fix(ec2): enable user_data_replace_on_change for spot compute and nat instances`)
- **Symptom**: Terraform failed when updating `user_data` on Spot EC2 instances:
  ```
  InvalidParameterCombination: Spot instances cannot be stopped/started
  ```
- **Root Cause**: By default, Terraform attempts to stop an instance in-place to modify user_data, which the AWS EC2 Spot API disallows.
- **Resolution**: Added `user_data_replace_on_change = true` to `aws_instance.node` and `aws_instance.fck_nat` so Terraform terminates and provisions a fresh Spot instance seamlessly.

---

### 5. Amazon Linux 2023 Minimal AMI Missing `iptables` for NAT Routing
- **Commit**: `d8bad18` (`fix(nat): install iptables-services on fck-nat and ensure secure-api file permissions`)
- **Symptom**: Private compute nodes in private subnets could not establish outbound connections or register with AWS SSM.
- **Root Cause**: Amazon Linux 2023 minimal images do not include `iptables` by default. The `fck-nat` user_data script failed silently during `iptables -t nat -A POSTROUTING`.
- **Resolution**: Added `dnf install -y iptables iptables-services`, enabled IP forwarding in sysctl, saved rules to `/etc/sysconfig/iptables`, and enabled the `iptables` systemd daemon.

---

### 6. Linux Kernel `execve()` Format Error (Errno 8) on Indented Heredocs
- **Commit**: `12e68e9` (`fix(iac): align user_data to column 0 to prevent execve Errno 8 format error`)
- **Symptom**: Private compute node booted but `secure-api.service` was missing. `/var/log/cloud-init.log` showed:
  ```
  Reason: [Errno 8] Exec format error: b'/var/lib/cloud/instance/scripts/part-001'
  ```
- **Root Cause**: In Terraform `<<-EOF`, indentation is stripped relative to the line with least whitespace. When embedded Python code was at column 0, the top line `#!/bin/bash` retained 14 leading spaces. The Linux kernel `execve()` requires magic bytes `0x23 0x21` (`#!`) at byte 0.
- **Resolution**: Aligned all lines of the `user_data` heredoc strictly to column 0.

---

### 7. Deployment Pipeline Race Conditions & Concurrency
- **Commit**: `06f6122` (`ci: add concurrency group to prevent overlapping terraform deployments`)
- **Symptom**: Multiple workflow runs triggered by rapid commits attempted parallel Terraform operations.
- **Root Cause**: Absence of GitHub Actions concurrency group allowed multiple runners to request OIDC tokens simultaneously.
- **Resolution**: Configured workflow concurrency group:
  ```yaml
  concurrency:
    group: terraform-deploy-${{ inputs.environment || 'lab' }}
    cancel-in-progress: false
  ```

---

### 8. Microservice URL Path Routing & OpenMetrics Telemetry
- **Commit**: `511631a` (`feat(api): add distinct route handlers for healthz, status, metrics, and threats`)
- **Symptom**: Requests to `/healthz`, `/api/v1/metrics`, and `/api/v1/status` all returned the generic welcome JSON.
- **Root Cause**: `SecureHandler.do_GET` lacked path parsing (`urllib.parse.urlparse`).
- **Resolution**: Implemented dedicated route handlers:
  - `/` -> System & Architecture Overview JSON
  - `/healthz` -> Microservice & Database Dependency Health Probe
  - `/api/v1/status` -> Live Zero-Trust & CIS Security Posture
  - `/api/v1/metrics` -> Prometheus Text Format (`text/plain; version=0.0.4`)
  - `/api/v1/threats` -> Threat Intelligence & Incident History
  - `404 Handler` -> RFC 7807 compliant error payload with route index.

---

### 9. Public Perimeter IP Restriction & Dynamic Whitelisting
- **Commits**: `00131b2` & `7b9c559`
- **Symptom**: ALB Security Group had open ingress `0.0.0.0/0`.
- **Root Cause**: Initial configuration allowed public internet ingress.
- **Resolution**: Parameterized `allowed_ingress_cidrs` across `security-groups` and `lab` environment. Dynamically added authorized client IP ranges (`125.235.173.172/32`, `103.111.244.0/22`) and deleted `0.0.0.0/0`.

---

### 10. Automated Stage Gate Filter & Name Alignment
- **Commits**: `eb125ce` & `69c2ffb`
- **Symptom**: Stage 2 and Stage 4 verification scripts exited with code 1.
- **Root Cause**: Script AWS CLI filters looked for `cloud-devsecops-lab-db-sg` and `k8s-node`, whereas Terraform named them `cloud-devsecops-lab-database-sg` and `cloud-devsecops-lab-node`.
- **Resolution**: Synchronized naming variables across all bash verification scripts in `tests/stages/`.

---

## Ephemeral GitHub Runner Platform: Scale-to-Zero Incident Notes (AWS and Azure)

These notes cover the AWS ASG and Azure VMSS ephemeral runners in
`QuocVanD-DevSecOpsLab/platform-runners`. They are intentionally operational:
commands check resource state but do not print runner tokens, webhook HMAC
secrets, Function keys, or storage credentials.

### 11. AWS Runner Did Not Tear Down After a Failed Job Bootstrap

- **Symptom**: An EC2 runner remained in the Auto Scaling group after a queued
  GitHub Actions job instead of returning to zero.
- **Root cause**: The repository runner registration token stored in AWS
  Secrets Manager had expired. GitHub registration then returned `404 Not
  Found`. The old user-data script used `set -e`, so it exited before reaching
  the self-termination command.
- **Impact**: Idle Spot capacity remained allocated and could increase cost.
- **Resolution**: `user_data.sh.tpl` now installs an EXIT trap after the AWS
  CLI and instance ID are available. Any bootstrap, token retrieval,
  registration, or runner failure requests
  `terminate-instance-in-auto-scaling-group --should-decrement-desired-capacity`.
  A successful ephemeral runner also terminates itself when its one job ends.

Safe AWS checks:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names devsecops-runners-mgmt-asg-20260821031937185500000004 \
  --region ap-southeast-1 \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,min:MinSize,max:MaxSize,instances:Instances[].{id:InstanceId,state:LifecycleState}}' \
  --output json

aws secretsmanager describe-secret \
  --secret-id devsecops-runners-mgmt-runner-token \
  --region ap-southeast-1 \
  --query '{name:Name,lastChanged:LastChangedDate}' --output json
```

Refresh the AWS registration token immediately before a manual test. Never
print it or pass it with a command-line argument:

```bash
token="$(gh api --method POST repos/QuocVanD-DevSecOpsLab/platform-runners/actions/runners/registration-token --jq .token)"
aws secretsmanager put-secret-value \
  --secret-id devsecops-runners-mgmt-runner-token \
  --secret-string "$token" --region ap-southeast-1 --output json >/dev/null
unset token
```

For a failed instance, inspect its console output and CloudTrail termination
events. Do not paste registration tokens into tickets or logs:

```bash
aws ec2 get-console-output --instance-id i-REPLACE_ME --latest \
  --region ap-southeast-1 --output text

aws cloudtrail lookup-events --region ap-southeast-1 \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=i-REPLACE_ME \
  --max-results 20 --output json
```

### 12. Duplicate `workflow_job.queued` Webhooks Created Extra Capacity

- **Symptom**: A GitHub redelivery scaled one job to two runners/VMs.
- **Root cause**: Webhook delivery is at-least-once. Incrementing desired
  capacity directly is not idempotent.
- **AWS resolution**: The Lambda conditionally inserts `workflow_job.id` into
  the PAY_PER_REQUEST DynamoDB table
  `devsecops-runners-mgmt-webhook-job-dedup`, with a one-hour TTL. A duplicate
  conditional write returns success to GitHub but does not scale the ASG.
- **Azure resolution in source**: The Function uses Azure Table Storage table
  `workflowjobdedup` and atomically creates a `workflow_job`/job-ID entity.
  It releases the claim if ARM scale-out fails. The dependency is
  `azure-data-tables`.

Check deduplication without exposing data values:

```bash
aws dynamodb describe-table \
  --table-name devsecops-runners-mgmt-webhook-job-dedup \
  --region ap-southeast-1 \
  --query 'Table.{status:TableStatus,billing:BillingModeSummary.BillingMode,items:ItemCount}' \
  --output json
```

### 13. Azure Webhook Did Not Initially Provision VMSS Capacity

- **Symptom**: The Function App existed but no Azure runner started for a
  queued job.
- **Root cause**: Terraform had created the hosting resources but had not
  deployed the Python v2 Function package. Also, the scaler Function App is
  deliberately in `devsecops-runners-mgmt-scaler-rg` (Southeast Asia), whereas
  the VMSS is in `devsecops-runners-mgmt-rg`.
- **Resolution**: The module archives `function_app/`, deploys it using
  `zip_deploy_file`, and sets `SCALER_PACKAGE_HASH` so source changes cause a
  Function App update. The Function managed identity has Virtual Machine
  Contributor on the VMSS resource group.
- **Verified behavior**: GitHub run `32470501196` completed successfully on
  an Azure Spot runner and the VMSS subsequently returned to capacity zero.

Use HTTP behavior and VMSS state as health evidence. `az functionapp function
list` can be empty for this Python v2 worker even when `/api/webhook` is
working.

```bash
az vmss show -g devsecops-runners-mgmt-rg -n devsecops-runners-mgmt-vmss \
  --query '{capacity:sku.capacity,provisioning:provisioningState}' -o json

az vmss list-instances -g devsecops-runners-mgmt-rg \
  -n devsecops-runners-mgmt-vmss \
  --query '[].{id:instanceId,name:name,provisioning:provisioningState}' -o json

az functionapp show -g devsecops-runners-mgmt-scaler-rg \
  -n devsecops-runners-mgmt-scaler-app \
  --query '{state:state,httpsOnly:httpsOnly}' -o json
```

### 14. Webhook Authentication and Financial-DDoS Controls

- **Threat**: An unauthenticated public webhook could repeatedly set runner
  capacity and cause cloud spend. Even invalid traffic can create API/Lambda or
  Function execution cost.
- **Implemented AWS controls**:
  - Required, validated (minimum 32-character) GitHub HMAC secret.
  - Fail-closed SHA-256 signature verification; a missing secret or header is
    rejected.
  - 1 MiB request-body limit.
  - API Gateway HTTP API throttle: 5 requests/second, burst 10.
  - Durable job-ID deduplication and ASG maximum held at 2 during remediation.
- **Implemented Azure source controls**:
  - Required, validated HMAC secret and fail-closed signature verification.
  - 1 MiB body limit and Table Storage job-ID deduplication.
  - Route configured for Function-level authentication; GitHub webhook URL is
    configured with a separate Function key plus the HMAC secret.

Generate and supply a secret only through an environment variable. Do not put
it in `*.tfvars`, shell history, a Terraform command-line `-var`, or source
control:

```bash
webhook_hmac="$(openssl rand -hex 32)"
export TF_VAR_github_webhook_secret="$webhook_hmac"
export TF_VAR_max_runners=2
terraform -chdir=platform-runners/aws-asg-scale2zero apply -input=false
terraform -chdir=platform-runners/azure-vmss-scale2zero apply -input=false
unset webhook_hmac
```

Validate the AWS protection with an unsigned request; it must return `401`:

```bash
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  --request POST --header 'Content-Type: application/json' --data '{}' \
  'https://23auxirdxk.execute-api.ap-southeast-1.amazonaws.com/webhook'

aws apigatewayv2 get-stage --api-id 23auxirdxk --stage-name '$default' \
  --region ap-southeast-1 \
  --query 'DefaultRouteSettings.{burst:ThrottlingBurstLimit,rate:ThrottlingRateLimit}' \
  --output json
```

**Azure follow-up / current caveat**: During remediation, the Function App
continued serving an older handler after zip deployment and restart. Its
`WEBHOOK_SECRET` setting was present (64 characters), but an unsigned direct
request still returned `200`, proving the running worker was not yet enforcing
the current fail-closed source. Do not consider Azure webhook authentication
complete until a locally generated, correctly signed `ping` receives `200`
and an unsigned request receives `401` or Function-auth rejection (`404`).
GitHub's synthetic `hooks/{id}/tests` delivery is unsigned and therefore
returns `401` by design; it is not a valid positive HMAC test.

Use this signed-ping pattern after rotating the HMAC and Function key, keeping
both values only in the current shell:

```bash
payload='{"zen":"auth-verification"}'
signature="sha256=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$webhook_hmac" -hex | sed 's/^.* //')"
curl --silent --show-error --request POST \
  --header 'Content-Type: application/json' \
  --header 'X-GitHub-Event: ping' \
  --header "X-Hub-Signature-256: $signature" \
  --data "$payload" 'AWS_WEBHOOK_URL'
```

For Azure, append the Function key to the actual GitHub webhook URL, but do
not print or commit that URL because its `code` query parameter is a secret.

### 15. Terraform State Locks and Safe Recovery

- **Symptom**: Azure local state reported `Error acquiring the state lock`.
- **Root cause**: A previous `terraform plan` was still running its provider
  refresh and legitimately held `.terraform.tfstate.lock.info`.
- **Resolution**: Wait for the owning Terraform process to exit. Do not use
  `-lock=false` or force-unlock while a matching process is active.

```bash
ps -axo pid,etime,command | rg '[t]erraform'
cat platform-runners/azure-vmss-scale2zero/.terraform.tfstate.lock.info
```

Only force-unlock after proving there is no active Terraform process and the
lock belongs to an abandoned local operation:

```bash
terraform -chdir=platform-runners/azure-vmss-scale2zero \
  force-unlock LOCK_ID_FROM_LOCK_FILE
```

### 16. End-to-End, Cost-Safe Test Checklist

1. Confirm both fleets are zero before dispatching a workflow.
2. Refresh the short-lived GitHub runner registration token immediately before
   the AWS or Azure test.
3. Dispatch one platform workflow at a time and monitor the assigned runner:

```bash
gh run view RUN_ID --repo QuocVanD-DevSecOpsLab/platform-runners \
  --json status,conclusion,jobs,url
```

4. Confirm exactly one instance was created for the job; duplicate events must
   not increase capacity twice.
5. After job completion, confirm ASG desired capacity and VMSS capacity are
   both zero using the commands above.
6. If a runner remains, capture console/cloud-init logs and termination
   events before manually draining it. Preserve evidence, then use the
   provider's normal ASG/VMSS scale command; never leave an unbounded runner
   group while diagnosing webhook behavior.

---

### 17. Azure Webhook Authentication (`AuthLevel.ANONYMOUS`) & Scaler Auto-Scale Triggering

- **Symptom**: Azure VMSS runner never scaled out when GitHub Actions workflows with `runs-on: [self-hosted, azure-spot]` were queued.
- **Root Cause**: The Azure Function App was configured with `http_auth_level=func.AuthLevel.FUNCTION`. Standard GitHub Webhook configurations send HMAC signatures (`X-Hub-Signature-256`) but do not attach Azure Function Master/Default keys via query strings or headers. The Azure Functions host intercepted incoming webhooks with HTTP 401/404 before the Python handler executed.
- **Resolution**:
  1. Configured `@app.route(..., auth_level=func.AuthLevel.ANONYMOUS)` to allow webhook delivery to reach the Python entrypoint.
  2. Maintained strict cryptographic protection in `verify_signature()` via fail-closed HMAC SHA-256 verification with `WEBHOOK_SECRET`.
  3. Integrated `DefaultAzureCredential` from `azure-identity` with fallback to `IDENTITY_ENDPOINT` and IMDS for robust ARM management token acquisition.
  4. Added `teardown_runner` EXIT trap in `cloud_init.sh.tpl` to guarantee VMSS instance deletion on bootstrap failure or completion.

---

### 18. Elimination of Multiple VM Scale-Outs on AWS via Strict Runner Label Matching

- **Symptom**: Each workflow execution caused AWS Auto Scaling to launch 2 EC2 Spot runner instances.
- **Root Cause**: The webhook scaler used loose `any(label in job_labels for label in RUNNER_LABELS)` matching. Because both AWS and Azure workflows requested the common generic label `self-hosted`, the AWS Lambda scaler matched `self-hosted` on non-AWS/Azure jobs (e.g. `[self-hosted, azure-spot]`), treating them as AWS requests and incrementing ASG desired capacity.
- **Resolution**:
  1. Replaced `any(...)` with strict subset enforcement:
     ```python
     required_labels = set(RUNNER_LABELS)
     job_labels_set = set(job_labels)
     if not required_labels.issubset(job_labels_set):
         return {"statusCode": 200, "body": json.dumps({"message": "Label mismatch"})}
     ```
  2. AWS scaler only provisions capacity when both `self-hosted` and `aws-spot` are explicitly required by the workflow job.
  3. Azure scaler similarly requires `self-hosted` and `azure-spot` to scale the VMSS.

---

### 19. Gitleaks Action Commercial License Gate Resolution & Path Synchronization

- **Symptom**: Security workflows failed on Gitleaks scanning with organizational license requirements (`GITLEAKS_LICENSE` required for organizations in `gitleaks-action@v2`).
- **Root Cause**: `gitleaks/gitleaks-action` v2 enforces commercial licensing checks for GitHub organization accounts. Additionally, repository restructuring into `workloads/devsecops-core/` left broken paths for Checkov, Hadolint, and deployment stage gates.
- **Resolution**:
  1. Replaced `gitleaks/gitleaks-action` with direct execution of the official open-source Gitleaks standalone binary (`gitleaks detect --source . --verbose --redact`), bypassing the action wrapper license gate while preserving full secret scanning.
  2. Passed optional `GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}` to maintain compatibility with licensed enterprise secrets.
  3. Updated Checkov directory to `workloads/devsecops-core/terraform/` and Hadolint target to `workloads/devsecops-core/k8s/apps/secure-api/Dockerfile`.
  4. Updated deployment pipeline working directories and test stage paths in `03-terraform-oidc-deploy.yml`.

