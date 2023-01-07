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

    $global:Product = $global:Catalog.Product.Command
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.DisplayName)"
    $global:Product.Description = "A command interface for managing the $($global:Platform.DisplayName) platform."
    # $global:Product.ShutdownMax = New-TimeSpan -Minutes 5
    $global:Product.HasTask = $false

    return $global:Product

#endregion PRODUCT DEFINITIONS