terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.48"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

data "azurerm_client_config" "current" {}

# 1. Resource Group
resource "azurerm_resource_group" "runners_rg" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Role        = "GitHub-Actions-Runners"
    CostProfile = "Scale-to-Zero-Spot"
  }
}

# 2. Key Vault for GitHub Runner Token
resource "random_string" "kv_suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_key_vault" "runners_kv" {
  name                       = "kv-${var.environment}-${random_string.kv_suffix.result}"
  location                   = azurerm_resource_group.runners_rg.location
  resource_group_name        = azurerm_resource_group.runners_rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge"
    ]
  }

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_key_vault_secret" "runner_token" {
  name         = "github-runner-token"
  value        = var.github_runner_token != "" ? var.github_runner_token : "placeholder-token"
  key_vault_id = azurerm_key_vault.runners_kv.id
}

# 3. SSH Key for VMSS admin
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 4. Azure Entra ID Workload Identity Federation (OIDC)
module "oidc" {
  source             = "./modules/oidc-workload-id"
  project_name       = var.project_name
  environment        = var.environment
  github_org         = var.github_org
  subscription_scope = "/subscriptions/${var.subscription_id}"
}

# 5. VMSS Spot Ephemeral Runner (Scale-to-Zero: min=0, instances=0)
module "vmss_runner" {
  source                = "./modules/vmss-runner"
  project_name          = var.project_name
  environment           = var.environment
  location              = var.location
  resource_group_name   = azurerm_resource_group.runners_rg.name
  subscription_id       = var.subscription_id
  vm_sku                = var.vm_sku
  admin_ssh_public_key  = tls_private_key.ssh.public_key_openssh
  github_org            = "${var.github_org}/platform-runners"
  runner_labels         = "self-hosted,azure-spot,linux,x64"
  key_vault_name        = azurerm_key_vault.runners_kv.name
  key_vault_secret_name = azurerm_key_vault_secret.runner_token.name
}

# Grant VMSS System Identity access to Key Vault
resource "azurerm_key_vault_access_policy" "vmss_kv_access" {
  key_vault_id = azurerm_key_vault.runners_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.vmss_runner.vmss_principal_id

  secret_permissions = ["Get"]
}

# 6. Webhook Scaler Function App
module "webhook_scaler" {
  source              = "./modules/webhook-scaler"
  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.runners_rg.name
  subscription_id     = var.subscription_id
  vmss_name           = module.vmss_runner.vmss_name
  webhook_secret      = var.github_webhook_secret
  runner_labels       = "self-hosted,azure-spot"
}
