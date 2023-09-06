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

    $global:Product = $global:Catalog.Product.SSOMonitor
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Monitors the ssoLogger on the $($global:Platform.Name) platform."
    $global:Product.HasTask = $true

    $global:Product.Config = @{
        SleepUnits = "Seconds"
        SleepDuration = 60
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS