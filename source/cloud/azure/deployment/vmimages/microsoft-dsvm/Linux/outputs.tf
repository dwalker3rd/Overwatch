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

output "secondary_storage_account_name" {
  value = azurerm_storage_account.secondary.name
}

output "secondary_storage_account_key" {
  value = azurerm_storage_account.secondary.primary_access_key
  sensitive = true
}

output "compute_name"{
  value= azurerm_linux_virtual_machine.main.name
}

output "vm_fqdn" {
  value = azurerm_public_ip.main.domain_name_label
}

output "ssh_key" {
  value = tls_private_key.ssh_key
  sensitive = true
}

output "ssh_private_key" {
  value = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}

output "ssh_public_key" {
  value = tls_private_key.ssh_key.public_key_openssh
  sensitive = true
}

output "client_secret" {
  value = azuread_application_password.jhub.value
  sensitive = true
}

output "client_id" {
  value = azuread_application.jhub.client_id
  sensitive = true
}

output "object_id" {
  value = azuread_application.jhub.object_id
  sensitive = true
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "nsg_name" {
  value = azurerm_network_security_group.main.name
}