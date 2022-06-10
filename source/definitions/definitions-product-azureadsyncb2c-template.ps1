#region PRODUCT DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = 
    [Product]@{
        Id = "AzureADSyncB2C"
        Name = "AzureADSyncB2C"
        Publisher = "Overwatch"
    }
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.DisplayName)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Syncs Azure AD users to Azure AD B2C."
$global:Product.HasTask = $true

$global:Product.Config = @{}

$global:imgAzureADSync = "$($global:Location.Images)/AzureADSync.png"

return $global:Product

#endregion PRODUCT DEFINITIONS