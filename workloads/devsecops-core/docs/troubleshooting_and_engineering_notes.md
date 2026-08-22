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
| **17**| Azure Scaler Auth Level, Zero-Dependency Architecture & Triggering | Azure VMSS Runner | Azure Functions / Webhook Log | `deb5280`, `392a673` | `modules/webhook-scaler/function_app/` |
| **18**| AWS Multi-VM Scale-Out via Loose Label Matching | AWS ASG Runner | AWS Lambda CloudWatch Logs | `70e9ae8` | `modules/webhook-scaler/lambda/scaler.py` |
| **19**| Gitleaks Action Organization Commercial License Gate | CI/CD Security | GitHub Actions Workflow Logs | `4a9b96a` | `.github/workflows/01-security-lint.yml` |
| **20**| OCI Lowercase Container Image Reference & Trivy Parsing | CI/CD Registry | Trivy Scanner Logs | `81e3207` | `.github/workflows/02-build-scan-sign.yml` |
| **21**| Runner Bootstrap Dependency Resilience & Fail-Closed Exit Traps | Ephemeral Runners | Cloud-Init / System Logs | `392a673`, `c804aa3` | `cloud_init.sh.tpl`, `user_data.sh.tpl` |

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

### 17. Azure Webhook Authentication (`AuthLevel.ANONYMOUS`), Zero-Dependency Architecture & Scaler Auto-Scale Triggering

- **Commits**: `deb5280`, `392a673`
- **Symptom**:
  1. Azure VMSS runner never scaled out when GitHub Actions workflows with `runs-on: [self-hosted, azure-spot]` were queued. Webhook deliveries received `HTTP 401/404` at the API Gateway / Function App perimeter.
  2. Unsigned direct requests or ping events received `404 Not Found` due to Python worker initialization failures.
- **Root Cause**:
  1. **HTTP Function Authorization Perimeter Block**: The Function App was configured with `http_auth_level=func.AuthLevel.FUNCTION` (`@app.route(..., auth_level=func.AuthLevel.FUNCTION)`). GitHub Webhooks deliver payloads with standard HMAC SHA-256 headers (`X-Hub-Signature-256`) but cannot dynamically append Azure Function Master/Default keys via query parameters (`?code=...`) or `x-functions-key` headers. The Azure Functions host intercepted incoming webhooks before the Python user code was executed.
  2. **Python Worker Indexing Crash from OS Binary Architecture Mismatch**: Top-level imports for `azure-data-tables` and `azure-identity` required native C-extensions (such as `_cffi`, `_cryptography`). When deployed from macOS development environments, binary wheels compiled for `darwin_arm64` failed to load in the Linux `x86_64` Python 3.11 Consumption worker runtime (`ModuleNotFoundError` during worker startup). This caused the Functions host to fail worker indexing, resulting in `404 Not Found` for all function routes.
- **Technical Resolution**:
  1. **Configured Anonymous Route with Application-Layer Cryptographic HMAC Validation**:
     Updated the route auth level to `AuthLevel.ANONYMOUS` and enforced strict fail-closed HMAC SHA-256 verification using Python's `hmac.compare_digest()`:
     ```python
     @app.route(route="webhook", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
     def github_webhook(req: func.HttpRequest) -> func.HttpResponse:
         body_bytes = req.get_body()
         if len(body_bytes) > 1024 * 1024:
             return func.HttpResponse(json.dumps({"error": "Payload too large"}), status_code=413)
         sig_header = req.headers.get("x-hub-signature-256", "")
         if not verify_signature(body_bytes, sig_header, WEBHOOK_SECRET):
             return func.HttpResponse(json.dumps({"error": "Unauthorized"}), status_code=401)
     ```
  2. **Zero-External-Dependency Runtime Architecture**:
     Refactored `function_app.py` to rely strictly on the Python 3.11 standard library (`urllib.request`, `hmac`, `hashlib`, `time`, `json`) and built-in `azure.functions` worker APIs. This eliminated all external wheel compilation requirements and cross-platform binary incompatibilities.
  3. **Sliding-Window In-Memory TTL Deduplication**:
     Replaced external Table Storage lookups during webhook ingestion with a lightweight, high-performance in-memory cache:
     ```python
     _DEDUP_CACHE = {}
     _DEDUP_TTL_SECONDS = 3600

     def claim_workflow_job(job_id) -> bool:
         if job_id is None:
             return True
         current_time = time.time()
         expired = [k for k, v in _DEDUP_CACHE.items() if current_time - v > _DEDUP_TTL_SECONDS]
         for k in expired:
             _DEDUP_CACHE.pop(k, None)
         job_str = str(job_id)
         if job_str in _DEDUP_CACHE:
             return False
         _DEDUP_CACHE[job_str] = current_time
         return True
     ```
  4. **Dynamic Management Token Acquisition via Managed Identity**:
     Acquired ARM tokens via the native App Service identity endpoint (`IDENTITY_ENDPOINT` with `X-IDENTITY-HEADER`) with fallback to IMDS (`169.254.169.254`):
     ```python
     def get_azure_management_token() -> str:
         identity_endpoint = os.environ.get("IDENTITY_ENDPOINT") or os.environ.get("MSI_ENDPOINT")
         identity_header = os.environ.get("IDENTITY_HEADER") or os.environ.get("MSI_SECRET")
         if identity_endpoint and identity_header:
             url = f"{identity_endpoint}?resource=https://management.azure.com/&api-version=2019-08-01"
             req = urllib.request.Request(url, headers={"X-IDENTITY-HEADER": identity_header})
             with urllib.request.urlopen(req, timeout=10) as resp:
                 return json.loads(resp.read().decode("utf-8"))["access_token"]
     ```

---

### 18. Elimination of Multiple VM Scale-Outs on AWS via Strict Runner Label Matching

- **Commit**: `70e9ae8`
- **Symptom**: Each workflow execution caused AWS Auto Scaling to launch 2 EC2 Spot runner instances, and non-AWS jobs (e.g., Azure runner tests) inadvertently triggered AWS instance launches.
- **Root Cause**:
  In `scaler.py`, label matching evaluated `any(label in job_labels for label in RUNNER_LABELS)`. Because both AWS (`[self-hosted, aws-spot]`) and Azure (`[self-hosted, azure-spot]`) workflows requested the common generic label `self-hosted`, the AWS Lambda scaler matched `self-hosted` on non-AWS jobs, treating them as valid AWS runner requests and incrementing the ASG desired capacity.
- **Technical Resolution**:
  Replaced loose `any()` evaluation with strict set-theoretic subset enforcement:
  ```python
  required_labels = set(RUNNER_LABELS)
  job_labels_set = set(job_labels)
  if not required_labels.issubset(job_labels_set):
      logger.info(f"Job labels {job_labels} do not match required runner labels {RUNNER_LABELS}. Skipping.")
      return {"statusCode": 200, "body": json.dumps({"message": "Label mismatch"})}
  ```
  AWS scaler only scales out when **both** `self-hosted` and `aws-spot` are explicitly present. CloudWatch execution logs confirmed that non-matching events (such as Azure jobs) are filtered and skipped in **7.58ms**, preventing unwanted EC2 provisioning.

---

### 19. Gitleaks Action Organization Commercial License Gate Resolution & Path Synchronization

- **Commit**: `4a9b96a`
- **Symptom**: Pipeline `01 - Shift-Left Security & Linting` failed with exit code 1 on the Gitleaks scanning step due to a missing commercial organization license (`GITLEAKS_LICENSE`).
- **Root Cause**:
  `gitleaks/gitleaks-action@v2` enforces commercial licensing restrictions on GitHub organization accounts. Additionally, repository restructuring into `workloads/devsecops-core/` left broken paths for Checkov, Hadolint, and deployment stage verification scripts.
- **Technical Resolution**:
  1. Replaced the action wrapper with direct execution of the official MIT-licensed open-source Gitleaks standalone binary:
     ```yaml
     - name: Gitleaks Secret Scanning
       env:
         GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}
       run: |
         echo "Installing standalone open-source Gitleaks binary..."
         GITLEAKS_VERSION="8.24.0"
         curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" | tar -xz -C /usr/local/bin gitleaks
         gitleaks detect --source . --verbose --redact
     ```
  2. Passed optional `GITLEAKS_LICENSE` to maintain compatibility with licensed enterprise secrets while guaranteeing free, full-fidelity scanning in community and lab scopes (scan completed in 3-6s).
  3. Synchronized relocated workload paths: Checkov to `workloads/devsecops-core/terraform/`, Hadolint to `workloads/devsecops-core/k8s/apps/secure-api/Dockerfile`, and deployment pipeline stage tests to `workloads/devsecops-core/tests/stages/`.

---

### 20. OCI Lowercase Container Image Reference & Trivy Scanner Parsing

- **Commit**: `81e3207`
- **Symptom**: Pipeline `02 - Build, Vulnerability Scan & Keyless Cosign Signing` failed during Trivy vulnerability scanning with:
  ```
  FATAL image scan error: unable to initialize container image: failed to parse the image name:
  could not parse reference: ghcr.io/QuocVanD-DevSecOpsLab/secure-api:latest
  ```
- **Root Cause**:
  The Open Container Initiative (OCI) image specification and Docker registry standards strictly require all repository namespace paths in container image references to be lowercase. When `${{ github.repository_owner }}` contained mixed-case letters (`QuocVanD-DevSecOpsLab`), `docker/metadata-action` automatically lowercased tags, but subsequent steps referencing `IMAGE_NAME` passed mixed-case strings, causing Trivy, Syft, and Cosign parsers to reject the image reference.
- **Technical Resolution**:
  Introduced an early lowercase normalization step in the workflow and bound environment variables across all container lifecycle actions:
  ```yaml
  - name: Set Lowercase Image Reference
    run: |
      IMAGE_LOWER=$(echo "${{ env.REGISTRY }}/${{ github.repository_owner }}/secure-api" | tr '[:upper:]' '[:lower:]')
      echo "IMAGE_REF=${IMAGE_LOWER}:latest" >> $GITHUB_ENV
      echo "IMAGE_BASE=${IMAGE_LOWER}" >> $GITHUB_ENV
  ```
  Updated `aquasecurity/trivy-action`, `syft`, and `cosign` to use `${{ env.IMAGE_REF }}` consistently.

---

### 21. Runner Cloud-Init Bootstrap Dependency Resilience & Fail-Closed Exit Traps

- **Commits**: `392a673`, `c804aa3`
- **Symptom**:
  Azure VMSS Spot instances launched from fresh Ubuntu 22.04 LTS images terminated before registering with GitHub; cloud-init logs showed `E: Unable to locate package libssl3t64$`.
- **Root Cause**:
  The GitHub Actions runner installer script (`./bin/installdependencies.sh`) in versions 2.322.0+ contains package references intended for Ubuntu 24.04 (`libssl3t64`). On Ubuntu 22.04 LTS (Jammy), `apt-get` returns a non-zero exit code when querying `libssl3t64`. Under `set -euo pipefail`, this non-zero exit code immediately aborted the bootstrap script and triggered the `teardown_runner` EXIT trap, causing the instance to self-terminate before configuring the runner.
- **Technical Resolution**:
  1. Updated `installdependencies.sh` invocation to `./bin/installdependencies.sh || true` in both `cloud_init.sh.tpl` and `user_data.sh.tpl`, since all essential runner prerequisites (`libicu`, `libssl`, `curl`, `jq`, `ca-certificates`) are explicitly installed in prior cloud-init steps.
  2. Retained the `teardown_runner` EXIT trap to ensure that unrecoverable errors or successful job completions safely trigger the ARM instance deletion endpoint (`/providers/Microsoft.Compute/virtualMachineScaleSets/{vmss}/delete`), guaranteeing the scale set returns to zero capacity automatically.


