## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

resource "azurerm_resource_group" "main" {
  name     = var.main_resource_group_name
  location = var.location
  tags     = var.tags
}