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

# Save the vm username as a secet
resource "azurerm_key_vault_secret" "vm_username" {
  name         = "${var.prefix}-vm-username"
  value        = var.admin_username
  key_vault_id = azurerm_key_vault.main.id
}

# Save vm password as a secret
resource "azurerm_key_vault_secret" "vm_password" {
  name         = "${var.prefix}-vm-password"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on = [
    random_password.password
  ]
}