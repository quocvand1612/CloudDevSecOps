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

locals {
  federated_subjects = {
    "runners-main" = "repo:${var.github_org}/platform-runners:ref:refs/heads/main"
    "runners-pr"   = "repo:${var.github_org}/platform-runners:pull_request"
    "aws-sec-main" = "repo:${var.github_org}/AWS-DevSecOps:ref:refs/heads/main"
    "aws-sec-pr"   = "repo:${var.github_org}/AWS-DevSecOps:pull_request"
    "legacy-main"  = "repo:quocvand1612/CloudDevSecOps:ref:refs/heads/main"
  }
}

# 3. Federated Identity Credentials (GitHub Actions OIDC)
resource "azuread_application_federated_identity_credential" "github_branches" {
  for_each       = local.federated_subjects
  application_id = azuread_application.github_actions.id
  display_name   = "gh-${each.key}"
  description    = "OIDC trust for ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value
}

# 4. Role Assignment (Contributor / Scope)
resource "azurerm_role_assignment" "github_actions_role" {
  scope                = var.subscription_scope
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
