# Golden Images for Ephemeral GitHub Actions Runners

Pre-bakes the DevOps/DevSecOps toolchain into the AWS AMI / Azure Managed Image
used by the ephemeral runner pools, so per-job boot time drops from ~3-5 min
(installing everything via `apt-get`/`curl` on every VM) to well under a minute
(just fetch the registration token, `config.sh`, `run.sh`, self-terminate).

## What's baked in
Docker, git, jq, Terraform, tflint, kubectl, Helm, Trivy, Checkov, Semgrep,
cosign, syft, grype, and the GitHub Actions runner binary (pre-extracted,
version-pinned to match `RUNNER_VERSION` in the boot scripts). AWS images also
get `aws-cli v2`; Azure images get `az-cli`.

Provisioning logic lives in one shared script (`scripts/provision-common.sh`)
used by both cloud templates, so the tool set never drifts between clouds.

## Building

```bash
cd packer/aws && packer init . && packer build -var aws_region=ap-southeast-1 runner-ami.pkr.hcl
cd packer/azure && packer init . && packer build -var subscription_id=<sub-id> -var location=eastus runner-image.pkr.hcl
```

AWS build uses the caller's default AWS credential chain (must match the OIDC
role used elsewhere in this repo, or a local profile with EC2/AMI permissions).
Azure build reuses the current `az login` session (`use_azure_cli_auth`) — no
static service-principal secrets, consistent with this repo's OIDC-only rule.

## Rebuild cadence
Rebuild whenever `RUNNER_VERSION` or the tool list changes. Golden images are
named with a build timestamp (`devsecops-runner-golden-{aws,azure}-...`). Set
`use_golden_image=true` for the corresponding Terraform stack to select the
newest image automatically; the default remains the Canonical Ubuntu fallback.
Old images can be pruned manually once no VMSS/ASG instance references them.
