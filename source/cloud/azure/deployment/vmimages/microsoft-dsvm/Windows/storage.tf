## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

resource "azurerm_storage_account" "main" {
  name                     = "${var.prefix}storage"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_tier             = var.main_storage_account_tier
  account_kind             = var.main_storage_account_kind
  account_replication_type = var.main_storage_account_replication_type

  depends_on = [
    azurerm_subnet.main
  ]
}

resource "azurerm_storage_container" "main" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_account" "secondary" {
  name                     = "${var.prefix}diagstorage"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_replication_type = "LRS"
  account_tier             = "Standard"

  depends_on = [
    azurerm_subnet.main 
  ]

}

resource "azurerm_storage_container" "deployment" {
  name                  = "deployment"
  storage_account_name  = azurerm_storage_account.secondary.name
  container_access_type = "private"
}

## Diagnostics
resource "azurerm_monitor_diagnostic_setting" "storage" {
  name               = "storage-diagnostics"
  target_resource_id = azurerm_storage_account.main.id
  storage_account_id = azurerm_storage_account.secondary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id 
  metric {
    category = "Transaction"
  }
  
  depends_on = [azurerm_storage_account.main,azurerm_storage_account.secondary,azurerm_log_analytics_workspace.main]
}