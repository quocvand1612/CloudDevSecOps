output "function_app_name" {
  value       = azurerm_linux_function_app.scaler.name
  description = "Azure Function App name"
}

output "function_app_default_hostname" {
  value       = azurerm_linux_function_app.scaler.default_hostname
  description = "Default hostname of the Function App"
}

output "webhook_url" {
  value       = "https://${azurerm_linux_function_app.scaler.default_hostname}/api/webhook"
  description = "Webhook URL to configure in GitHub Org settings"
}
