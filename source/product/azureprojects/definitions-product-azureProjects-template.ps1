#region PRODUCT DEFINITIONS

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$global:Product = $global:Catalog.Product.AzureProjects

$global:Product.Config = @{
    Location = @{
        Base = "$($global:Location.Root)\data"
    }
}
$global:Product.Config.Location += @{ Root = "$($global:Product.Config.Location.Base)\azure" }

return $global:Product

#endregion PRODUCT DEFINITIONS