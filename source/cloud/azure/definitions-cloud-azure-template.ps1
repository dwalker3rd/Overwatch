$global:Cloud = $global:Catalog.Cloud.Azure
$global:Cloud.Image = "$($global:Location.Images)/azure_logo.png"

#region INITIALIZATION

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

        }

    }       
    Set-Alias -Name azureInit -Value Initialize-AzureConfig -Scope Global  

#endregion INITIALIZATION
#region GLOBAL DEFINITIONS

    $global:ResourceTypeAlias = @{}

    # resource type alias map
    $global:ResourceTypeAlias += @{
        "ApplicationInsights" = "Microsoft.Insights/components"
        "Bastion" = "Microsoft.Network/bastionHosts"
        "BatchAccount" = "Microsoft.Batch/BatchAccounts"        
        "CosmosDBAccount" = "Microsoft.DocumentDB/databaseAccounts"
        "DataFactory" = "Microsoft.DataFactory/factories"
        "KeyVault" = "Microsoft.KeyVault/vaults"
        "MLWorkspace" = "Microsoft.MachineLearningServices/workspaces"
        "NetworkInterface" = "Microsoft.Network/networkInterfaces"
        "SqlVM" = "Microsoft.SqlVirtualMachine/SqlVirtualMachines"
        "StorageAccount" = "Microsoft.Storage/storageAccounts"
        "StorageContainer" = "Microsoft.Storage/storageAccounts/(.*)/blobServices/default/containers"
        "VM" = "Microsoft.Compute/virtualMachines"
    }

    # reverse resource type alias map
    $global:ResourceTypeAlias += @{
        "Microsoft.Batch/BatchAccounts" = "BatchAccount"
        "Microsoft.Compute/virtualMachines" = "VM"
        "Microsoft.DataFactory/factories" = "DataFactory"
        "Microsoft.DocumentDB/databaseAccounts" = "CosmosDBAccount"
        "Microsoft.Insights/components" = "ApplicationInsights"
        "Microsoft.KeyVault/vaults" = "KeyVault"
        "Microsoft.MachineLearningServices/workspaces" = "MLWorkspace"
        "Microsoft.Network/bastionHosts" = "Bastion"
        "Microsoft.Network/networkInterfaces" = "NetworkInterface"
        "Microsoft.SqlVirtualMachine/SqlVirtualMachines" = "SqlVM"
        "Microsoft.Storage/storageAccounts" = "StorageAccount"
        "Microsoft.Storage/storageAccounts/(.*)/blobServices/default/containers" = "StorageContainer"
    }    

    # resource location map
    $global:ResourceLocations = Get-AzLocation
    $global:ResourceLocationMap = @{}
    $global:ResourceLocations | Foreach-Object {$global:ResourceLocationMap += @{"$($_.Location)" = $_.DisplayName}}
    $global:ResourceLocations | Where-Object {!$global:ResourceLocationMap.$($_.DisplayName)} | Foreach-Object {$global:ResourceLocationMap += @{"$($_.DisplayName)" = $_.Location}}

    # available providers
    $script:ResourceProviders = Get-AzResourceProvider -ListAvailable

#endregion GLOBAL DEFINITIONS