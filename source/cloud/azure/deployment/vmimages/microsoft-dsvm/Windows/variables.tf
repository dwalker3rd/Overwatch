## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

variable prefix {
    description = "Prefix to append at the begining of all Azure resources names"
    default = "dsenv01"
}

locals {
  random_padding = "${var.prefix}${random_string.padding.result}"
}

resource "random_string" "padding" {
  length  = 12 - length(var.prefix)
  special = false
  upper   = false
}

variable "main_resource_group_name" {
}

variable "admin_username" {
  description = "The admin user name of the windows virtual machine."
}

variable location {
    default = "eastus"
}

variable user_ip {
}

locals {
    resource_prefix = local.random_padding
}

variable "virtual_network_address_prefix" {
  description = "VNET address prefix"
  default     = ["10.1.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Subnet address prefix"
  default     = ["10.1.0.0/24"]
}

variable "bastion_subnet_address_prefix" {
  description = "Subnet address prefix"
  default     = ["10.1.1.0/26"]
}

variable "user_object_id" {
  description = "This is the object id that will be assinged to the compute resource."
  default     = ""
}

variable "compute_size" {
  description = "Virtual Machine Size"
  default     = "Standard_NC6s_v2"
}

variable "tags" {
  description = "Tags used to identify resources."
  type        = map(string)

  default = {
    source = "terraform"
    env    = "sandbox"
  }
}
variable network_watcher_name {
}

variable network_watcher_count {
  default = 1
}

variable network_watcher_rg_name {
    default = "NetworkWatcherRG"
}