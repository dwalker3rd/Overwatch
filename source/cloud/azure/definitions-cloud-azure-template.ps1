#region AZCONFIG

    # required for Az 12.0.0 to disable WAM login.  See https://github.com/Azure/azure-powershell/issues/24967 
    if ((Get-InstalledPSResource Az -ErrorAction SilentlyContinue) -or (Get-InstalledPSResource Az -Scope AllUsers -ErrorAction SilentlyContinue)) {
        Update-AzConfig -EnableLoginByWam $false -WarningAction SilentlyContinue | Out-Null
    }

#endregion AZCONFIG 
#region GLOBAL CLOUD

    $global:Cloud = $global:Catalog.Cloud.Azure
    $global:Cloud.Image = "$($global:Location.Images)/azure_logo.png"

#endregion GLOBAL CLOUD
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

                ResourceType = @{
                    ApplicationInsights = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-appInsights`""
                        Dependencies = @{
                            OperationalInsightsWorkspace = @{}
                        }
                    }
                    Bastion = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-bastion`""
                        Dependencies = @{
                            Subnet = @{
                                subnetName = "AzureBastionSubnet"
                                subnetAddressPrefix = "10.1.1.0/26"
                            }
                            PublicIPAddress = @{}
                            VirtualNetwork = @{}
                        }
                    }
                    BatchAccount = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-batch`""
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = "diag" }
                            KeyVault = @{}
                        }
                    }
                    CosmosDBAccount = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-cosmos<00>`""
                        Dependencies = @{}
                    }
                    DataFactory = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-adf`"" 
                        Dependencies = @{}
                    }
                    Disk = @{
                        ResourceName = "`"`$(`$ResourceName)-<dependencyType><00>`""
                        Dependencies = @{}
                    }
                    KeyVault = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-kv`""
                        Dependencies = @{}
                    }
                    MLWorkspace = @{ 
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-mlws<00>`""
                        IdentityType = "`"SystemAssigned`""
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = "diag" }
                            KeyVault = @{}
                            ApplicationInsights = @{}
                        }
                    }
                    NetworkInterface = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-nic<00>`""
                        Dependencies = @{
                            Subnet = @{}
                        }
                    }
                    NetworkSecurityRule = @{
                        Name = "`"<Name>`""
                        Description = "`"<Description>`""
                        Access = "`"<Access>`""
                        Protocol = "`"<Protocol>`""
                        Direction = "`"<Direction>`""
                        Priority = "`"<Priority>`""
                        SourceAddressPrefix = "`"<SourceAddressPrefix>`""
                        SourcePortRange = "`"<SourcePortRange>`""
                        DestinationAddressPrefix = "`"<DestinationAddressPrefix>`""
                        DestinationPortRange = "`"<DestinationPortRange>`""
                        Dependencies = @{
                            NetworkSecurityGroup = @{}
                        }
                    }
                    NetworkSecurityGroup = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-nsg`""
                    }
                    OperationalInsightsWorkspace = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-loganalytics`""
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = "diag" }
                        }
                    }
                    PublicIPAddress = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-`$(`$ResourceType)-pip`""
                        Sku = "`"Standard`""
                        AllocationMethod = "`"Static`""
                    }
                    ResourceGroup = @{
                        ResourceName = "`"<resourceGroupName>`""
                    }
                    SqlVM = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-sqlvm`""
                        Dependencies = @{}
                    }
                    StorageAccount = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)<dependencyType>storage`""
                        Dependencies = @{}
                    }
                    StorageContainer = @{
                        Dependencies = @{
                            StorageAccount = @{ dependencyType = $null }
                        }
                    }
                    VM = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-vm<00>`""
                        Admin = "`"`$(`$prefix)`$(`$projectName)adm`""
                        Dependencies = @{
                            VirtualNetwork = @{}
                            NetworkSecurityGroup = @{}
                            PublicIPAddress = @{ dependentResourceType = "vm" }
                            NetworkInterface = @{}
                            Disk = @(
                                @{ dependencyType = "osdisk" },
                                @{ dependencyType = "datadisk" }
                            )
                        }
                    }
                    Subnet = @{
                        ResourceName = "`"<subnetName>`""
                        AddressPrefix = "`"<subnetAddressPrefix>`""
                        Dependencies = @{
                            VirtualNetwork = @{}
                        }
                    }
                    VirtualNetwork = @{
                        ResourceName = "`"`$(`$prefix)`$(`$projectName)-vnet`""
                        AddressPrefix = "`"10.1.1.0/16`""
                        SubnetName = "`"`$(`$prefix)`$(`$projectName)-subnet`""
                        SubnetAddressPrefix = "`"10.1.1.0/24`""
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
        "Subnet" = "Microsoft.Network/virtualNetworks/(.*)/subnets"
        "VirtualNetwork" = "Microsoft.Network/virtualNetworks"
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
        "Microsoft.Network/virtualNetworks/(.*)/subnets" = "Subnet"
        "Microsoft.OperationalInsights/workspaces" = "OperationalInsightsWorkspace" 
        "Microsoft.SqlVirtualMachine/SqlVirtualMachines" = "SqlVM"
        "Microsoft.Storage/storageAccounts" = "StorageAccount"
        "Microsoft.Storage/storageAccounts/(.*)/blobServices/default/containers" = "StorageContainer"
        "Microsoft.Resources/subscriptions/resourceGroups" = "ResourceGroup"
    }

#endregion GLOBAL DEFINITIONS