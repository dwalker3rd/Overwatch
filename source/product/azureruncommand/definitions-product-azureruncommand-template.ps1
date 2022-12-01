#region PRODUCT DEFINITIONS

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = $global:Catalog.Product.AzureRunCommand

$global:Product.Config = @{}

return $global:Product

#endregion PRODUCT DEFINITIONS