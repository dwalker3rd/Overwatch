#region PRODUCT DEFINITIONS

<# 
.Synopsis
Definitions for the Monitor product
.Description
Definitions required by the MicrosoftTeams provider

.Parameter Heartbeat
.Parameter Store
The name of the heartbeat file
.Parameter ReportFrequency
The frequency with which heartbeat messages are sent
.Parameter FlapDetectionEnabled
Skip alert on first error to allow platform time to recover

#>

    . "$($global:Location.Definitions)\classes.ps1"

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
        FlapDetectionEnabled = $true
        FlapDetectionPeriod = New-TimeSpan -Seconds 750
    }

    return $global:Product

#endregion PRODUCT DEFINITIONS