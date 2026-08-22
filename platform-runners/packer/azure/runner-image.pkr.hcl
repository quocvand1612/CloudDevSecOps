packer {
  required_plugins {
    azure = {
      version = ">= 2.0.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "devsecops-runners-mgmt-rg"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())
}

# Same base image as azure-vmss-scale2zero/modules/vmss-runner/main.tf
# (source_image_reference publisher/offer/sku), so the golden image stays a
# strict superset of the currently-deployed OS.
source "azure-arm" "runner" {
  use_azure_cli_auth = true # reuse the operator's existing `az login` session (OIDC-only repo convention: no static SP secrets)
  subscription_id    = var.subscription_id
  location           = var.location
  vm_size            = var.vm_size

  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"

  managed_image_resource_group_name = var.resource_group_name
  managed_image_name                = "devsecops-runner-golden-azure-${local.timestamp}"

  azure_tags = {
    Name          = "devsecops-runner-golden-azure"
    RunnerVersion = "2.336.0"
    BuiltBy       = "packer"
    Project       = "devsecops-runners"
  }
}

build {
  name    = "devsecops-runner-azure"
  sources = ["source.azure-arm.runner"]

  provisioner "shell" {
    environment_vars = ["CLOUD=azure"]
    script           = "../scripts/provision-common.sh"
    execute_command  = "sudo -E bash '{{ .Path }}'"
  }

  # Azure VM images must be generalized (waagent deprovision) before capture.
  provisioner "shell" {
    inline = [
      "sudo waagent -deprovision+user -force",
    ]
  }
}
