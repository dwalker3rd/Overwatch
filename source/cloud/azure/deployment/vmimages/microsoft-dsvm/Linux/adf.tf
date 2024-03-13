## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

resource "azurerm_data_factory" "main" {
  name                = "${var.prefix}-adf"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}