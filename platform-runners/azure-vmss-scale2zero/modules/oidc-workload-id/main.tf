# ==============================================================================
# Azure Entra ID (Azure AD) Workload Identity Federation for GitHub Actions
# ==============================================================================

# 1. Azure AD Application
resource "azuread_application" "github_actions" {
  display_name = "${var.project_name}-${var.environment}-github-actions-app"
  owners       = [var.owner_object_id != "" ? var.owner_object_id : data.azuread_client_config.current.object_id]
}

data "azuread_client_config" "current" {}

# 2. Service Principal
resource "azuread_service_principal" "github_actions" {
  client_id                    = azuread_application.github_actions.client_id
  app_role_assignment_required = false
  owners                       = [var.owner_object_id != "" ? var.owner_object_id : data.azuread_client_config.current.object_id]
}

# 3. Federated Identity Credential (GitHub Actions OIDC)
resource "azuread_application_federated_identity_credential" "github_branches" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-org-federation"
  description    = "OIDC trust for GitHub Actions workflows in ${var.github_org}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/*"
}

# 4. Role Assignment (Contributor / Scope)
resource "azurerm_role_assignment" "github_actions_role" {
  scope                = var.subscription_scope
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
