## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "${var.prefix}-vm-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.prefix}"
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  ip_configuration {
    name                          = "DefaultSubnet"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id 
  }
  depends_on = [
    azurerm_virtual_network.main, 
    azurerm_public_ip.main, 
    azurerm_subnet.main
    ]
}

# Vitrual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet"
  address_space       = var.virtual_network_address_prefix
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_address_prefix
  service_endpoints    = ["Microsoft.KeyVault","Microsoft.Storage"]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.user_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Port_8000"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000"
    source_address_prefix      = var.user_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Port_80"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
  depends_on                = [azurerm_subnet.main]
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
  depends_on = [
    azurerm_network_interface.main
  ]
}

# Bastion Host
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.bastion_subnet_address_prefix
  depends_on           = [azurerm_virtual_network.main, azurerm_linux_virtual_machine.main]
}

resource "azurerm_public_ip" "bastion" {
  name                = "${var.prefix}-bastion-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion" {
  name                = "${var.prefix}-bastion"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
  depends_on           = [azurerm_subnet.bastion, azurerm_public_ip.bastion]
}

resource "azurerm_network_watcher" "main" {
  name                = "${var.network_watcher_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = var.network_watcher_rg_name
}

## Network Watcher and Logs
resource "azurerm_network_watcher_flow_log" "main" {
  name                      = "${var.network_watcher_name}${var.prefix}"
  network_watcher_name      = azurerm_network_watcher.main.name
  resource_group_name       = azurerm_network_watcher.main.resource_group_name
  network_security_group_id = azurerm_network_security_group.main.id
  storage_account_id        = azurerm_storage_account.secondary.id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = 10
  }
  depends_on = [azurerm_storage_account.secondary, azurerm_log_analytics_workspace.main]
}