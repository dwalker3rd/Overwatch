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

                ResourceTypes = @{
                    ApplicationInsights = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-appInsights`"" }
                        Dependencies = @{
                            OperationalInsightsWorkspace = @{}
                        }
                    }
                    Bastion = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-bastion`"" }
                        Dependencies = @{
                            VirtualNetwork = @{}
                            PublicIPAddress = @{}
                        }
                    }
                    BatchAccount = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-batch`"" }
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = "diag" }
                            KeyVault = @{}
                        }
                    }
                    CosmosDBAccount = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-cosmos00`""}
                        Dependencies = @{}
                    }
                    DataFactory = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-adf`"" } 
                        Dependencies = @{}
                    }
                    Disk = @{
                        Name = @{ Pattern = "`"`$(`$dependentResourceName)-<dependencyType>00`"" }
                        Dependencies = @{}
                    }
                    KeyVault = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-kv`"" }
                        Dependencies = @{}
                    }
                    MLWorkspace = @{ 
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-mlws00`"" }
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = "diag" }
                            KeyVault = @{}
                            ApplicationInsights = @{}
                        }
                    }
                    NetworkInterface = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-nic00`"" }
                        Dependencies = @{
                            VirtualNetworkSubnetConfig = @{}
                        }
                    }
                    NetworkSecurityGroup = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-nsg`"" }
                        Dependencies = @{}
                    }
                    OperationalInsightsWorkspace = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-loganalytics`"" }
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = "diag" }
                        }
                    }
                    PublicIPAddress = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-`$(`$dependentResourceType)-pip`"" }
                        Dependencies = @{}
                    }
                    ResourceGroup = @{
                        Name = @{ Pattern = "`"`$(`$prefix)-`$(`$projectName)-rg`"" }
                        Dependencies = @{}
                    }
                    SqlVM = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-sqlvm`"" }
                        Dependencies = @{}
                    }
                    StorageAccount = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)<dependencyType>storage`"" }
                        Dependencies = @{}
                    }
                    StorageContainer = @{
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = $null }
                        }
                    }
                    VM = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-vm00`"" }
                        Admin = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)adm`"" }
                        Dependencies = @{
                            VirtualNetwork = @{}
                            VirtualNetworkSubnetConfig = @{}
                            NetworkSecurityGroup = @{}
                            PublicIPAddress = @{}
                            NetworkInterface = @{}
                            Disk = @(
                                @{ dependencyType = "osdisk" },
                                @{ dependencyType = "datadisk" }
                            )
                        }
                    }
                    VirtualNetwork = @{
                        Name = @{ Pattern = "`"`$(`$prefix)`$(`$projectName)-vnet`"" }
                        Dependencies = @{
                            VirtualNetworkSubnetConfig = @{}
                        }
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
        "Disk" = "Microsoft.Compute/disks"
        "KeyVault" = "Microsoft.KeyVault/vaults"
        "MLWorkspace" = "Microsoft.MachineLearningServices/workspaces"
        "NetworkInterface" = "Microsoft.Network/networkInterfaces"
        "NetworkSecurityGroup" = "Microsoft.Network/networkSecurityGroups"
        "OperationalInsightsWorkspace" = "Microsoft.OperationalInsights/workspaces"
        "PublicIpAddress" = "Microsoft.Network/publicIPAddresses"
        "ResourceGroup" = "Microsoft.Resources/subscriptions/resourceGroups"
        "SqlVM" = "Microsoft.SqlVirtualMachine/SqlVirtualMachines"
        "StorageAccount" = "Microsoft.Storage/storageAccounts"
        "StorageContainer" = "Microsoft.Storage/storageAccounts/(.*)/blobServices/default/containers"
        "VirtualNetwork" = "Microsoft.Network/virtualNetworks"
        "VirtualNetworkSubnetConfig" = "Microsoft.Network/virtualNetworks/(.*)/subnets"
        "VM" = "Microsoft.Compute/virtualMachines"
        "VmExtension" = "Microsoft.Compute/virtualMachines/extensions"
    }

    # reverse resource type alias map
    $global:ResourceTypeAlias += @{
        "Microsoft.Batch/BatchAccounts" = "BatchAccount"
        "Microsoft.Compute/virtualMachines" = "VM"
        "Microsoft.Compute/virtualMachines/extensions" = "VmExtension"
        "Microsoft.DataFactory/factories" = "DataFactory"
        "Microsoft.Compute/disks" = "Disk"
        "Microsoft.DocumentDB/databaseAccounts" = "CosmosDBAccount"
        "Microsoft.Insights/components" = "ApplicationInsights"
        "Microsoft.KeyVault/vaults" = "KeyVault"
        "Microsoft.MachineLearningServices/workspaces" = "MLWorkspace"
        "Microsoft.Network/bastionHosts" = "Bastion"
        "Microsoft.Network/networkInterfaces" = "NetworkInterface"
        "Microsoft.Network/publicIPAddresses" = "PublicIpAddress"
        "Microsoft.Network/networkSecurityGroups" = "NetworkSecurityGroup"
        "Microsoft.Network/virtualNetworks" = "VirtualNetwork"
        "Microsoft.Network/virtualNetworks/(.*)/subnets" = "VirtualNetworkSubnetConfig"
        "Microsoft.OperationalInsights/workspaces" = "OperationalInsightsWorkspace" 
        "Microsoft.SqlVirtualMachine/SqlVirtualMachines" = "SqlVM"
        "Microsoft.Storage/storageAccounts" = "StorageAccount"
        "Microsoft.Storage/storageAccounts/(.*)/blobServices/default/containers" = "StorageContainer"
        "Microsoft.Resources/subscriptions/resourceGroups" = "ResourceGroup"
    }

#endregion GLOBAL DEFINITIONS
