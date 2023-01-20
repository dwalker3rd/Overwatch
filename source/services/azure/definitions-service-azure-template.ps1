# The following line indicates a post-installation configuration to the installer
# Manual Configuration > Service > AzureAD > Configure Azure AD tenant
# Manual Configuration > Service > AzureAD > Add MsGraph credentials to vault
# Manual Configuration > Service > AzureAD > Add Admin credentials to vault

function global:Initialize-Azure {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    param(
        [switch]$Reinitialize
    )

    if ($null -eq $global:Azure -or $Reinitialize) {
        $global:Azure = @{}
        $global:Azure += @{

            Location = @{ 
                Data = "$($global:Location.Root)\data\azure"
            }

            "<tenantKeyNoQuotes>" = @{
                Name = "<tenantKey>"
                Prefix = "<tenantKey>"
                DisplayName = "<tenantName>"
                Organization = ""
                Subscription = @{
                    Id = "<subscriptionId>"
                    Name = "<subscriptionName>"
                }
                Tenant = @{
                    Type = "<tenantType>"
                    Id = "<tenantId>"
                    Name = "<tenantName>"
                    Domain = @("<tenantDomain>")
                }
                MsGraph = @{
                    Scope = "https://graph.microsoft.com/.default"
                    Credentials = "<tenantKey>-msgraph" # app id/secret
                    AccessToken = $null
                }
                Admin = @{
                    Credentials = "<tenantKey>-admin"
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