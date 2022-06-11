#region PRODUCT DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = 
    [Product]@{
        Id = "StartRMTAgents"
        Name = "StartRMTAgents"
        Publisher = "Overwatch"
    }
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.DisplayName)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Starts $($global:Platform.Name) agents."
$global:Product.HasTask = $true

return $global:Product

#endregion PRODUCT DEFINITIONS