output "vmss_id" {
  value       = azurerm_linux_virtual_machine_scale_set.runner_vmss.id
  description = "Virtual Machine Scale Set ID"
}

output "vmss_name" {
  value       = azurerm_linux_virtual_machine_scale_set.runner_vmss.name
  description = "Virtual Machine Scale Set Name"
}

output "vmss_principal_id" {
  value       = azurerm_linux_virtual_machine_scale_set.runner_vmss.identity[0].principal_id
  description = "Principal ID of VMSS Managed Identity"
}
