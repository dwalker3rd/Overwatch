## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

resource "azurerm_storage_account" "main" {
  name                     = "${var.prefix}storage"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_account" "secondary" {
  name                     = "${var.prefix}diagstorage"
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  account_replication_type = "LRS"
  account_tier             = "Standard"
}

resource "azurerm_storage_container" "deployment" {
  name                  = "deployment"
  storage_account_name  = azurerm_storage_account.secondary.name
  container_access_type = "private"
}
