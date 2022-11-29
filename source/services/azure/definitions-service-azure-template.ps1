# The following line indicates a post-installation configuration to the installer
# Manual Configuration > Service > Azure > Configure Azure Projects

function global:Initialize-AzureProjects {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    param()

    if ($null -eq $global:AzureProjects) {
        $global:AzureProjects = @{}
        $global:AzureProjects += @{

            Location = @{ 
                Data = "$($global:Location.Root)\data\azure"
            }
            Tenant = @{
                Group = @{
                    Project = @{}
                }
            }
            Defaults = @{
                Resources = @{
                    Minimum = @(
                        @{
                            resourceType = "StorageAccount"
                            resourceName = ""
                            resourceID = "StorageAccount"
                        },
                        @{
                            resourceType = "StorageContainer"
                            resourceName = ""
                            resourceID = "StorageContainer"
                        }
                    )
                }
            }

        }
    }

}       

Initialize-AzureProjects