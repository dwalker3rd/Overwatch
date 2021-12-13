#region PRODUCT DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = 
    [Product]@{
        Id = "AzureADCache"
        Name = "AzureADCache"
        Vendor = "Overwatch"
    }
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Persists Azure AD groups and users in a local cache"
$global:Product.HasTask = $true

$global:Product.Config = @{}

$global:imgAzureADCache = "$($global:Location.Images)/AzureADCache.png"

return $global:Product

#endregion PRODUCT DEFINITIONS