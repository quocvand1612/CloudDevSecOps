# STRIDE Threat Model: CloudDevSecOps Platform

This document outlines the threat modeling assessment conducted for the CloudDevSecOps reference architecture using the **STRIDE** methodology (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, and Elevation of Privilege).

---

## 1. System Scope & Trust Boundaries

```
[ External Internet ]
        │
────────┼─────────────────────────────────────────────────────────── [ Trust Boundary 1: Global Edge ]
        ▼
[ CloudFront CDN + AWS WAF ]
        │  (mTLS / X-Origin-Verify Header)
────────┼─────────────────────────────────────────────────────────── [ Trust Boundary 2: Ingress Tier ]
        ▼
[ Application Load Balancer ]
        │  (Private Subnet Routing)
────────┼─────────────────────────────────────────────────────────── [ Trust Boundary 3: Compute Tier ]
        ▼
[ Kubernetes Compute (Cilium eBPF / Bottlerocket) ]
        │  (Isolated Subnet Routing / Port 5432)
────────┼─────────────────────────────────────────────────────────── [ Trust Boundary 4: Data Tier ]
        ▼
[ RDS PostgreSQL (KMS CMK Encrypted) ]
```

---

## 2. STRIDE Threat Analysis Matrix

| Threat Category | Potential Attack Vector | Impact | Mitigating Security Control |
| :--- | :--- | :--- | :--- |
| **Spoofing (S)** | Direct traffic injection to ALB bypassing CloudFront WAF | High | ALB listener drops requests lacking secret header `X-Origin-Verify`. CloudFront is the only authorized ingress point. |
| **Spoofing (S)** | Forged container images pushed to production registry | Critical | **Cosign keyless cryptographic signing** with Sigstore & GitHub Actions OIDC verification before admission. |
| **Tampering (T)** | Modification of container files or rootfs at runtime | High | Enforced `readOnlyRootFilesystem: true` via Kyverno admission policy; Bottlerocket immutable OS. |
| **Tampering (T)** | Tampering with Terraform state files | Critical | S3 Bucket Versioning + KMS CMK encryption + DynamoDB state locking + strict IAM OIDC role scoping. |
| **Repudiation (R)** | Unauthorized infrastructure changes with denied actions | Medium | AWS CloudTrail enabled with KMS CMK encryption and immutable audit log delivery to CloudWatch. |
| **Information Disclosure (I)** | Leaked AWS IAM long-lived access keys in git repository | Critical | **100% Tokenless / Keyless Architecture**: Zero static AWS credentials; GitHub Actions authenticates via AWS IAM OIDC federation. Pre-commit Gitleaks blocks commits. |
| **Information Disclosure (I)** | Database credentials compromised via environment variables | High | AWS Secrets Manager synced into memory via External Secrets Operator (ESO) using IAM Pod Identity; KMS CMK envelope encryption. |
| **Denial of Service (D)** | Distributed Layer 7 HTTP flood / Slowloris attack | High | AWS WAFv2 rate limiting rule (500 requests / 5 min per IP) + AWS Shield Standard DDOS mitigation at CloudFront edge. |
| **Elevation of Privilege (E)** | Container breakout to host node via root privileges / SSRF | Critical | IMDSv2 enforced with `http_put_response_hop_limit = 1` (blocks SSRF credential theft); `runAsNonRoot: true`, capabilities dropped (`ALL`), `allowPrivilegeEscalation: false`. |
| **Elevation of Privilege (E)** | Lateral movement across Kubernetes namespaces | High | Cilium eBPF L7 NetworkPolicies enforcing default-deny ingress/egress and explicit API path allowlists. |

---

## 3. Residual Risk & Review Cadence

- **Residual Risk Level**: Low / Accepted for lab and staging profiles.
- **Review Frequency**: Quarterly or upon major architecture changes.
- **Automated Verification**: Validated on every pull request via Checkov, Trivy, and simulated attack test suites.
