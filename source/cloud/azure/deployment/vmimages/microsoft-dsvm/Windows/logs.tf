## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

resource "azurerm_log_analytics_workspace" "main" {
    name                = "${var.prefix}-loganalytics"
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name
    sku                 = var.log_analytics_workspace_sku
}

resource "azurerm_log_analytics_linked_storage_account" "main" {
  data_source_type      = "CustomLogs"
  resource_group_name   = azurerm_resource_group.main.name
  workspace_resource_id = azurerm_log_analytics_workspace.main.id
  storage_account_ids   = [azurerm_storage_account.secondary.id]
  depends_on = [azurerm_log_analytics_workspace.main,azurerm_storage_account.secondary]
}