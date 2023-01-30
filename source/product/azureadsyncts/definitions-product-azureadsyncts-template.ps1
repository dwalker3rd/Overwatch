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

    $global:Product = $global:Catalog.Product.AzureADSyncTS
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Syncs Active Directory users to Tableau Server."
    $global:Product.HasTask = $true

    $global:Product.Config = @{
        Schedule = @{
            Full = @{
                DayOfWeek = "Sunday"
                Hour = 1
                Minute = @(0..14)
            }
        }
        Sites = @{
            ContentUrl = @("PathOperations")
        }
        PathOperations = @{
            SiteRoleMinimum = "ExplorerCanPublish"
        }
    }

    $global:imgAzureADSync = "$($global:Location.Images)/AzureADSync.png"

    return $global:Product

#endregion PRODUCT DEFINITIONS