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

    $global:Product = $global:Catalog.Product.AzureADCache
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Persists Azure AD groups and users in a local cache."
    $global:Product.HasTask = $true

    $global:Product.Config = @{}

    $global:imgAzureADSync = "$($global:Location.Images)/AzureADSync.png"

    return $global:Product

#endregion PRODUCT DEFINITIONS