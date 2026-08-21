# ==============================================================================
# CloudDevSecOps - Multi-Cloud Ephemeral Runners & Workload Automation
# ==============================================================================
.PHONY: help init lint fmt runner-aws-init runner-aws-plan runner-aws-apply runner-aws-destroy \
        runner-azure-init runner-azure-plan runner-azure-apply runner-azure-destroy \
        workload-plan-lab workload-apply-lab workload-destroy-lab clean

SHELL := /bin/bash

help: ## Show help screen
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-28s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize pre-commit hooks and local dependencies
	@echo "Installing pre-commit hooks..."
	@pre-commit install || true
	@echo "Ready for DevSecOps development!"

fmt: ## Format all Terraform configurations
	@echo "==> Formatting Terraform across repository..."
	@terraform fmt -recursive

lint: fmt ## Run all local security linters
	@echo "==> Running Gitleaks Secret Detection..."
	@gitleaks detect --verbose || true

# ------------------------------------------------------------------------------
# Platform Runners: AWS EC2 Auto Scaling Group (Scale-to-Zero Spot)
# ------------------------------------------------------------------------------
runner-aws-init: ## Initialize AWS Runner Terraform stack
	@terraform -chdir=platform-runners/aws-asg-scale2zero init

runner-aws-plan: ## Plan AWS Ephemeral Spot Runner Stack (OIDC + ASG + Lambda Scaler)
	@terraform -chdir=platform-runners/aws-asg-scale2zero plan

runner-aws-apply: ## Deploy AWS Ephemeral Spot Runner Stack
	@terraform -chdir=platform-runners/aws-asg-scale2zero apply -auto-approve

runner-aws-destroy: ## Destroy AWS Ephemeral Spot Runner Stack
	@terraform -chdir=platform-runners/aws-asg-scale2zero destroy -auto-approve

# ------------------------------------------------------------------------------
# Platform Runners: Azure VM Scale Sets (Scale-to-Zero Spot in Southeast Asia)
# ------------------------------------------------------------------------------
runner-azure-init: ## Initialize Azure Runner Terraform stack
	@terraform -chdir=platform-runners/azure-vmss-scale2zero init

runner-azure-plan: ## Plan Azure Ephemeral Spot Runner Stack (Entra OIDC + VMSS + Function Scaler)
	@terraform -chdir=platform-runners/azure-vmss-scale2zero plan

runner-azure-apply: ## Deploy Azure Ephemeral Spot Runner Stack
	@terraform -chdir=platform-runners/azure-vmss-scale2zero apply -auto-approve

runner-azure-destroy: ## Destroy Azure Ephemeral Spot Runner Stack
	@terraform -chdir=platform-runners/azure-vmss-scale2zero destroy -auto-approve

# ------------------------------------------------------------------------------
# Workloads Stack (Preserved DevSecOps Core)
# ------------------------------------------------------------------------------
workload-plan-lab: ## Plan Workload Lab infrastructure
	@terraform -chdir=workloads/devsecops-core/terraform/environments/lab init
	@terraform -chdir=workloads/devsecops-core/terraform/environments/lab plan

workload-apply-lab: ## Deploy Workload Lab infrastructure
	@terraform -chdir=workloads/devsecops-core/terraform/environments/lab apply -auto-approve

workload-destroy-lab: ## Destroy Workload Lab infrastructure
	@terraform -chdir=workloads/devsecops-core/terraform/environments/lab destroy -auto-approve

clean: ## Clean local cache and temporary files
	@find . -type d -name ".terraform" -exec rm -rf {} +
	@find . -name "*.tfstate*" -delete
	@rm -rf sbom/ junit.xml
