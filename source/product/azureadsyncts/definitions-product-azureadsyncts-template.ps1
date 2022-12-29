#region PRODUCT DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$global:Product = $global:Catalog.Product.AzureADSyncTS
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Syncs Active Directory users to Tableau Server."
$global:Product.HasTask = $true

$platformTaskInterval = Get-PlatformTaskInterval AzureADSyncTS

$global:Product.Config = @{
    Schedule = @{
        Full = @{
            DayOfWeek = "Sunday"
            Hour = 1
            Minute = @(0..($platformTaskInterval.Seconds -eq 0 ? $platformTaskInterval.Minutes - 1 : $platformTaskInterval.Minutes))
        }
    }
}

$global:imgAzureADSync = "$($global:Location.Images)/AzureADSync.png"

return $global:Product

#endregion PRODUCT DEFINITIONS