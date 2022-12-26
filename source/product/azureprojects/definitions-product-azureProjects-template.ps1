#region PRODUCT DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$global:Product = $global:Catalog.Product.AzureProjects

$global:Product.Config = @{}
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"

return $global:Product

#endregion PRODUCT DEFINITIONS