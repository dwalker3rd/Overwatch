## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

data "azuread_client_config" "current" {}

resource "azuread_application" "jhub" {
  display_name     = "${var.prefix}-jhub-app"
  identifier_uris  = []
  sign_in_audience = "AzureADMyOrg"

  api {
    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access terraform-jhub-app on behalf of the signed-in user."
      admin_consent_display_name = "Access terraform-jhub-app"
      enabled                    = true
      id                         = "96183846-204b-4b43-82e1-5d2222eb4b9b"
      type                       = "User"
      user_consent_description   = "Allow the application to access terraform-jhub-app on your behalf."
      user_consent_display_name  = "Access jhub-app"
      value                      = "user_impersonation"
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
  }

  web {
    redirect_uris = ["https://${var.prefix}.${var.location}.cloudapp.azure.com:8000/hub/oauth_callback"]

    implicit_grant {
      access_token_issuance_enabled = true
    }
  }
}

resource "azuread_service_principal" "jhub_app" {
  client_id               = azuread_application.jhub.client_id
  app_role_assignment_required = false
}

resource "azuread_application_password" "jhub" {
  application_id = "/applications/${azuread_application.jhub.object_id}"
  start_date = timestamp()
  end_date = timeadd(timestamp(), "17520h") # 2 years duration. You will need to renew the client secret and add it to the jupyterhub_conf.py file in the vm
}