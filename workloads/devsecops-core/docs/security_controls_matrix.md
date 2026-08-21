# Security Controls Matrix & Compliance Mapping

This matrix maps the security controls implemented in **CloudDevSecOps** against industry-standard frameworks: **CIS AWS Foundations Benchmark v3.0**, **NIST Cybersecurity Framework (CSF)**, and the **OWASP Top 10**.

---

## 1. Regulatory & Framework Crosswalk

| Security Domain | Control Description | CIS AWS v3.0 | NIST CSF | OWASP Top 10 | Implementation in Code |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Identity & Access** | Tokenless CI/CD via IAM OIDC Web Identity Federation | 1.16, 1.17 | PR.AC-1 | A07:2021 (Auth Failures) | `terraform/bootstrap/main.tf` |
| **Identity & Access** | Zero static credentials on compute nodes (SSM / IRSA) | 1.18 | PR.AC-4 | A01:2021 (Broken Access) | `terraform/modules/k3s-lab-node` |
| **Data Protection** | KMS Customer Managed Keys with auto-rotation | 3.8, 3.9 | PR.DS-1 | A02:2021 (Cryptographic Failures) | `terraform/modules/kms` |
| **Data Protection** | S3 State Bucket TLS 1.2+ Enforced & Public Block | 2.1.1, 2.1.2 | PR.DS-2 | A05:2021 (Security Misconfig) | `terraform/bootstrap/main.tf` |
| **Network Security** | Multi-tier VPC with Isolated Data Subnets (No IGW) | 5.1, 5.2 | PR.PT-4 | A01:2021 (Broken Access) | `terraform/modules/vpc` |
| **Network Security** | CloudFront Origin Secret Header (`X-Origin-Verify`) | - | PR.PT-4 | A05:2021 (Security Misconfig) | `terraform/modules/cloudfront-waf` |
| **Network Security** | Cilium eBPF L7 Ingress/Egress Network Policies | - | PR.PT-4 | A01:2021 (Broken Access) | `k8s/cilium/cilium-network-policy.yaml` |
| **Workload Hardening** | Pod Security Standard Restricted (Non-root, read-only rootfs) | - | PR.IP-1 | A04:2021 (Insecure Design) | `k8s/kyverno/policy-admission-rules.yaml` |
| **Workload Hardening** | IMDSv2 Hop Limit 1 (Anti-SSRF Protection) | - | PR.IP-1 | A10:2021 (SSRF) | `terraform/modules/k3s-lab-node` |
| **Supply Chain** | Keyless Container Signing with Cosign & Rekor log | - | PR.DS-6 | A08:2021 (Software Integrity) | `.github/workflows/02-build-scan-sign.yml` |
| **Supply Chain** | SBOM Generation with Syft (CycloneDX / SPDX) | - | ID.RA-1 | A06:2021 (Vulnerable Components) | `.github/workflows/02-build-scan-sign.yml` |
| **Threat Detection** | Falco eBPF Kernel Anomaly & Shell Detection | - | DE.CM-1 | A09:2021 (Logging Failures) | `k8s/falco/falco-rules.yaml` |
| **Automated Response**| SOAR EventBridge -> Lambda Pod Quarantine | - | RS.RP-1 | - | `terraform/modules/soar-remediation` |
| **FinOps Guardrails** | Infracost PR estimation + AWS Budget $10 Alarm | - | ID.BE-5 | - | `terraform/bootstrap/main.tf` |
