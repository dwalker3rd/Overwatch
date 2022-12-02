#region PRODUCT DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$global:Product = $global:Catalog.Product.AzureProjects

$global:Product.Config = @{}

return $global:Product

#endregion PRODUCT DEFINITIONS