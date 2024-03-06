$global:Cloud = $global:Catalog.Cloud.Azure
$global:Cloud.Image = "$($global:Location.Images)/azure_logo.png"

function global:Initialize-AzureConfig {

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

            Templates = @{
                Resources = @{
                    Location = "uksouth"
                    Bastion = @{ Name = @{ Pattern = "<0><1>bastion" } }
                    ResourceGroup = @{Name = @{ Pattern = "<0>-<1>-rg" } }
                    StorageAccount = @{
                        SKU = "Standard_LRS"
                        Name = @{ Pattern = "<0><1>storage" }
                        SoftDelete = @{
                            Enabled = $true
                            RetentionDays = 7
                        }
                        Permission = "Off"
                    }
                    VM = @{
                        Name = @{ Pattern = "<0><1>vm<2>" }
                        Size = "Standard_DS13_v2"
                        OsType = "Windows"
                        Admin = @{ Pattern = "<0><1>adm" }
                    }
                    BatchAccount = @{ Name = @{ Pattern = "<0><1>batch" } }
                    MLWorkspace = @{ Name = @{ Pattern = "<0><1>mlws<2>" } }
                    CosmosDBAccount = @{  Name = @{ Pattern = "<0><1>cosmos<2>"  } }
                    SqlVM = @{ Name = @{ Pattern = "<0><1>sqlvm<2>" } }
                    KeyVault = @{ Name = @{ Pattern = "<0><1>-kv" } }
                    DataFactory = @{ Name = @{ Pattern = "<0><1>-adf" } }
                    ApplicationInsights = @{ Name = @{ Pattern = "<0><1>-appInsights"}}
                    NetworkInterface = @{ Name = @{ Pattern = "<0><1>-nic" } }
                }
            }

        }

        # some updates
        # ...

    }

}       
Set-Alias -Name azureInit -Value Initialize-AzureConfig -Scope Global  

Initialize-AzureConfig
