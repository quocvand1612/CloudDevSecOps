# ==============================================================================
# Azure VMSS Spot Ephemeral Runner Module (Scale-to-Zero)
# ==============================================================================

# 1. Virtual Network & Subnet
resource "azurerm_virtual_network" "runner_vnet" {
  name                = "${var.project_name}-${var.environment}-runner-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_cidr]

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Role        = "GitHub-Runners-VNet"
  }
}

resource "azurerm_subnet" "runner_subnet" {
  name                 = "${var.project_name}-${var.environment}-runner-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.runner_vnet.name
  address_prefixes     = [var.subnet_cidr]
}

# 2. Network Security Group (Egress Only)
resource "azurerm_network_security_group" "runner_nsg" {
  name                = "${var.project_name}-${var.environment}-runner-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "AllowInternetOutBound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.runner_subnet.id
  network_security_group_id = azurerm_network_security_group.runner_nsg.id
}

# 3. Linux Virtual Machine Scale Set (Spot, Scale-to-Zero)
resource "azurerm_linux_virtual_machine_scale_set" "runner_vmss" {
  name                = "${var.project_name}-${var.environment}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_sku
  instances           = 0 # SCALE TO ZERO DEFAULT

  admin_username = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  # Standard Priority with Scale-to-Zero (0 idle cost)
  priority = "Regular"

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = var.disk_size_gb
  }

  network_interface {
    name    = "runner-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.runner_subnet.id
      public_ip_address {
        name = "runner-pip"
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/cloud_init.sh.tpl", {
    github_org          = var.github_org
    runner_labels       = var.runner_labels
    key_vault_name      = var.key_vault_name
    secret_name         = var.key_vault_secret_name
    resource_group_name = var.resource_group_name
    vmss_name           = "${var.project_name}-${var.environment}-vmss"
  }))

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Role        = "GitHub-Ephemeral-Runner"
  }

  lifecycle {
    ignore_changes = [instances]
  }
}

# 4. Grant VMSS SystemAssigned Identity permission on Resource Group for self-deallocation
resource "azurerm_role_assignment" "vmss_self_manage" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_virtual_machine_scale_set.runner_vmss.identity[0].principal_id
}
