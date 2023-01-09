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

$global:Product = $global:Catalog.Product.BgInfo
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName

$global:Product.Config = @{
    Files = @{
        Config = "$($global:Location.BgInfo)\bgInfo.bgi"
        CustomContent = "$($global:Location.BgInfo)\bgInfo.txt"
    }
}

$global:imgAzureADSync = "$($global:Location.Images)/AzureADSync.png"

return $global:Product

#endregion PRODUCT DEFINITIONS