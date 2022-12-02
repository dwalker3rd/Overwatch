#region PRODUCT DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$global:Product = $global:Catalog.Product.StartRMTAgents
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Starts $($global:Platform.Name) agents."
$global:Product.HasTask = $true

return $global:Product

#endregion PRODUCT DEFINITIONS