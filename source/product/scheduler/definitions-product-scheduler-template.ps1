#region PRODUCT DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = $global:Catalog.Product.Scheduler
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Manages scheduled activities for Overwatch"
$global:Product.HasTask = $true

$global:Product.Config = @{}

return $global:Product

#endregion PRODUCT DEFINITIONS