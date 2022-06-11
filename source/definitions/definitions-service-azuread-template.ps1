# The following line indicates a post-installation configuration to the installer
# Manual Configuration > Service > AzureAD > Update Data

function global:Initialize-AzureAD {

    $global:AzureAD = @()
    $global:AzureAD += @{

        Data = "$($global:Location.Root)\data\azureAD"
        SpecialGroups = @("All Users", "All Domain Users")

        acme = @{
            Name = "acme"
            Prefix = "acme"
            DisplayName = "acme"
            Organization = "ACME Corporation"
            Subscription = @{
                Id = "00000000-0000-0000-0000-000000000000"
                Name = "ACME Azure AD Tenant"
            }
            Tenant = @{
                Type = "Azure AD"
                Id = "00000000-0000-0000-0000-000000000000"
                Name = "acme.onmicrosoft.com"
                Domain = @("acme.onmicrosoft.com")
            }
            IdentityIssuer = "acme.okta.com"
            MsGraph = @{
                Scope = "https://graph.microsoft.com/.default"
                Credentials = "acme-msgraph" # app id/secret
                AccessToken = $null
            }
            Sync = @{
                Enabled = $true
                Source = "acme.com"
            }
        }

        acmeb2c = @{
            Name = "acmeb2c"
            Prefix = "acmeb2c"
            DisplayName = "acmeb2c"
            Organization = "ACMEB2C"
            Subscription = @{
                Id = "00000000-0000-0000-0000-000000000000"
                Name = "ACMEB2C Azure AD B2C"
            }
            Tenant = @{
                Type = "Azure AD B2C"
                Id = "00000000-0000-0000-0000-000000000000"
                Name = "acmeb2c.onmicrosoft.com"
                Domain = @("acmeb2c.onmicrosoft.com")
            }
            MsGraph = @{
                Scope = "https://graph.microsoft.com/.default"
                Credentials = "acmeb2c-msgraph" # app id/secret
                AccessToken = $null
            }
            Admin = @{
                Credentials = "acmeb2c-admin"
            }
        }
    }

}
Set-Alias -Name azureADInit -Value Initialize-AzureAD -Scope Global

Initialize-AzureAD