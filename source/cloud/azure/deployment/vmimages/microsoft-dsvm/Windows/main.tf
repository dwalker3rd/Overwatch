## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.89.0"
    }
  }
}
provider "azurerm" {
   features {
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "primary" {}

resource "tls_private_key" "ssh_key" {
  algorithm   = "RSA"
}

resource "random_password" "password" {
  length           = 12
  special = true  
  upper   = true  
  lower   = true  
  numeric  = true  
  override_special = "!@#$%^&*()-=+[]{}|:;,.<>?/~" 
}

resource "random_password" "client_secret" {
  length           = 12
  special          = false
}