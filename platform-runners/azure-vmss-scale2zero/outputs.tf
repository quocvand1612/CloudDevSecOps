output "azure_client_id" {
  value       = module.oidc.client_id
  description = "Azure App Client ID for GitHub Actions azure/login action"
}

output "azure_tenant_id" {
  value       = var.tenant_id
  description = "Azure Tenant ID"
}

output "azure_subscription_id" {
  value       = var.subscription_id
  description = "Azure Subscription ID"
}

output "azure_webhook_endpoint_url" {
  value       = module.webhook_scaler.webhook_url
  description = "Azure Function Webhook URL to configure in GitHub Org Webhooks"
}

output "vmss_name" {
  value       = module.vmss_runner.vmss_name
  description = "Azure VMSS Name"
}

output "key_vault_name" {
  value       = azurerm_key_vault.runners_kv.name
  description = "Key Vault holding runner secrets"
}
