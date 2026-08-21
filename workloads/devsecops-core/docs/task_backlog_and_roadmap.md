# Task Backlog & Engineering Roadmap

> **Project**: `QuocVanD-DevSecOpsLab`  
> **Tracker**: Multi-Cloud DevSecOps Platform & Runner Infrastructure  
> **Status**: Phase 1 & Phase 2 Complete (AWS & Azure Scale-to-Zero Runners Operational)

---

## 1. Milestone Tracking Overview

```
[Phase 1: AWS Ephemeral Spot ASG Runner]   =====> [100% COMPLETE]
[Phase 2: Azure Ephemeral VMSS Runner]      =====> [100% COMPLETE]
[Phase 3: Workload Identity & OIDC Trust]   =====> [100% COMPLETE]
[Phase 4: Multi-Repo Pipeline Rollout]      =====> [IN PROGRESS]
[Phase 5: K8s / Workload DevSecOps Gates]   =====> [PLANNED]
```

---

## 2. Detailed Milestone Status

### Milestone 1: AWS Scale-to-Zero EC2 Spot Runner (`platform-runners/aws-asg-scale2zero`)
- [x] VPC with public & private subnets in `ap-southeast-1` (Singapore)
- [x] Low-cost `fck-nat` spot instance for egress routing ($0.003/hr vs $0.045/hr Managed NAT)
- [x] Auto Scaling Group with desired capacity `0`, min `0`, max `5`
- [x] Launch template with Spot instance allocation and cloud-init ephemeral runner bootstrap
- [x] AWS API Gateway HTTP API + Python Lambda Webhook Scaler for `workflow_job.queued`
- [x] Secrets Manager integration for runner registration token
- [x] GitHub Repository Webhook registered and live
- [x] End-to-end workflow execution verified on `[self-hosted, aws-spot]`

---

### Milestone 2: Azure Scale-to-Zero VMSS Runner (`platform-runners/azure-vmss-scale2zero`)
- [x] Resource Group `devsecops-runners-mgmt-rg` and Virtual Network in `southeastasia` (Singapore)
- [x] Linux VMSS with desired capacity `0`, min `0`, max `5` (`Standard_B2s`)
- [x] Cloud-init script with Azure Key Vault MSI token fetch, ephemeral runner execution, and automated self-deallocation
- [x] Storage Account (`scalerkjlj19sa`) & `Y1` Consumption Linux Function App (`devsecops-runners-mgmt-scaler-app`)
- [x] Azure Function Webhook Scaler (Python 3.11) with ARM VMSS capacity scaling API
- [x] Key Vault `kv-mgmt-0cdrj` access policy linked to VMSS Managed Identity
- [x] GitHub Repository Webhook registered and verified (`HTTP 200 PONG`)
- [x] Entra ID App Registration `github-actions-devsecops-runners` with Federated Identity Credentials

---

### Milestone 3: OIDC Passwordless Cloud Authentication
- [x] AWS IAM OIDC Identity Provider (`token.actions.githubusercontent.com`) and IAM Roles
- [x] Azure Entra ID Federated Credentials for branches `main` and `pull_request` across `platform-runners` and `AWS-DevSecOps`
- [x] GitHub secret `AZURE_CLIENT_ID` configured in repositories
- [x] Zero static long-lived credentials stored in GitHub Secrets

---

### Milestone 4: Multi-Repository Rollout & Workloads (Next Steps)
- [ ] Push local updates to `QuocVanD-DevSecOpsLab/platform-runners`
- [ ] Setup repository `QuocVanD-DevSecOpsLab/AWS-DevSecOps` with DevSecOps microservice codebase
- [ ] Configure CI/CD automated pipeline:
  - Security Linting & SAST (Trivy, Semgrep, tfsec, Checkov)
  - Container Build, Vulnerability Scan, & Cosign Keyless Image Signing
  - Automated deployment to K3s/EKS via OIDC ephemeral runner
- [ ] Provision `QuocVanD-DevSecOpsLab/Azure-DevSecOps` for AKS workloads

---

## 3. Handover Checklist for Next Engineer / Agent

When picking up this repository:
1. **Verify State Health**:
   ```bash
   # AWS Runner TF State
   terraform -chdir=platform-runners/aws-asg-scale2zero plan
   # Azure Runner TF State
   terraform -chdir=platform-runners/azure-vmss-scale2zero plan
   ```
2. **Verify Scale-to-Zero Compute Invariance**:
   - Both AWS ASG and Azure VMSS should report `0 instances` running while idle.
3. **Verify Webhooks**:
   ```bash
   gh api /repos/QuocVanD-DevSecOpsLab/platform-runners/hooks
   ```
4. **Trigger Test Jobs**:
   - AWS Spot Runner:
     ```bash
     gh workflow run "test-aws-ephemeral-runner.yml" -R QuocVanD-DevSecOpsLab/platform-runners
     ```
   - Azure VMSS Runner:
     ```bash
     gh workflow run "test-azure-ephemeral-runner.yml" -R QuocVanD-DevSecOpsLab/platform-runners
     ```
