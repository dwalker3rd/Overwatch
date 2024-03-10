#region PRODUCT DEFINITIONS

    param(
        [switch]$MinimumDefinitions
    )

    if ($MinimumDefinitions) {
        $root = $PSScriptRoot -replace "\\definitions",""
        Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
    }
    else {
        . $PSScriptRoot\classes.ps1
    }

    $global:Product = $global:Catalog.Product.AzureProjects

    $global:Product.Config = @{

        Templates = @{
            Resources = @{
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

    return $global:Product

#endregion PRODUCT DEFINITIONS