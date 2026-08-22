# Repository Guidelines

## Project Structure & Module Organization

- `terraform/` contains the core AWS DevSecOps infrastructure, organized by reusable `modules/` and environment directories.
- `workloads/devsecops-core/` contains the workload Terraform, stage-verification shell tests, and operational documentation.
- `platform-runners/aws-asg-scale2zero/` provisions ephemeral GitHub runners with an ASG, Lambda webhook scaler, and OIDC.
- `platform-runners/azure-vmss-scale2zero/` provides the Azure VMSS/Function App equivalent. Keep provider-specific logic inside its module.
- `platform-runners/packer/` holds runner-image build material. GitHub Actions workflows live in `.github/workflows/`.

## Build, Test, and Development Commands

Run `make help` to list supported commands. Common commands:

```bash
make fmt                 # terraform fmt -recursive
make lint                # format, then Gitleaks detection
make runner-aws-init     # initialize AWS runner Terraform
make runner-aws-plan     # review AWS runner changes
make runner-azure-plan   # review Azure runner changes
make workload-plan-lab   # initialize and plan the lab workload
```

Use `terraform -chdir=<stack> validate` before a plan. Never run `apply` or `destroy` casually: these commands modify billable cloud resources. Use `TF_VAR_*` environment variables for sensitive Terraform inputs; do not place secrets in `.tfvars` files or command-line `-var` flags.

## Coding Style & Naming Conventions

Use `terraform fmt` formatting (two-space HCL indentation) and keep resources narrowly scoped. Name Terraform resources with descriptive snake_case; use existing provider naming patterns such as `devsecops-runners-<environment>-...` for cloud resource names. Python uses four spaces, `snake_case` functions, and standard-library logging. Shell scripts should use `#!/usr/bin/env bash` or `#!/bin/bash`, `set -euo pipefail` where compatible, and quote variables.

## Testing Guidelines

Run formatting and validation first, then a Terraform plan for every affected stack. Workload checks are executable shell scripts under `workloads/devsecops-core/tests/stages/` (for example, `01_verify_foundation.sh`). For runner changes, test one workflow at a time and confirm the ASG/VMSS returns to zero after completion. Do not use production credentials or print webhook secrets, Function keys, registration tokens, or storage connection strings.

## Commit & Pull Request Guidelines

Follow the existing Conventional Commit pattern: `fix(azure-runner): ...`, `feat(azure): ...`, `fix(terraform): ...`. Keep commits focused by stack. PRs should describe the infrastructure impact, include the relevant `terraform plan`/test evidence, link the issue when available, and call out cost, security, state, or rollback implications. Never commit Terraform state, generated credentials, or cloud access artifacts.
