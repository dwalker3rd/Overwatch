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

    $global:Product = $global:Catalog.Product.AyxRunner
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.DisplayName)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Config = @{
        NotRunningThreshold = New-TimeSpan -Seconds 450
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS