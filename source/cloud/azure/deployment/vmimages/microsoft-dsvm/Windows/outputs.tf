## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "main_storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "main_storage_account_key" {
  value = azurerm_storage_account.main.primary_access_key
  sensitive = true
}

output "secondary_storage_account_key" {
  value = azurerm_storage_account.secondary.primary_access_key
  sensitive = true
}

output "compute_name"{
  value= azurerm_windows_virtual_machine.main.name
}

output "vm_fqdn" {
  value = azurerm_public_ip.main.domain_name_label
}

output "client_secret" {
  value = random_password.client_secret.result
  sensitive = true
}

output "vm_password" {
  value = random_password.password.result
  sensitive = true
}

output "nsg_name" {
  value = azurerm_network_security_group.main.name
}