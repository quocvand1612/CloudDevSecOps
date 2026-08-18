# Incident Response Runbook: Compromised Container Workload

**Severity**: High / Critical  
**Target Audience**: Security Operations, DevSecOps Engineers, Incident Responders

---

## 1. Overview & Trigger Conditions
This runbook triggers when:
- **Falco eBPF** detects unexpected shell execution or privilege escalation inside a workload pod (`Terminal Shell Spawned in Restricted Container`).
- **AWS GuardDuty** flags anomalous network beaconing or runtime behavior from the compute tier.
- An alert is pushed via **AWS EventBridge** to the automated SOAR Lambda function.

---

## 2. Automated Containment (Phase 1 - Immediate)
The automated SOAR Lambda function automatically performs initial containment:
1. **Network Isolation**: Labels the affected pod with `quarantine: "true"`.
2. **Cilium Network Policy Trigger**: Activates `incident-auto-quarantine-policy`, instantly cutting all ingress and egress traffic to the container.
3. **Forensic Log Snapshot**: Preserves container stdout/stderr logs and eBPF syscall telemetry in CloudWatch.

---

## 3. Manual Investigation & Triage (Phase 2)

### Step 3.1: Verify Quarantined Workload Status
```bash
# Check pod status and quarantine label
kubectl get pods -n prod-workload -l quarantine=true

# Inspect pod network policies
cilium endpoint list
```

### Step 3.2: Inspect Syscall & Process Logs
```bash
# View CloudWatch logs for the incident timestamp
aws logs filter-log-events \
  --log-group-name "/aws/events/security-findings" \
  --filter-pattern "CRITICAL"
```

### Step 3.3: Dump Container Forensic Memory / Artifacts
If non-ephemeral evidence is required:
```bash
# Take EBS snapshot of the host instance via SSM
aws ec2 create-snapshot \
  --volume-id <vol-id> \
  --description "Forensic snapshot of compromised instance"
```

---

## 4. Remediation & Recovery (Phase 3)

1. **Terminate Malicious Pod**:
   ```bash
   kubectl delete pod <compromised-pod-name> -n prod-workload
   ```
2. **Patch Root Cause**:
   - Verify if attack vector was an unpatched dependency (check Trivy CVE scan reports).
   - Verify if Kyverno admission policy was bypassed or misconfigured.
3. **Re-deploy Verified Artifact**:
   - Trigger `.github/workflows/02-build-scan-sign.yml` to produce a signed, freshly scanned release.
4. **Post-Mortem**:
   - Update `docs/threat_model.md` and add relevant Falco detection rules to prevent recurrence.
