# The following line indicates a post-installation configuration to the installer
# Manual Configuration > Service > Azure > Configure Azure AD tenants
# Manual Configuration > Service > Azure > Add MsGraph credentials to vault

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

        }
    }

}       
Set-Alias -Name azProjInit -Value Initialize-AzureProjects -Scope Global

Initialize-AzureProjects