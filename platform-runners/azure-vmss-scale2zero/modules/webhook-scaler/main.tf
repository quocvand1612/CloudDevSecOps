# ==============================================================================
# Azure Function Webhook Scaler (Scale-to-Zero Controller)
# ==============================================================================

# Dedicated RG for Scaler in region with available Y1 Consumption quota (southeastasia)
resource "azurerm_resource_group" "scaler_rg" {
  name     = "${var.project_name}-${var.environment}-scaler-rg"
  location = var.location

  tags = {
    Environment = var.environment
    Role        = "Webhook-Autoscaler-RG"
  }
}

# Provisioning the Function App alone leaves the endpoint without routes.
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/function_app"
  output_path = "${path.module}/function_app.zip"
}

# 1. Storage Account for Azure Function App
resource "random_id" "storage_suffix" {
  byte_length = 4
}

resource "azurerm_storage_account" "func_storage" {
  name = "scaler${random_id.storage_suffix.hex}sa"

  resource_group_name      = azurerm_resource_group.scaler_rg.name
  location                 = azurerm_resource_group.scaler_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Environment = var.environment
  }
}

# 2. Consumption Service Plan ($0 Idle Cost / 1M Free Executions)
resource "azurerm_service_plan" "func_plan" {
  name                = "${var.project_name}-${var.environment}-func-plan"
  resource_group_name = azurerm_resource_group.scaler_rg.name
  location            = azurerm_resource_group.scaler_rg.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption Plan

  tags = {
    Environment = var.environment
  }
}

# 3. Linux Function App (Python 3.11)
resource "azurerm_linux_function_app" "scaler" {
  name                = "${var.project_name}-${var.environment}-scaler-app"
  resource_group_name = azurerm_resource_group.scaler_rg.name
  location            = azurerm_resource_group.scaler_rg.location

  storage_account_name       = azurerm_storage_account.func_storage.name
  storage_account_access_key = azurerm_storage_account.func_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.func_plan.id
  zip_deploy_file            = data.archive_file.function_zip.output_path

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "AZURE_SUBSCRIPTION_ID"          = var.subscription_id
    "RESOURCE_GROUP_NAME"            = var.resource_group_name
    "VMSS_NAME"                      = var.vmss_name
    "WEBHOOK_SECRET"                 = var.webhook_secret
    "RUNNER_LABELS"                  = var.runner_labels
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "SCALER_PACKAGE_HASH"            = data.archive_file.function_zip.output_base64sha256
  }

  tags = {
    Environment = var.environment
    Role        = "Webhook-Autoscaler"
  }
}

# 4. Grant Function App Managed Identity permission to scale VMSS in runner RG
resource "azurerm_role_assignment" "func_vm_contributor" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_function_app.scaler.identity[0].principal_id
}
