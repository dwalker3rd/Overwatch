## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

# Key Vault
resource "azurerm_key_vault" "main" {
  name                = "${var.prefix}-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"
  enabled_for_disk_encryption = true

    access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = var.user_object_id

    key_permissions = [
      "Get", "Create", "List"
    ]

    secret_permissions = [
      "Get", "List", "Set"
    ]

    storage_permissions = [
      "Get", "List"
    ]
  }
}

# Save SSH Key as a secret
resource "azurerm_key_vault_secret" "ssh-private-key" {
  name         = "jhub-ssh-private-key"
  value        = tls_private_key.ssh_key.private_key_pem
  key_vault_id = azurerm_key_vault.main.id
  depends_on = [
    tls_private_key.ssh_key
  ]
}

# Save main Storage Account name as a secret
resource "azurerm_key_vault_secret" "storage-account-name" {
  name         = "${var.prefix}storage-name"
  value        = azurerm_storage_account.main.name
  key_vault_id = azurerm_key_vault.main.id
  depends_on = [
    azurerm_storage_account.main
  ]
}

# Save main Storage Account primary Key as a secret
resource "azurerm_key_vault_secret" "storage_key" {
  name         = "${var.prefix}storage-key"
  value        = azurerm_storage_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on = [
    azurerm_storage_account.main
  ]
}

# Role assignments
resource "azurerm_role_assignment" "vm_reader" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine.main.identity[0].principal_id
  depends_on = [
    azurerm_linux_virtual_machine.main
  ]
}

## Diagnostics
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name               = "kv-diagnostics"
  target_resource_id = azurerm_key_vault.main.id
  storage_account_id = azurerm_storage_account.secondary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id 

  metric {
    category = "AllMetrics"
  }
  
  depends_on = [azurerm_key_vault.main,azurerm_log_analytics_workspace.main,azurerm_storage_account.secondary]
}