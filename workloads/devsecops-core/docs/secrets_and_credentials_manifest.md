# Secrets & Cloud Credentials Manifest

> **Project**: `QuocVanD-DevSecOpsLab`  
> **Security Policy**: Zero Plaintext Secrets in Repositories • OIDC Workload Identity Authentication

---

## 1. Secrets Management Architecture

All credentials, tokens, and cryptographic keys are managed dynamically via native cloud secret stores and OIDC trust relationships:

1. **GitHub Organization / Repository Secrets**: Store only non-sensitive identifiers (e.g. `AZURE_CLIENT_ID`, `AWS_ROLE_TO_ASSUME`) or ephemeral webhook secrets.
2. **AWS Secrets Manager**: Stores short-lived runner registration tokens and infrastructure-level credentials.
3. **Azure Key Vault**: Stores runner registration tokens with Azure RBAC and MSI access policies.

---

## 2. Secrets & Identity Registry

### A. GitHub Actions Secrets (Org / Repo Level)

| Secret Key | Target Scope | Purpose | Stored Value Type |
| :--- | :--- | :--- | :--- |
| `AZURE_CLIENT_ID` | `QuocVanD-DevSecOpsLab/*` | Azure Entra ID App Registration Client ID | UUID (`32b042b1-2419-4eb9-b6c5-da2560bc2ddc`) |
| `AWS_ROLE_ARN` | `QuocVanD-DevSecOpsLab/*` | AWS IAM Role for GitHub OIDC | ARN (`arn:aws:iam::089204859876:role/...`) |
| `WEBHOOK_SECRET` | Repository Webhooks | HMAC SHA-256 signature verification for Scalers | Cryptographic random string (in TF/Lambda) |

---

### B. Azure Key Vault Secrets (`kv-mgmt-0cdrj`)

- **Resource Group**: `devsecops-runners-mgmt-rg`
- **Region**: `southeastasia`
- **Access Policy**:
  - Terraform admin principal (`5d938365-...`) -> Full Secret Permissions (Get, List, Set, Delete, Purge)
  - VMSS System-Assigned MSI Principal (`2d484f4d-...`) -> `Get` permissions only

| Secret Name | Purpose | Rotation Frequency | Retrieval Command |
| :--- | :--- | :--- | :--- |
| `github-runner-token` | Ephemeral GitHub Runner registration token | 1 hour TTL / refreshed on-demand | `az keyvault secret show --vault-name kv-mgmt-0cdrj --name github-runner-token --query value -o tsv` |

---

### C. AWS Secrets Manager Secrets (`ap-southeast-1`)

- **Region**: `ap-southeast-1`
- **Encryption**: AWS Managed KMS Key (`aws/secretsmanager`)
- **Access Policy**:
  - EC2 Instance Profile (`devsecops-runners-mgmt-runner-profile`) -> `secretsmanager:GetSecretValue`

| Secret Name | Purpose | Retrieval Command |
| :--- | :--- | :--- |
| `devsecops-runners-mgmt-github-runner-token` | Ephemeral EC2 Runner registration token | `aws secretsmanager get-secret-value --secret-id devsecops-runners-mgmt-github-runner-token --region ap-southeast-1 --query SecretString -o text` |

---

## 3. OIDC Federated Trust Configuration

### AWS OIDC Identity Provider
- **Provider URL**: `https://token.actions.githubusercontent.com`
- **Audience (`aud`)**: `sts.amazonaws.com`
- **Trust Policy Pattern**:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::089204859876:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          },
          "StringLike": {
            "token.actions.githubusercontent.com:sub": "repo:QuocVanD-DevSecOpsLab/*:*"
          }
        }
      }
    ]
  }
  ```

### Azure Entra ID Federated Credentials
- **App Registration Name**: `github-actions-devsecops-runners`
- **Issuer**: `https://token.actions.githubusercontent.com`
- **Configured Subjects**:
  - `repo:QuocVanD-DevSecOpsLab/platform-runners:ref:refs/heads/main`
  - `repo:QuocVanD-DevSecOpsLab/platform-runners:pull_request`
  - `repo:QuocVanD-DevSecOpsLab/AWS-DevSecOps:ref:refs/heads/main`
  - `repo:QuocVanD-DevSecOpsLab/AWS-DevSecOps:pull_request`

---

## 4. Secure Operational Procedures (No-Leak Commands)

### Rotating GitHub Runner Token across both AWS & Azure
Run this combined bash snippet to refresh runner tokens simultaneously:

```bash
# 1. Fetch fresh registration token for platform-runners
NEW_TOKEN=$(gh api --method POST /repos/QuocVanD-DevSecOpsLab/platform-runners/actions/runners/registration-token --jq '.token')

# 2. Update Azure Key Vault
az keyvault secret set --vault-name "kv-mgmt-0cdrj" --name "github-runner-token" --value "$NEW_TOKEN" --output none
echo "[+] Azure Key Vault token updated."

# 3. Update AWS Secrets Manager
aws secretsmanager put-secret-value --secret-id "devsecops-runners-mgmt-github-runner-token" --secret-string "$NEW_TOKEN" --region ap-southeast-1 --output none
echo "[+] AWS Secrets Manager token updated."
```
