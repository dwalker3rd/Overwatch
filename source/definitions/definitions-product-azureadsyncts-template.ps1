#region PRODUCT DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = 
    [Product]@{
        Id = "AzureADSyncTS"
        Name = "AzureADSyncTS"
        Publisher = "Overwatch"
    }
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Syncs Active Directory users to Tableau Server."
$global:Product.HasTask = $true

$global:Product.Config = @{}

$global:imgAzureADSync = "$($global:Location.Images)/AzureADSync.png"

return $global:Product

#endregion PRODUCT DEFINITIONS