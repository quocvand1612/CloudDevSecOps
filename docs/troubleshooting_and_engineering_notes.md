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
