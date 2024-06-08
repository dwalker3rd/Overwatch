#region PRODUCT DEFINITIONS

    <# 
    .Synopsis
    Definitions for the Monitor product
    .Description
    Definitions required by the MicrosoftTeams provider
    .Parameter ReportEnabled
    [bool] Flag which indicates whether heartbeat reports are enabled/disabled.
    .Parameter ReportSchedule
    [timespan] or [arraylist] The amount of time between heartbeat reports.
    #>

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

    $global:Product = $global:Catalog.Product.Monitor
    $global:Product.DisplayName = "$($global:Overwatch.Name) $($global:Product.Name) for $($global:Platform.Name)"
    $global:Product.TaskName = $global:Product.DisplayName
    $global:Product.Description = "Monitors the health and activity of the $($global:Platform.Name) platform."
    $global:Product.HasTask = $true
    $global:Product.Config = @{
        ReportEnabled = $true
        ReportSchedule = @(
            (Get-Date -Hour 5 -Minute 0 -Second 0 -AsUTC),
            (Get-Date -Hour 13 -Minute 0 -Second 0 -AsUTC)
        )
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS