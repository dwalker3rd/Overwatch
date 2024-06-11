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

$global:Product = $global:Catalog.Product.Upgrade
$global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
$global:Product.TaskName = $global:Product.DisplayName
$global:Product.Description = "Upgrades the $($global:Platform.Name) platform."
$global:Product.HasTask = $true

$global:Product.Config = @{
    "<platform>" = @{
        build = ""
        version = ""
        script = ""
        workingDirectory = ""
        startPlatform = $true
        retryCount = 1
    }
}
$global:Product.Config."<platform>".script = "C:\Program Files\Platform...\scripts\upgrade.ps1 --arg1"
$global:Product.Config."<platform>".workingDirectory = "C:\Program Files\...\scripts"

return $global:Product

#endregion PRODUCT DEFINITIONS