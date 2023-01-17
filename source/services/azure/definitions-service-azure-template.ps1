# The following line indicates a post-installation configuration to the installer
# Manual Configuration > Service > Azure > Configure Azure Projects

function global:Initialize-Azure {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    param()

    if ($null -eq $global:Azure) {
        $global:Azure = @{}
        $global:Azure += @{

            Location = @{ 
                Data = "$($global:Location.Root)\data\azure"
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

            Defaults = @{
                Location = "uksouth"
                Bastion = @{ Name = @{ Template = "<0><1>bastion" } }
                ResourceGroup = @{Name = @{ Template = "<0>-<1>-rg" } }
                StorageAccount = @{
                    SKU = "Standard_LRS"
                    Name = @{ Template = "<0><1>storage" }
                    SoftDelete = @{
                        Enabled = $true
                        RetentionDays = 7
                    }
                    Permission = "Off"
                }
                VM = @{
                    Name = @{ Template = "<0><1>vm<2>" }
                    Size = "Standard_DS13_v2"
                    OsType = "Windows"
                    Admin = @{ Template = "<0><1>adm" }
                }
                BatchAccount = @{ Name = @{ Template = "<0><1>batch" } }
                MLWorkspace = @{ Name = @{ Template = "<0><1>mlws<2>" } }
                CosmosDBAccount = @{  Name = @{ Template = "<0><1>cosmos<2>"  } }
                SqlVM = @{ Name = @{ Template = "<0><1>sqlvm<2>" } }
                KeyVault = @{ Name = @{ Template = "<0><1>-kv" } }
                DataFactory = @{ Name = @{ Template = "<0><1>-adf" } }
            }

        }
    }

}       
Set-Alias -Name azureInit -Value Initialize-Azure -Scope Global  

Initialize-Azure