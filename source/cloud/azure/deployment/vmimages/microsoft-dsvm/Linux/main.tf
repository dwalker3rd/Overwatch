## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.89.0"
    }
  }

  backend "azurerm" {
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