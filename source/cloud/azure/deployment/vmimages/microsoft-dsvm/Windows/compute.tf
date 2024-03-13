## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

# Virtual Machine
resource "azurerm_windows_virtual_machine" "main" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.compute_size
  admin_username      = var.admin_username
  admin_password      = random_password.password.result
  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  source_image_reference {
      publisher ="microsoft-dsvm"
      offer = "dsvm-win-2019"
      sku = "server-2019"
      version = "latest"
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
    azurerm_storage_account.secondary, azurerm_network_interface.main
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
  virtual_machine_id = azurerm_windows_virtual_machine.main.id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "azurerm_virtual_machine_extension" "post_deployment" {
  name                 = "CustomScript"
  virtual_machine_id   = azurerm_windows_virtual_machine.main.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<SETTINGS
  {
     "commandToExecute": "powershell -encodedCommand ${textencodebase64(file("postdeploy.ps1"), "UTF-16LE")}"
  }
  SETTINGS
  depends_on = [azurerm_windows_virtual_machine.main]

}

data "template_file" "custom_script" {
    template = "${file("postdeploy.ps1")}"
}
