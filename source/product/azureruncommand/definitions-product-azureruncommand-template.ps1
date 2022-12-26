#region PRODUCT DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$global:Product = $global:Catalog.Product.AzureRunCommand
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"

$global:Product.Config = @{}

return $global:Product

#endregion PRODUCT DEFINITIONS