# Master-Level Cloud DevSecOps & AWS Security Assessment & Complete Answer Key

This document contains **50+ deeply technical, scenario-driven, and architectural questions** alongside **authoritative master-level answers** covering the **CloudDevSecOps** reference platform, AWS Security internals, Kubernetes runtime defense, Cryptography, and Software Supply Chain Security.

---

## 📑 Table of Contents

1. [Identity, Federation & Keyless OIDC (STS, Sigstore, OIDC)](#1-identity-federation--keyless-oidc)
2. [Cryptography, Envelope Encryption & Key Management (KMS, Secrets, Storage)](#2-cryptography-envelope-encryption--key-management)
3. [Network Security, Perimeter Defense & Edge Microsegmentation](#3-network-security-perimeter-defense--edge-microsegmentation)
4. [Container Runtime Defense, Kubernetes & eBPF Security](#4-container-runtime-defense-kubernetes--ebpf-security)
5. [Threat Modeling, Incident Response & SOAR Automation](#5-threat-modeling-incident-response--soar-automation)
6. [Cloud Architecture, FinOps & Multi-Tenancy Governance](#6-cloud-architecture-finops--multi-tenancy-governance)
7. [🎓 Complete Master Answer Key](#-complete-master-answer-key)

---

## 1. Identity, Federation & Keyless OIDC

### Q1.1: OIDC Subject Claim Validation & Cross-Tenant Spoofing Vectors
**Scenario:** In our IAM OIDC trust policy for GitHub Actions, we configured:
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:quocvand1612/CloudDevSecOps:*",
    "repo:quocvand1612@*/CloudDevSecOps@*:*"
  ]
}
```
* **The Question:** Why does GitHub Actions include both repository name and account ID numerical hashes (`@317749204`) in new token versions? What exact cross-account exploit vector opens up if an engineer configures `"token.actions.githubusercontent.com:sub": "*:CloudDevSecOps:*"` instead of anchoring the account username/ID?

---

### Q1.2: Cryptographic Mechanics of Keyless Container Signing (Sigstore / Cosign)
**Scenario:** In workflow `02-build-scan-sign.yml`, we execute:
```bash
cosign sign --yes ghcr.io/quocvand1612/secure-api:latest
```
* **The Question:** No private key or password was provided to Cosign. Detail the exact 5-step cryptographic sequence involving the GitHub Actions OIDC provider, Fulcio Certificate Authority, Rekor Transparency Log, and the OCI Container Registry that makes this signature cryptographically verifiable by third parties without storing a long-lived private key.

---

### Q1.3: STS `AssumeRoleWithWebIdentity` vs. `AssumeRole` Session Boundaries
**Scenario:** GitHub Actions requests credentials directly via AWS STS `AssumeRoleWithWebIdentity` rather than using standard AWS Access Keys.
* **The Question:** How does AWS STS validate the token signature without communicating with GitHub on every single API call? What role does the `.well-known/openid-configuration` and `jwks_uri` play? What is the maximum duration of an assumed session, and how can session tagging (`sts:TagSession`) be leveraged to enforce ABAC (Attribute-Based Access Control) in multi-branch CI/CD?

---

### Q1.4: The 2023 GitHub OIDC Thumbprint Outage & AWS IAM Root CA Validation
**Scenario:** In `terraform/bootstrap/main.tf`, we dynamically query thumbprints via `data.tls_certificate.github_actions`.
* **The Question:** What was the technical root cause of the widespread July 2023 GitHub Actions OIDC outage on AWS? Why did SHA-1 thumbprint pinning fail when GitHub rotated its intermediate TLS certificates? How did AWS modify IAM's backend OIDC validation logic to prevent future thumbprint rotation failures?

---

### Q1.5: Transitive Role Chaining & Privilege Escalation in CI/CD
**Scenario:** An attacker compromises a feature branch in a GitHub repository and can modify `.github/workflows/`.
* **The Question:** If the IAM role assumed by GitHub Actions has `iam:PassRole` permissions on EC2/Lambda roles without `iam:PassedToService` condition constraints, describe the exact step-by-step privilege escalation path the attacker could execute to gain full AdministratorAccess in the AWS account.

---

## 2. Cryptography, Envelope Encryption & Key Management

### Q2.1: Envelope Encryption Internals & Key Hierarchy
**Scenario:** Our RDS PostgreSQL database and EBS volumes are encrypted using a Customer Managed Key (CMK) in AWS KMS.
* **The Question:** Explain the exact mathematical lifecycle of a write operation to an encrypted PostgreSQL tablespace:
  1. How does RDS obtain the Data Encryption Key (DEK)?
  2. Where does the plaintext DEK reside in memory?
  3. Where is the encrypted DEK stored on disk?
  4. Why does AWS KMS never store or log the plaintext DEK?

---

### Q2.2: Annual KMS Key Rotation vs. Data Re-encryption
**Scenario:** `aws_kms_key.primary` has `enable_key_rotation = true` (365-day rotation).
* **The Question:** When AWS KMS automatically rotates key material after 365 days:
  - Why does RDS PostgreSQL **NOT** need to re-encrypt existing gigabytes of table data on disk?
  - How does KMS decrypt historical data blocks written 2 years ago using older key material?
  - What is the difference between *Automatic Key Material Rotation* and *Manual Key Rotation with Key Aliases*?

---

### Q2.3: IAM Database Authentication vs. Secrets Manager Rotation
**Scenario:** Our RDS instance has `iam_database_authentication_enabled = true`.
* **The Question:** 
  1. Contrast the security architecture of IAM Database Authentication with AWS Secrets Manager password rotation.
  2. How does the PostgreSQL server validate an IAM authentication token when PostgreSQL itself does not have native AWS IAM credentials?
  3. Why does IAM DB Auth have a connection rate limit (200 connections/sec) and how do connection pools (e.g., PgBouncer / RDS Proxy) interact with ephemeral tokens?

---

### Q2.4: KMS Key Policy vs. IAM Policy Evaluation Logic
**Scenario:** In `terraform/modules/kms/main.tf`, the key policy contains:
```json
{
  "Sid": "EnableRootPermissions",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::ACCOUNT_ID:root" },
  "Action": "kms:*",
  "Resource": "*"
}
```
* **The Question:** Why is this specific statement mandatory in AWS KMS? What happens if you remove this statement and only grant KMS permissions to IAM roles via standard IAM Policies? What is the dual-evaluation rule in AWS KMS?

---

### Q2.5: High-Entropy Dynamic Passwords vs. Terraform State Exposure
**Scenario:** `terraform/modules/rds-postgres/main.tf` uses `resource "random_password"` with `special = true`.
* **The Question:** While `random_password` eliminates hardcoded plaintext in Git, where does the generated password get stored in plaintext? What specific security controls must be applied to the S3 remote backend bucket, DynamoDB lock table, and CI/CD runner memory to prevent credential harvesting from Terraform state files?

---

## 3. Network Security, Perimeter Defense & Edge Microsegmentation

### Q3.1: CloudFront to ALB Origin Verification Security Limitations
**Scenario:** Our ALB drops direct requests and verifies requests from CloudFront via the `X-Origin-Verify` custom header.
* **The Question:** 
  - What are the architectural attack vectors of using static secret header verification (`X-Origin-Verify`) compared to true mutual TLS (mTLS) or AWS VPC Lattice / PrivateLink?
  - If an attacker discovers the public IP of the ALB (`52.220.104.84`) and guesses or extracts the `X-Origin-Verify` token (e.g., from CloudFront request logs or an SSRF leak), how can they bypass CloudFront WAF entirely?
  - How can you architect a zero-trust origin that makes direct ALB ingress mathematically impossible without mTLS?

---

### Q3.2: `fck-nat` Linux Kernel NAT vs. AWS Managed NAT Gateway
**Scenario:** We replaced the $32/mo AWS Managed NAT Gateway with `fck-nat` running on a Graviton `t4g.nano` Spot instance.
* **The Question:**
  1. What is the fundamental difference in network throughput, connection concurrency, and failover behavior between an EC2 Linux kernel `iptables` NAT router and an AWS Hypervisor-managed NAT Gateway?
  2. What happens to `fck-nat` when the Linux conntrack table (`/proc/sys/net/netfilter/nf_conntrack_max`) is exhausted by a high-frequency outbound microservice?
  3. How does EC2 Spot interruption handling affect outbound egress traffic, and how would you architect an active-active HA `fck-nat` cluster in Terraform?

---

### Q3.3: AWS Transit Gateway (TGW) Appliance Mode in Multi-AZ Security Hubs
**Scenario:** In our Production Architecture (`terraform/environments/prod`), we specify a centralized Inspection VPC with Transit Gateway.
* **The Question:**
  - What is **TGW Appliance Mode**, and why is it strictly required when routing traffic through stateful firewalls/NATs across multiple Availability Zones?
  - Describe the "Asymmetric Routing Problem" that occurs in AWS when Appliance Mode is disabled on VPC attachments.

---

### Q3.4: Network Security Group Chaining & Circular References
**Scenario:** Our security groups are strictly chained:
- `ALB SG` allows 80/443 from allowed client CIDRs.
- `Compute SG` allows port 8080 ONLY from `ALB SG` (`source_security_group_id`).
- `Database SG` allows port 5432 ONLY from `Compute SG`.
* **The Question:**
  1. What happens at the network virtualization layer when an EC2 instance in `Compute SG` is compromised and attempts to connect to another instance in the same `Compute SG`?
  2. Why is referencing Security Group IDs superior to referencing subnet CIDR blocks in Zero-Trust environments?
  3. What is the limit of chained security group rules in AWS and how does cross-account SG referencing work across VPC Peering?

---

### Q3.5: AWS WAFv2 Rule Evaluation Order & Regex Performance Denial of Service (ReDoS)
**Scenario:** Regional WAFv2 is attached to our public ingress.
* **The Question:**
  - In what exact order does AWS WAFv2 process WebACL rules (e.g., Rate Limiting vs IP Whitelisting vs AWS Managed Core Rule Set vs Custom Regex)?
  - How can a malicious actor exploit algorithmic complexity in poorly structured custom regex rules in AWS WAF to cause latency degradation or rule evaluation bypasses?

---

## 4. Container Runtime Defense, Kubernetes & eBPF Security

### Q4.1: IMDSv2 Hop Limit = 1 and SSRF Container Defense
**Scenario:** In `terraform/modules/k3s-lab-node/main.tf`, we enforce:
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
}
```
* **The Question:**
  1. Explain the exact networking difference between standard bridge networking (`cbr0` / container veth pairs) and host networking (`hostNetwork: true`) regarding IP packet TTL.
  2. Why does setting `http_put_response_hop_limit = 1` mathematically prevent a container running inside a Kubernetes pod from obtaining the IMDSv2 token via an SSRF vulnerability in the application?
  3. If an attacker tricks a pod into using `hostNetwork: true`, does Hop Limit = 1 protect the node credentials? Why or why not?

---

### Q4.2: Distroless Non-Root Containers & Linux Capability Dropping
**Scenario:** Our Go microservice uses `gcr.io/distroless/static-debian12:nonroot` with UID 65532 and `capabilities.drop = ["ALL"]`.
* **The Question:**
  - What attack vectors are eliminated by running a distroless container compared to Alpine/Ubuntu base images (e.g., absence of package managers, shells, glibc vulnerabilities)?
  - If a container drops `CAP_NET_RAW`, what specific internal container network attacks (e.g., ARP spoofing, packet sniffing) are prevented?
  - Can a process running as non-root (UID 65532) still exploit a Linux kernel privilege escalation vulnerability (e.g., Dirty COW, Dirty Pipe)? How do `seccompProfile: RuntimeDefault` and AppArmor restrict kernel syscall surface area?

---

### Q4.3: eBPF-Based CNI (Cilium) vs. iptables/Netfilter Performance & Security
**Scenario:** The production architecture deploys Cilium eBPF CNI for Kubernetes networking and security policy.
* **The Question:**
  1. How does Cilium use eBPF programs attached to Linux socket layers (`sockops`) and TC (Traffic Control) hooks to bypass the `kube-proxy` iptables sequential rule traversal?
  2. How does Cilium enforce **Layer 7 HTTP filtering** (e.g., allowing only `GET /healthz` and blocking `POST /admin`) without injecting an intrusive Envoy sidecar proxy into every application pod?
  3. Describe how Cilium's identity-based security policies (`CiliumNetworkPolicy`) prevent IP-spoofing attacks inside a multi-tenant Kubernetes cluster.

---

### Q4.4: Kyverno Admission Control vs. Kubernetes Built-in Pod Security Standards (PSS)
**Scenario:** We enforce security policies using Kyverno Policy-as-Code manifests in `k8s/kyverno/`.
* **The Question:**
  - What are the operational and security differences between Kubernetes native **Pod Security Standards (Privileged / Baseline / Restricted)** and a dynamic Admission Controller like **Kyverno**?
  - What is the security implication of setting Kyverno webhook `failurePolicy: Ignore` vs `failurePolicy: Fail` during a control plane outage or admission webhook timeout?
  - How can Kyverno mutate incoming pods on-the-fly to automatically inject security contexts (e.g., `readOnlyRootFilesystem: true`) without developer intervention?

---

### Q4.5: Falco Runtime Threat Detection & Kernel Probe Evasion
**Scenario:** `k8s/falco/falco-rules.yaml` monitors syscall events across all worker nodes.
* **The Question:**
  1. How does Falco intercept kernel system calls via the eBPF probe driver (`sys_enter_execve`, `sys_enter_openat`, etc.)?
  2. How can an advanced adversary attempt to evade Falco syscall detection using fileless execution techniques (e.g., `memfd_create` + `execveat`, direct shellcode execution in memory without spawning a shell)?
  3. What happens to Falco alert delivery if the kernel ring buffer drops events under a massive burst of process creations?

---

## 5. Threat Modeling, Incident Response & SOAR Automation

### Q5.1: STRIDE Threat Analysis of the CloudDevSecOps Platform
**Scenario:** Review the 3-tier architecture (Edge ➡️ Compute ➡️ RDS).
* **The Question:** Perform a complete **STRIDE** assessment on the Application Load Balancer to Compute Node boundary:
  - **S**poofing: How can an adversary spoof identity between ALB and Compute?
  - **T**ampering: Can HTTP payloads be modified in transit inside the VPC?
  - **R**epudiation: How are administrative database modifications audited?
  - **I**nformation Disclosure: How is sensitive data in transit protected without VPC endpoint encryption?
  - **D**enial of Service: What prevents an attacker from exhausting worker node compute resources?
  - **E**levation of Privilege: What prevents pod escape to the EC2 host?

---

### Q5.2: The Sub-3-Second SOAR Quarantine Loop Architecture
**Scenario:** When a container is compromised, Falco triggers an automated quarantine loop.
* **The Question:**
  1. Walk through the end-to-end data path from the moment an attacker executes `whoami` in a pod:
     `Falco Daemon` ➡️ `EventBridge` ➡️ `SOAR Lambda` ➡️ `Kubernetes API` ➡️ `Cilium BPF Map Update`.
  2. Where can race conditions occur in this pipeline?
  3. If the attacker deletes the Kubernetes API server connection or alters the pod's labels before Lambda acts, how can the SOAR engine guarantee containment at the network/eBPF level?

---

### Q5.3: Volatile Memory Forensics in Ephemeral Cloud Workloads
**Scenario:** A container is quarantined following an alert.
* **The Question:**
  - Standard Kubernetes auto-scaling or pod restarting immediately destroys volatile memory and process artifacts.
  - How would you architect an automated forensic pipeline that captures the container's volatile memory dump (`/proc/$PID/mem`), process namespace, and open network sockets before isolating or terminating the pod?

---

### Q5.4: Supply Chain Compromise: Malicious Dependency in Upstream Base Image
**Scenario:** A legitimate Go module imported by `secure-api` is hijacked on GitHub and updated with a malicious backdoor that executes after a 24-hour delay.
* **The Question:**
  - Which layers of our defense-in-depth pipeline would detect or prevent this attack at each stage:
    1. At Commit Time (Pre-commit)
    2. At Build Time (GitHub Actions CI)
    3. At Admission Time (Kubernetes API)
    4. At Runtime (Compute Node / Falco / Cilium)

---

### Q5.5: Blast Radius Containment of Compromised Compute Node vs. Pod
**Scenario:** An attacker discovers an unpatched Linux kernel vulnerability (e.g., zero-day dirty container escape) and gains root on the EC2 worker node host (`i-01d1755a716e14982`).
* **The Question:**
  1. What AWS resources can the attacker access from the EC2 host given the instance profile `cloud-devsecops-lab-node-profile`?
  2. Can the attacker access the RDS PostgreSQL database directly? (Explain why or why not using Security Group rules and database subnet configurations).
  3. Can the attacker decrypt other customers' data or other S3 buckets in the AWS account? (Explain KMS key policy constraints).

---

## 6. Cloud Architecture, FinOps & Multi-Tenancy Governance

### Q6.1: Multi-Account AWS Organization Architecture vs. Single-Account Isolation
**Scenario:** Our lab is currently in a single AWS account (`033781183622`).
* **The Question:**
  - How would you restructure this architecture into an enterprise **AWS Control Tower / Multi-Account Landing Zone**?
  - Detail the specific dedicated accounts required (e.g., *Log Archive Account, Security Tooling Account, Shared Services Network Hub Account, Core Production Account*).
  - How do **Service Control Policies (SCPs)** enforce security invariants that even an account `AdministratorAccess` user cannot disable?

---

### Q6.2: FinOps Cost Guardrail Watchdog Architecture
**Scenario:** In `scripts/cost_guardrail_watchdog.sh` and `terraform/bootstrap/`, we enforce a $10 budget alarm with automated 50% credit threshold cleanup.
* **The Question:**
  1. Why is relying solely on AWS Budgets SNS notifications insufficient for real-time cost containment during an active cryptomining or DDoS event? (Discuss AWS Cost Explorer data ingestion latency of 8–24 hours).
  2. How would you design a real-time FinOps anomaly detection engine using CloudWatch Metrics, AWS Cost Anomaly Detection, and automated Lambda execution to terminate rogue EC2 Spot instances within 60 seconds of a spend spike?

---

### Q6.3: Terraform State File Concurrency, Lock Contention & Split-Brain Prevention
**Scenario:** In commit `a55f513`, we added `-lock-timeout=60s` and concurrency groups to prevent DynamoDB lock contention in sequential CI/CD.
* **The Question:**
  - What exact DynamoDB table schema (`LockID` string hash key) and atomic conditional write (`attribute_not_exists(LockID)`) mechanism does Terraform use to acquire state locks?
  - What failure mode occurs if a CI/CD runner is forcefully killed by GitHub Actions during `terraform apply`? How does an automated pipeline safely recover from a stale state lock without human intervention or data corruption?

---

### Q6.4: Zero-Downtime Database Migration & Multi-AZ Failover Dynamics
**Scenario:** Upgrading RDS PostgreSQL from version 16.9 to 17.0 in the Production environment.
* **The Question:**
  - Detail the zero-downtime database upgrade strategy using PostgreSQL logical replication or AWS DMS (Database Migration Service).
  - During an automated Multi-AZ failover:
    1. How does AWS Route 53 CNAME updating redirect application traffic from primary to standby?
    2. What happens to inflight transactions and application connection pools during the 15–35 second DNS TTL failover window?
    3. How does AWS RDS Proxy mitigate connection thrashing during database failovers?

---

### Q6.5: Supply Chain Security Level 3 (SLSA) Compliance Verification
**Scenario:** The user wants to audit this repository against the **Supply-chain Levels for Software Artifacts (SLSA) v1.0** framework.
* **The Question:**
  - Assess our current GitHub Actions pipeline (`01-security-lint`, `02-build-scan-sign`, `03-terraform-oidc-deploy`) against the 4 SLSA levels:
    - **Build Level 1**: Scripted build and provenance available.
    - **Build Level 2**: Hosted build service with authenticated provenance (GitHub Actions + Cosign).
    - **Build Level 3**: Hardened build platform preventing insider tampering (Hermetic builds, pinned action SHAs, isolated runners).
  - What specific enhancements are required to elevate our build pipeline to full **SLSA Level 4 / Hermetic Isolation**?

---
---

# 🎓 Complete Master Answer Key

---

### Answer 1.1: OIDC Subject Claim Validation & Cross-Tenant Spoofing Vectors
1. **Why GitHub Actions includes Account Numerical IDs (`@317749204`)**:
   GitHub usernames and organization names are mutable. If user `quocvand1612` deletes or renames their account, an external attacker could immediately register the orphaned username `quocvand1612`, recreate repository `CloudDevSecOps`, and inherit the exact same string claim (`repo:quocvand1612/CloudDevSecOps:ref:refs/heads/main`). By appending the immutable numerical account ID assigned at creation (`@317749204`), GitHub ensures cryptographic uniqueness across account deletions and re-registrations.
2. **The Wildcard Exploit Vector (`"*:CloudDevSecOps:*"`):**
   AWS IAM evaluates `StringLike` wildcards across the entire string. If configured with `*:CloudDevSecOps:*`, any GitHub user globally (e.g., `attacker/CloudDevSecOps` or `evil-corp/CloudDevSecOps-fork`) generating an OIDC token with `sub: repo:attacker/CloudDevSecOps:ref:refs/heads/main` satisfies the condition. The attacker can execute a workflow in their own private repository, call AWS STS `AssumeRoleWithWebIdentity`, and assume the production AWS deployment role, resulting in a full cloud account takeover.

---

### Answer 1.2: Cryptographic Mechanics of Keyless Container Signing (Sigstore / Cosign)
The 5-step keyless cryptographic flow:
1. **OIDC Token Generation**: The GitHub Actions runner requests an ephemeral OIDC IdToken signed by GitHub (`token.actions.githubusercontent.com`) with audience `sigstore`.
2. **Ephemeral Keypair Generation**: Cosign generates an in-memory ECDSA P-256 keypair on the runner. The private key exists strictly in RAM for milliseconds and is never saved to disk.
3. **Fulcio Certificate Authority Exchange**: Cosign submits the public key + OIDC JWT to Fulcio (the Sigstore free CA). Fulcio validates the JWT signature against GitHub's JWKS, extracts verified claims (`issuer`, `repository`, `workflow_ref`), and issues a short-lived (10-minute) X.509 code-signing certificate embedding these claims in the Subject Alternative Name (SAN) extension.
4. **Rekor Transparency Log Entry**: Cosign submits the artifact hash, signature, and Fulcio certificate to Rekor (an immutable, append-only cryptographic Merkle Tree log). Rekor generates a Signed Entry Timestamp (SET) and inclusion proof.
5. **OCI Registry Bundle Publication**: Cosign packages the signature, Fulcio X.509 cert, and Rekor inclusion proof into an OCI image artifact (`.sig` tag) and pushes it to GHCR alongside the container image. Verifiers (e.g. Kyverno) verify the signature using only Fulcio's root CA and Rekor's public key—no private key storage required.

---

### Answer 1.3: STS `AssumeRoleWithWebIdentity` vs. `AssumeRole` Session Boundaries
1. **Signature Validation without Real-Time Callbacks**: AWS STS caches the JSON Web Key Set (JWKS) retrieved from GitHub's OIDC discovery endpoint (`/.well-known/openid-configuration` ➡️ `jwks_uri`). When an incoming JWT arrives, STS decrypts and verifies the RS256 signature locally against the cached public keys in memory in under 2ms.
2. **Session Limits**: Sessions assumed via `AssumeRoleWithWebIdentity` can range from 900 seconds (15 minutes) to 43,200 seconds (12 hours), bounded by the IAM role's `MaxSessionDuration`.
3. **ABAC Role Tagging (`sts:TagSession`)**: OIDC claims can be mapped to transient session tags (e.g., `aws:RequestTag/repo`, `aws:RequestTag/ref`). IAM policies can enforce Attribute-Based Access Control, such as:
   ```json
   "Condition": {
     "StringEquals": { "aws:PrincipalTag/ref": "refs/heads/main" }
   }
   ```
   This restricts write operations strictly to workflows triggered on the `main` branch.

---

### Answer 1.4: The 2023 GitHub OIDC Thumbprint Outage & AWS IAM Root CA Validation
1. **Root Cause**: In July 2023, GitHub rotated the intermediate TLS certificate on `token.actions.githubusercontent.com`. AWS IAM historically required customers to hardcode the SHA-1 thumbprint of the top intermediate certificate. When GitHub rotated its intermediate CA, the thumbprint no longer matched, and AWS STS threw `OpenIDConnect provider HTTPS certificate doesn't match configured thumbprint`, halting CI/CD pipelines worldwide.
2. **AWS Architectural Fix**: AWS updated the IAM OIDC engine to maintain a built-in trust store of verified global Root Certificate Authorities (e.g., DigiCert Global Root CA, Let's Encrypt). For known providers like GitHub, IAM now validates the full TLS certificate chain up to the trusted Root CA, ignoring legacy intermediate thumbprints and eliminating certificate rotation outages permanently.

---

### Answer 1.5: Transitive Role Chaining & Privilege Escalation in CI/CD
1. **Privilege Escalation Path**:
   - The compromised workflow runner creates a new AWS Lambda function (`aws lambda create-function`) containing an administrative payload (e.g., creating a backdoor IAM admin user).
   - The attacker attaches an existing high-privilege IAM role (e.g., `OrganizationAccountAccessRole` or `AdministratorAccess` role) to the Lambda using `iam:PassRole`.
   - The attacker invokes the Lambda (`aws lambda invoke`), executing code with administrative permissions.
2. **Remediation**:
   - Enforce `iam:PassedToService` condition:
     ```json
     "Condition": { "StringEquals": { "iam:PassedToService": "lambda.amazonaws.com" } }
     ```
   - Explicitly constrain `Resource` ARNs in `iam:PassRole` to only low-privilege service roles rather than `*`.

---

### Answer 2.1: Envelope Encryption Internals & Key Hierarchy
1. **DEK Generation**: RDS requests a Data Encryption Key from AWS KMS via `kms:GenerateDataKey(KeyId=CMK_ARN, KeySpec=AES_256)`.
2. **Plaintext vs. Ciphertext DEK**: KMS returns two values:
   - `Plaintext DEK`: 256-bit AES key held temporarily in EC2 hypervisor/database engine volatile memory (RAM) to perform AES-GCM block encryption on data writes.
   - `Ciphertext DEK`: Encrypted under the KMS CMK, saved directly in the EBS/tablespace volume header on disk.
3. **Memory Sanitization**: When the volume unmounts or DB shuts down, the plaintext DEK is securely zeroed from RAM.
4. **Why KMS Never Stores Plaintext DEKs**: KMS is an HSM-backed key management service, not a storage engine. It protects the CMK in hardware security modules (FIPS 140-3 Level 3) and offloads data encryption to client services, achieving high throughput without KMS API bottlenecking.

---

### Answer 2.2: Annual KMS Key Rotation vs. Data Re-encryption
1. **Why Re-Encryption Is Not Needed**: Under envelope encryption, table data is encrypted with Data Encryption Keys (DEKs), not directly with the CMK. The CMK only encrypts the DEKs.
2. **Historical Decryption**: When KMS rotates key material, it assigns a new key material version (`Version 2`). The previous key material (`Version 1`) is preserved in the HSMs in read-only/decrypt-only mode. When decrypting a historical block, KMS reads the key version metadata in the ciphertext DEK header and routes the operation to Version 1 key material.
3. **Automatic vs. Manual Key Rotation**:
   - *Automatic Rotation*: Rotates backing key material under the same Key ARN every 365 days with zero application or Terraform changes.
   - *Manual Rotation*: Creates a new `aws_kms_key` resource (new Key ARN) and updates Key Aliases (`alias/app-key`). Applications referencing raw Key ARNs must be manually updated.

---

### Answer 2.3: IAM Database Authentication vs. Secrets Manager Rotation
1. **Comparison**:
   - *Secrets Manager*: Static credentials stored in an encrypted vault. Rotation Lambda executes `ALTER USER` and updates the vault; applications must reload passwords.
   - *IAM DB Auth*: Zero passwords. Applications use AWS STS credentials to generate a short-lived (15-minute) signed SigV4 authorization token passed as the database password.
2. **Validation Mechanism**: RDS PostgreSQL runs an internal AWS PAM plugin (`rds_iam`). When a connection arrives, PostgreSQL passes the token to the local RDS authentication daemon, which validates the SigV4 cryptographic signature against STS without storing passwords in the database catalog.
3. **Connection Limits & Pooling**: IAM DB Auth is CPU-intensive (cryptographic signature verification per handshake) and capped at 200 connections/sec. Production architectures must place **AWS RDS Proxy** or **PgBouncer** in front to maintain pooled, persistent backend connections while authenticating clients.

---

### Answer 2.4: KMS Key Policy vs. IAM Policy Evaluation Logic
1. **Why the Root Statement is Mandatory**: AWS KMS uses a dual-evaluation model. A KMS key policy is the primary authorization boundary. By default, IAM policies have **zero effect** on KMS keys unless the Key Policy explicitly delegates access to the account via `Principal: { "AWS": "arn:aws:iam::ACCOUNT_ID:root" }`.
2. **Risk of Removal**: If the root statement is removed and the key policy only references a specific IAM role that is subsequently deleted, the KMS key becomes an **orphaned key**—permanently un-decryptable and un-deletable even by the AWS Account Root user without AWS Support intervention.

---

### Answer 2.5: High-Entropy Dynamic Passwords vs. Terraform State Exposure
1. **Plaintext Storage**: `random_password` stores generated passwords in plaintext inside the `terraform.tfstate` JSON file.
2. **Mandatory State Security Controls**:
   - *S3 Server-Side Encryption*: Enforce `aws:kms` encryption with a Customer Managed Key.
   - *Bucket Policy TLS Invariant*: Deny all `s3:*` actions where `aws:SecureTransport == false`.
   - *Least Privilege IAM*: Only the GitHub Actions OIDC role ARN may access the state bucket.
   - *DynamoDB Encryption*: Enable KMS encryption and point-in-time recovery on the state lock table.
   - *Ephemeral Runner Hygiene*: Runners must wipe workspace directories upon completion.

---

### Answer 3.1: CloudFront to ALB Origin Verification Security Limitations
1. **Limitations of `X-Origin-Verify`**: It is a shared static secret (bearer token). It does not provide cryptographic mutual authentication, client identity proof, or replay protection.
2. **Bypass Vector**: If an attacker discovers the ALB public IP and extracts the header value (via log leak, GitHub Actions leak, or SSRF in a backend service that reflects request headers), they can send direct HTTP requests with `X-Origin-Verify: <secret>` straight to the ALB, bypassing CloudFront WAF rate limiting, geo-blocking, and bot mitigation.
3. **Zero-Trust Alternatives**:
   - *VPC PrivateLink & Internal ALB*: Make the ALB completely private (no public IPs). CloudFront connects to the VPC via CloudFront VPC Origins (PrivateLink) directly into private subnets.
   - *ALB mTLS / Client Certificate Authentication*: Configure ALB with mutual TLS requiring CloudFront client certificates.
   - *AWS Prefix Lists*: Restrict ALB security group ingress strictly to the `com.amazonaws.global.cloudfront.origin-facing` managed prefix list.

---

### Answer 3.2: `fck-nat` Linux Kernel NAT vs. AWS Managed NAT Gateway
1. **Differences**: AWS Managed NAT Gateway is a distributed, multi-AZ, serverless hypervisor NAT scaling up to 100 Gbps automatically with built-in AWS fault tolerance. `fck-nat` is a single EC2 instance limited by instance network bandwidth (e.g. up to 5 Gbps on `t4g.nano`) and CPU.
2. **Conntrack Exhaustion**: Linux `netfilter` tracks every active TCP/UDP connection in `/proc/net/nf_conntrack`. When `nf_conntrack_max` is reached (default ~65k-262k entries depending on RAM), the kernel drops all new SYN packets with `nf_conntrack: table full, dropping packet`, causing total egress outage for all private compute pods.
3. **Spot Interruption & HA**: Spot instances receive a 2-minute termination notice. In a production HA setup: run 2 `fck-nat` instances in separate AZs, deploy an AWS Lambda / CloudWatch event rule on Spot interruption to re-point the VPC Route Table `0.0.0.0/0` to the standby ENI in <5 seconds.

---

### Answer 3.3: AWS Transit Gateway (TGW) Appliance Mode in Multi-AZ Security Hubs
1. **What Appliance Mode Does**: Ensures that for a given bidirectional TCP flow between two VPCs traversing a central Inspection VPC, both the forward (SYN) and reverse (SYN-ACK) packets are routed through the *same* Availability Zone's inspection appliance (firewall/NAT).
2. **The Asymmetric Routing Problem**: Without Appliance Mode, AWS TGW uses round-robin / hash-based routing per AZ. Inbound traffic from AZ-A might hit Firewall-A in the Hub VPC, but return traffic from the database in AZ-B might be routed to Firewall-B. Because stateful firewalls track TCP handshake state, Firewall-B drops the SYN-ACK packet because it never saw the initial SYN, breaking connections.

---

### Answer 3.4: Network Security Group Chaining & Circular References
1. **Intra-SG Isolation**: In AWS, membership in a Security Group does NOT automatically allow traffic between instances in that SG unless a self-referencing rule (`source = sg-compute`) is explicitly added. Without it, compromised compute node A cannot communicate with compute node B on any port.
2. **SG ID vs Subnet CIDR**: Subnet CIDR rules allow any IP in the subnet (including future rogue instances, rogue Lambda ENIs, or compromised endpoints). SG IDs are dynamic cryptographic tags evaluated by the AWS Nitro hypervisor at the ENI level, ensuring only authorized instances can communicate regardless of IP changes.
3. **Cross-VPC & Limits**: Chained SG referencing works across VPC Peering connections within the same region. Rule limits: default 60 inbound/outbound rules per SG, max 5 SGs per ENI.

---

### Answer 3.5: AWS WAFv2 Rule Evaluation Order & Regex Performance Denial of Service (ReDoS)
1. **Processing Order**: Evaluated sequentially by Rule Priority (lowest integer first).
   - *Terminating Actions* (`BLOCK`, `ALLOW`): Halts further evaluation immediately.
   - *Non-Terminating Actions* (`COUNT`, `CAPTCHA` on pass): Continues evaluation.
   - Standard best practice: IP Whitelist/Blocklist (Priority 1) ➡️ Rate Limiting (Priority 2) ➡️ AWS Managed Rules / OWASP CRS (Priority 3) ➡️ Custom App Regex (Priority 4).
2. **ReDoS & Inspection Limits**: Complex nested backtracking regexes (e.g. `(a+)+$`) cause catastrophic exponential backtracking in regex engines, causing WAF evaluation timeouts. Additionally, AWS WAF historically inspects only the first 8 KB / 16 KB / 64 KB of request body. Attackers can pad requests with junk data to push SQLi/XSS payloads beyond the inspection threshold (Body Truncation Bypass).

---

### Answer 4.1: IMDSv2 Hop Limit = 1 and SSRF Container Defense
1. **Bridge vs. Host Networking TTL**:
   - *Bridge Networking*: Containers communicate across a virtual Ethernet bridge (`cbr0`). When a packet crosses the Linux network namespace boundary from container `veth` to host `cbr0`, the Linux IP stack decrements the IPv4 Time-To-Live (TTL) by 1.
   - *Host Networking*: The pod shares the host's root network namespace (`netns`). Packets originate with default host TTL without crossing a bridge.
2. **Why Hop Limit = 1 Blocks Container SSRF**:
   - The EC2 Metadata Service is a link-local address (`169.254.169.254`).
   - When `http_put_response_hop_limit = 1`, the IMDS daemon sets the IP TTL of the response token packet to 1.
   - When the response packet attempts to cross from host back into the container's bridge network namespace, the kernel decrements TTL from 1 to 0 and drops the packet (`TTL expired in transit`). The container never receives the IMDSv2 token!
3. **HostNetwork Vulnerability**: If a rogue pod sets `hostNetwork: true`, it bypasses the bridge entirely; packets do not decrement TTL, allowing the pod to steal node credentials. Kyverno must strictly disallow `hostNetwork: true`.

---

### Answer 4.2: Distroless Non-Root Containers & Linux Capability Dropping
1. **Distroless Elimination**: Eliminates package managers (`apt`, `apk`), system shells (`/bin/sh`, `/bin/bash`), and common utilities (`curl`, `wget`, `nc`). An attacker achieving Remote Code Execution (RCE) cannot spawn a reverse shell or download malware via shell commands.
2. **Dropping `CAP_NET_RAW`**: Prevents crafting raw IP packets, executing ARP spoofing, ICMP redirect attacks, or running network sniffers (`tcpdump`) inside the pod network namespace.
3. **Kernel Privilege Escalation**: Even non-root (UID 65532) shares the host Linux kernel. Exploits like Dirty Pipe exploit kernel write primitives via syscalls. `seccompProfile: RuntimeDefault` blocks high-risk syscalls (`ptrace`, `bpf`, `kexec_load`, `mount`), closing kernel attack vectors before exploitation occurs.

---

### Answer 4.3: eBPF-Based CNI (Cilium) vs. iptables/Netfilter Performance & Security
1. **iptables Sequential Traversal vs. eBPF**: `kube-proxy` in iptables mode evaluates $O(N)$ sequential rules for $N$ services. Cilium attaches eBPF programs directly to network interface hooks (XDP/tc) and socket operations (`sockops`), performing $O(1)$ hash table lookups in BPF maps, eliminating netfilter conntrack overhead.
2. **In-Kernel L7 Filtering**: Cilium parses HTTP headers directly in the Linux kernel via eBPF stream parsers (sockmap/sk_msg) or selectively redirects only L7-inspected traffic to an embedded in-kernel Envoy proxy without requiring a per-pod sidecar.
3. **Identity-Based Security**: Cilium assigns a numeric Security Identity to pods based on Kubernetes labels. Network packets are tagged with this identity in the eBPF packet metadata, preventing IP spoofing because policy enforcement evaluates cryptographic eBPF endpoint identity rather than mutable pod IP addresses.

---

### Answer 4.4: Kyverno Admission Control vs. Kubernetes Built-in Pod Security Standards (PSS)
1. **PSS vs. Kyverno**: PSS is a static, namespace-level Kubernetes feature with 3 fixed profiles (Privileged, Baseline, Restricted). Kyverno is a dynamic, declarative Policy-as-Code engine supporting fine-grained validation, mutation, generation, and image signature verification (Cosign).
2. **`failurePolicy: Ignore` vs. `Fail`**: `Ignore` allows pods to be scheduled even if Kyverno webhook is down (availability over security - risk of unvalidated malicious pods bypassing controls). `Fail` rejects all pod admissions if Kyverno is unresponsive (security over availability).
3. **Dynamic Mutation**: Kyverno uses `mutate` rules with JSON patches or overlays to automatically inject `securityContext: { readOnlyRootFilesystem: true, runAsNonRoot: true }` into Pod specs during admission before passing them to the etcd datastore.

---

### Answer 4.5: Falco Runtime Threat Detection & Kernel Probe Evasion
1. **Syscall Interception**: Falco's eBPF probe hooks into the Linux kernel tracepoints (`raw_syscalls:sys_enter` and `raw_syscalls:sys_exit`). Every syscall with its arguments and process context is pushed to a shared lockless kernel ring buffer read by the user-space Falco daemon.
2. **Fileless Evasion**: Attackers allocate anonymous memory via `memfd_create()`, write an ELF binary into memory, and execute it via `fexecve()` or `execveat()`. If Falco rules only monitor `sys_enter_execve` on disk paths, memory execution goes undetected. Mitigation requires monitoring `execveat` and `memfd_create` syscalls.
3. **Ring Buffer Drops**: Under massive syscall bursts, the ring buffer overflows, resulting in dropped events. Falco exports Prometheus metrics (`falco_ring_buffer_drops_total`) to trigger alerts when monitoring coverage degrades.

---

### Answer 5.1: STRIDE Threat Analysis of the CloudDevSecOps Platform
- **Spoofing**: Attacker spoofs client IP or impersonates compute node. Mitigated by ALB X-Forwarded-For validation, IMDSv2, and chained Security Groups.
- **Tampering**: Attacker intercepts intra-VPC packets. Mitigated by AWS Nitro intra-VPC hardware encryption (automatically encrypts traffic between Nitro instances with no performance penalty) and TLS 1.3.
- **Repudiation**: Malicious database updates. Mitigated by CloudTrail API logs, RDS Enhanced Monitoring, PostgreSQL `pgaudit` logging, and immutable S3 state logs.
- **Information Disclosure**: Data leak from unencrypted disk/memory. Mitigated by KMS CMK storage encryption, Secrets Manager dynamic generation, and IAM token authentication.
- **Denial of Service**: Resource exhaustion. Mitigated by WAF rate limits (500 req/5m), ALB connection limits, Kubernetes CPU/Memory requests/limits, and horizontal pod autoscaling.
- **Elevation of Privilege**: Container breakout. Mitigated by Distroless non-root UID 65532, read-only rootfs, dropped capabilities, Seccomp runtime defaults, and IMDSv2 hop limit 1.

---

### Answer 5.2: The Sub-3-Second SOAR Quarantine Loop Architecture
1. **Data Pipeline**: Falco detects interactive shell ➡️ outputs JSON alert to stdout/gRPC ➡️ Falcosidekick publishes to AWS EventBridge default bus ➡️ EventBridge pattern rule triggers SOAR Lambda ➡️ Lambda uses Kubernetes API / Cilium API to apply `quarantine: "true"` label ➡️ Cilium BPF map updates endpoint policy, dropping all non-quarantine network packets at the TC layer in <3 seconds.
2. **Race Conditions**: Compromised container deletes Kubernetes API connectivity, kills logging agent, or renames process.
3. **Tamper-Proof Containment**: Because Cilium enforces policy in the Linux kernel via eBPF on the worker node host, a compromised container *cannot* modify host BPF maps from inside the container namespace. Lambda can also revoke node instance credentials via AWS IAM / Security Group detachment if Kubernetes API is unresponsive.

---

### Answer 5.3: Volatile Memory Forensics in Ephemeral Cloud Workloads
1. **Namespace Freeze**: Lambda or agent sends SIGSTOP or freezes the container cgroup via `/sys/fs/cgroup/unified/.../cgroup.freeze` to halt memory modifications.
2. **Memory Dump**: Agent executes `gcore` or reads `/proc/$PID/mem` directly from the host OS, streaming the memory image to an encrypted S3 forensic bucket.
3. **Disk Snapshot**: Call AWS EC2 `CreateSnapshot` on the worker node's EBS root volume with tag `ForensicEvidence=true`.
4. **Network Capture**: Export active Cilium network conntrack table and tcpdump pcap buffers.
5. **Isolate**: Apply quarantine network policy.

---

### Answer 5.4: Supply Chain Compromise: Malicious Dependency in Upstream Base Image
1. **Pre-Commit**: Gitleaks detects embedded malicious API tokens/keys; Trivy/govulncheck detects known CVEs in the dependency hash.
2. **CI Build**: Syft generates SBOM (SPDX/CycloneDX); Trivy scans container filesystem; Cosign signs image with provenance attestation.
3. **Admission**: Kyverno verifies Cosign signature against Sigstore transparency log; blocks image if unverified.
4. **Runtime**: Falco detects unauthorized outbound network connection or file access attempts (`/etc/shadow`, `/var/run/secrets`); Cilium egress policy drops unauthorized egress traffic to unknown C2 IP addresses; EventBridge triggers SOAR quarantine.

---

### Answer 5.5: Blast Radius Containment of Compromised Compute Node vs. Pod
1. **Node IAM Permissions**: Restricted strictly to SSM management (`AmazonSSMManagedInstanceCore`) and pulling images from ECR. No access to KMS admin, IAM modification, or other S3 buckets.
2. **RDS Access**: Node is in `Compute SG` and private compute subnet. It *can* reach port 5432 on RDS PostgreSQL, but requires database credentials or an IAM auth token. It cannot route to external networks except through `fck-nat`.
3. **Other Tenant Data**: KMS CMK Key Policy strictly scopes decryption to specific resource ARNs. The instance profile has no `kms:Decrypt` permission on other keys or account S3 state buckets.

---

### Answer 6.1: Multi-Account AWS Organization Architecture vs. Single-Account Isolation
1. **Dedicated Account Slices**:
   - *Management / Billing Account*: AWS Organizations, SCPs, consolidated billing.
   - *Log Archive Account*: Centralized S3 bucket with Object Lock for all CloudTrail, VPC Flow Logs, and GuardDuty findings.
   - *Security Tooling Account*: Centralized Security Hub, GuardDuty master, AWS IAM Identity Center.
   - *Network Hub Account*: AWS Transit Gateway, AWS Network Firewall / Inspection VPC, Centralized Ingress/Egress.
   - *Application Workload Accounts* (Dev, Staging, Prod): Isolated VPCs attached to TGW with zero inter-environment access.
2. **Service Control Policies (SCPs)**: Enforce guardrails (e.g. deny `cloudtrail:StopLogging`, deny disabling GuardDuty, deny unencrypted EBS volumes, deny regions other than `ap-southeast-1`). SCPs override even root / AdministratorAccess in member accounts.

---

### Answer 6.2: FinOps Cost Guardrail Watchdog Architecture
1. **Cost Explorer Latency**: AWS Cost Explorer and AWS Budgets ingest billing data with an 8-24 hour batch delay, meaning a compromised account spinning up 100 GPU instances could incur thousands of dollars before a Budget alarm fires.
2. **Real-Time Engine**:
   - *CloudWatch Metric Alarms*: Monitor EC2 running instance counts (`EC2:RunningInstances`), network bytes out, and CPU utilization aggregated per minute.
   - *AWS CloudTrail + EventBridge*: EventBridge rule matching `RunInstances`, `CreateCluster`, or `AuthorizeSecurityGroupIngress`.
   - *Lambda Circuit Breaker*: Lambda evaluates instance type against an approved whitelist (e.g. only `t4g.*` allowed in Lab). If unauthorized instance types or count > threshold, Lambda immediately issues `ec2:TerminateInstances` and sends high-priority PagerDuty/SNS alerts in <60 seconds.

---

### Answer 6.3: Terraform State File Concurrency, Lock Contention & Split-Brain Prevention
1. **DynamoDB Schema**: Table has hash key `LockID` (string, e.g. `<bucket-name>/<state-path>-md5`).
2. **Atomic Write**: When acquiring a lock, Terraform executes `PutItem` with condition expression `attribute_not_exists(LockID)`. If another runner holds the lock, DynamoDB returns `ConditionalCheckFailedException`.
3. **Force Kill / Stale Lock**: If a runner is killed abruptly, the lock record remains in DynamoDB. Recovery requires executing `terraform force-unlock <LOCK_ID>`. In CI/CD, running with `-lock-timeout=60s` allows sequential pipeline stages to wait for transient lock releases automatically without failing.

---

### Answer 6.4: Zero-Downtime Database Migration & Multi-AZ Failover Dynamics
1. **Zero-Downtime Major Upgrade**: Use PostgreSQL Logical Replication / AWS DMS to replicate data from v16 to a standalone v17 instance in real-time. Once replication lag is 0, switch application DNS/endpoint to v17 with seconds of read-only downtime.
2. **Multi-AZ Failover Mechanics**:
   - Primary database crashes or AZ fails.
   - RDS monitoring detects failure, flips synchronous replication standby in AZ-B to primary.
   - AWS Route 53 updates the CNAME of the database endpoint to point to the new primary IP address (propagation takes 15–35 seconds).
   - Inflight transactions abort and throw connection errors; connection pools must reconnect.
   - *RDS Proxy Solution*: Sits between microservices and PostgreSQL. During failover, RDS Proxy holds incoming SQL queries in queue and seamlessly routes them to the new primary without terminating client application connections, cutting failover disruption time from 35s to <3s.

---

### Answer 6.5: Supply Chain Security Level 3 (SLSA) Compliance Verification
1. **Current SLSA Level**: Meets **SLSA Build Level 2** (Hosted GitHub Actions runner, authenticated provenance via Cosign + OIDC Sigstore, software bill of materials via Syft, pinned commit SHAs).
2. **Elevation to SLSA Level 3 & 4 (Hermetic Isolation)**:
   - *Hermetic Builds*: Build container images in isolated network environments where build tools cannot download unvetted remote dependencies during compilation (pre-fetch all Go dependencies into vendor directory with cryptographic checksum verification `go.sum`).
   - *Ephemeral Isolated Runners*: Run builds on dedicated, hardened, ephemeral Kubernetes runners (e.g., GitHub Actions Runner Controller - ARC) with no persistent state.
   - *Signed In-Toto Attestations*: Generate cryptographically signed SLSA provenance attestations capturing full commit SHA, build parameters, builder identity, and input artifact digests, verified by Kyverno before deployment.
