## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.compute_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  source_image_reference {
    publisher = "microsoft-dsvm"
    offer     = "ubuntu-2004"
    sku       = "2004-gen2"
    version   = "22.07.19"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 1024
  }
  
  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = "https://${azurerm_storage_account.secondary.name}.blob.core.windows.net/"
  }
  depends_on = [
    azurerm_network_interface.main
  ]
}

# Data Disk

resource "azurerm_managed_disk" "main" {
  name                 = "${var.prefix}-vm-DataDisk_1"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 1024
}

resource "azurerm_virtual_machine_data_disk_attachment" "main" {
  managed_disk_id    = azurerm_managed_disk.main.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = "10"
  caching            = "ReadWrite"
}
