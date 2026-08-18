# ==============================================================================
# CloudDevSecOps - Developer Operations & Automation
# ==============================================================================
.PHONY: help init lint checkov tf-init-lab tf-plan-lab tf-apply-lab tf-destroy-lab tf-plan-prod bootstrap-plan bootstrap-apply test-security build-app clean

SHELL := /bin/bash

help: ## Show help screen
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize pre-commit hooks and local dependencies
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@echo "Ready for DevSecOps development!"

lint: ## Run all local security linters (Gitleaks, TFLint, Hadolint)
	@echo "==> Running Gitleaks Secret Detection..."
	@gitleaks detect --verbose || true
	@echo "==> Formatting Terraform..."
	@terraform fmt -recursive
	@echo "==> Linting Dockerfile..."
	@hadolint k8s/apps/secure-api/Dockerfile || true

checkov: ## Run Checkov IaC Security & CIS Benchmark Scanner
	@echo "==> Running Checkov against Terraform configurations..."
	@checkov -d terraform/ --framework terraform --compact --quiet

bootstrap-plan: ## Plan AWS OIDC Provider, S3 State & Budget Guardrail
	@terraform -chdir=terraform/bootstrap init
	@terraform -chdir=terraform/bootstrap plan

bootstrap-apply: ## Apply AWS OIDC Provider, S3 State & Budget Guardrail
	@terraform -chdir=terraform/bootstrap apply -auto-approve

tf-init-lab: ## Initialize Lab Terraform environment
	@terraform -chdir=terraform/environments/lab init

tf-plan-lab: ## Plan Lab infrastructure (< $10/mo cost profile)
	@terraform -chdir=terraform/environments/lab plan

tf-apply-lab: ## Deploy Lab infrastructure to AWS
	@terraform -chdir=terraform/environments/lab apply -auto-approve

tf-destroy-lab: ## Destroy Lab infrastructure to guarantee $0 ongoing cost
	@terraform -chdir=terraform/environments/lab destroy -auto-approve

tf-plan-prod: ## Plan Production enterprise architecture (Multi-AZ EKS, Aurora)
	@terraform -chdir=terraform/environments/prod init
	@terraform -chdir=terraform/environments/prod plan

build-app: ## Build hardened Go microservice container locally
	@docker build -t ghcr.io/quocvand1612/secure-api:latest k8s/apps/secure-api/

test-security: ## Run simulated attack tests (testing Falco & Cilium quarantine)
	@./tests/security/simulate_attack.sh

clean: ## Clean local cache and temporary files
	@find . -type d -name ".terraform" -exec rm -rf {} +
	@find . -name "*.tfstate*" -delete
	@rm -rf sbom/ junit.xml
