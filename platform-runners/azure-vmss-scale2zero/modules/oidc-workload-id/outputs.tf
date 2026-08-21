output "client_id" {
  value       = azuread_application.github_actions.client_id
  description = "Azure AD Application (Client) ID for GitHub Actions azure/login action"
}

output "tenant_id" {
  value       = data.azuread_client_config.current.tenant_id
  description = "Azure AD Tenant ID"
}

output "service_principal_object_id" {
  value       = azuread_service_principal.github_actions.object_id
  description = "Service Principal Object ID"
}
