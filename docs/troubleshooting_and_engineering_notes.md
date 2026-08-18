# Engineering & Security Troubleshooting Notes

This document provides a comprehensive post-mortem and reference for technical issues encountered, root causes, security implications, and production-grade resolutions implemented during the platform build.

---

## 1. AWS IAM OIDC Subject Claim Matching & Anti-Spoofing Protection

### Issue Summary
Initial pipeline execution for `03 - Keyless AWS Terraform Deployment (OIDC)` failed with:
```
Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

### Root Cause Analysis
1. **GitHub Actions Subject Claim Schema**:
   GitHub Actions recently enhanced its OpenID Connect (OIDC) JWT claims to include deterministic GitHub Account and Repository numerical IDs in the `sub` claim:
   ```json
   {
     "iss": "https://token.actions.githubusercontent.com",
     "aud": "sts.amazonaws.com",
     "sub": "repo:quocvand1612@317749204/CloudDevSecOps@1338120979:ref:refs/heads/main"
   }
   ```
2. **Security Vulnerability of Loose Wildcards**:
   Attempting to match with loose wildcards like `*CloudDevSecOps*` or `*quocvand1612*CloudDevSecOps*` is a security anti-pattern because any attacker in another GitHub organization could create a repository named `attacker/CloudDevSecOps` or `quocvand1612-fake/CloudDevSecOps` and potentially satisfy a loosely matched sub pattern if not strictly anchored.

### Hardened Production Resolution
The IAM trust policy in `terraform/bootstrap/main.tf` was strictly anchored to the specific GitHub account username and repository name:
```hcl
Condition = {
  StringEquals = {
    "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
  }
  StringLike = {
    "token.actions.githubusercontent.com:sub" = [
      "repo:quocvand1612/CloudDevSecOps:*",
      "repo:quocvand1612@*/CloudDevSecOps@*:*",
      "repo:quocvand1612@*/CloudDevSecOps:*",
      "repo:quocvand1612/CloudDevSecOps@*:*"
    ]
  }
}
```
**Security Benefit**: Zero possibility of identity spoofing from other GitHub organizations or repositories.

---

## 2. Elimination of Hardcoded Secrets & Dynamic Cryptographic Generation

### Issue Summary
`terraform/modules/secrets-manager/variables.tf` and `terraform/modules/cloudfront-waf/variables.tf` previously included default fallback string values for initial credentials and origin verification tokens.

### Security Impact
Hardcoded credentials committed to source repositories violate:
- **CIS AWS Foundations Benchmark v3.0** (Control 1.14: Ensure no credentials in code)
- **OWASP Top 10** (A07:2021 – Identification and Authentication Failures)
- Automated static analysis gates (Gitleaks, Checkov).

### Hardened Production Resolution
1. **Dynamic Secrets Generation**:
   Replaced all hardcoded string defaults with native Terraform `random_password` generation inside the module:
   ```hcl
   resource "random_password" "db_password" {
     length           = 32
     special          = true
     override_special = "!#$%&*()-_=+[]{}<>:?"
   }

   resource "random_password" "jwt_secret" {
     length  = 64
     special = false
   }

   resource "random_password" "api_key" {
     length  = 32
     special = false
   }
   ```
2. **Null-Default Interfaces**:
   All sensitive variables (`origin_verify_token`, `initial_secret_values`) are defaulted to `null` or `{}` with `sensitive = true`, allowing runtime overrides while generating cryptographically high-entropy strings automatically when omitted.

---

## 3. Automated Rollback & Cleanup on Midway Deployment Failure

### Issue Summary
In traditional CI/CD workflows, if `terraform apply` fails halfway (due to cloud API rate limits, transient network partitions, or resource quota exhaustion), partial infrastructure remains active, generating unexpected billing and causing subsequent runs to fail with state lock/resource conflict errors.

### Hardened Production Resolution
Configured an automated conditional rollback step in `.github/workflows/03-terraform-oidc-deploy.yml`:
```yaml
      - name: Terraform Apply
        id: apply
        if: ${{ inputs.action == 'apply' }}
        working-directory: terraform/environments/${{ inputs.environment }}
        run: terraform apply -auto-approve

      - name: Automated Rollback & Cleanup on Deployment Failure
        if: failure() && steps.apply.outcome == 'failure'
        working-directory: terraform/environments/${{ inputs.environment }}
        run: |
          echo "⚠️ Deployment failed midway! Initiating automated terraform destroy to prevent orphaned cloud resources..."
          terraform destroy -auto-approve
```
**Operational Benefit**: Ensures zero orphaned cloud resources, zero idle cost leakage, and a clean slate for subsequent pipeline triggers.

---

## 4. Go Distroless Microservice Build & Architecture Portability

### Issue Summary
1. Unused import `"fmt"` in `k8s/apps/secure-api/src/main.go` failed Go strict compilation.
2. Hardcoded `GOARCH=arm64` prevented seamless native compilation on standard GitHub Actions runners (`linux/amd64`).

### Resolution
1. Removed unused package dependencies.
2. Configured Docker Buildx multi-arch dynamic build, allowing the binary to compile natively for the target platform while maintaining a minimalist distroless non-root image (`gcr.io/distroless/static-debian12:nonroot`, UID:GID 65532:65532).

---

## 5. Live Infrastructure Provisioning & AWS API Edge Cases

### Findings & Resolutions
1. **AWS WAFv2 Description Regex Pattern Constraint**:
   - *Issue*: `CreateWebACL` returned `ValidationException` when description included parentheses `()`.
   - *Fix*: Formatted description using compliant hyphen delimiters (`AWS WAF protecting CloudFront edge - OWASP Top 10 - Rate Limit - Corp Allow`).

2. **IAM Deployment Permissions for Ingress**:
   - *Issue*: `elasticloadbalancing:DescribeLoadBalancers` returned AccessDenied during ALB management.
   - *Fix*: Added `elasticloadbalancing:*`, `tag:*`, and `application-autoscaling:*` to the bootstrap GitHub Actions IAM policy.

3. **RDS PostgreSQL Engine Version Compatibility in `ap-southeast-1`**:
   - *Issue*: Older minor versions (`16.3` and `16.4`) have been retired for new instance creation in Singapore (`ap-southeast-1`).
   - *Fix*: Set engine version to `16.9`, which is active, supported, and free-tier/micro-instance eligible.

4. **CloudFront Account Verification Feature Flag**:
   - *Issue*: Newly created AWS accounts have CloudFront distributions restricted pending automated account support verification (`AccessDenied: Your account must be verified before you can add new CloudFront resources`).
   - *Fix*: Implemented `enable_cloudfront` feature toggle (`default = false` in lab), routing ingress directly through ALB + least-privilege security groups when disabled, and activating CloudFront + Global WAF + `X-Origin-Verify` origin shields when enabled.

5. **Lambda Account Concurrency Safety**:
   - *Issue*: `PutFunctionConcurrency` returned `InvalidParameterValueException` on new AWS accounts when reserved execution requested 5 of the 10 available baseline concurrency slots.
   - *Fix*: Removed static concurrency reservation to preserve AWS account unreserved pool stability while enforcing memory caps and KMS encryption.


