#region PRODUCT DEFINITIONS

param(
    [switch]$MinimumDefinitions
)

if ($MinimumDefinitions) {
    $root = $PSScriptRoot -replace "\\definitions",""
    Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
}
else {
    . $PSScriptRoot\classes.ps1
}

$global:Product = $global:Catalog.Product.AzureProjects

$global:Product.Config = @{}

return $global:Product

#endregion PRODUCT DEFINITIONS