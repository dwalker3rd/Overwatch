<# 
.Synopsis
Heartbeat functions for the Overwatch Monitor product.
.Description
Maintains heartbeat status and history.
.Parameter IsOK
Flag (set by the Monitor product) which indicates the overall status of the platform.
.Parameter PlatformIsOK
Flag (set by the platform) which indicates the current status of the platform.
.Parameter PlatformRollupStatus
[string] Status description (set by the platform).
.Parameter PlatformAlert
Flag which indicates whether the platform has an active alert.
.Parameter PlatformTimeStamp
[datetime] Heartbeat timestamp.
.Parameter ReportEnabled
[bool] Whether or not reporting is enabled.
.Parameter ReportFrequency
[timespan] The frequency at which heartbeat reports occur.
.Parameter PreviousReport
[datetime] The time at which the previous status report occurred.
.Parameter SincePreviousReport
[timespan] The time SINCE the previous status report occurred.
.Parameter FlapDetectionEnabled
[bool] Flag which indicates whether Overwatch uses flap detection to avoid reporting rapid state changes.  
.Parameter FlapDetectionPeriod
[timespan] When flap detection is enabled, the period required before Overwatch reports a NOT OK status.
#>

function Get-HeartbeatSettings {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$Heartbeat
    )

    $monitor = Get-Product "Monitor"
    
    $Heartbeat.ReportEnabled = $monitor.Config.ReportEnabled
    $Heartbeat.ReportSchedule = $monitor.Config.ReportEnabled ? $monitor.Config.ReportSchedule :  [timespan]::Zero
    $Heartbeat.FlapDetectionEnabled = $monitor.Config.FlapDetectionEnabled
    $Heartbeat.FlapDetectionPeriod = $monitor.Config.FlapDetectionPeriod

    return $Heartbeat

}

function global:Get-Heartbeat {

    [CmdletBinding()]
    param ()

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    if ($(get-cache heartbeat).Exists()) {
        $heartbeat = Read-Cache heartbeat 
    }
    else {
        $heartbeat = Initialize-Heartbeat 
    }

    $heartbeat.SincePreviousReport = (Get-Date).Subtract($heartbeat.PreviousReport)

    return $heartbeat
}

function global:Show-Heartbeat {

    $heartbeat = Get-Heartbeat
    $heartbeat | Select-Object -ExcludeProperty History

    [Heartbeat[]]$heartbeat.History | Select-Object -Property TimeStamp, IsOK, PlatformIsOK, PlatformRollupStatus, PlatformAlert | Format-Table

}

function Push-HeartbeatHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$Heartbeat
    )

    for ($i = $Heartbeat.History.Count-1; $i -gt 0; $i--) {
        $Heartbeat.History[$i] = $Heartbeat.History[$i-1]
    }
    
    $Heartbeat.History[0] = @{
        IsOK = $Heartbeat.IsOK
        PlatformIsOK = $Heartbeat.PlatformIsOK
        PlatformRollupStatus = $Heartbeat.PlatformRollupStatus
        PlatformAlert = $Heartbeat.PlatformAlert
        TimeStamp = $Heartbeat.TimeStamp
    }

    return

}

function global:Set-Heartbeat {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$true)][bool]$IsOK,
        [switch]$Reported
    )

    $heartbeat = Get-Heartbeat

    # Refresh monitor config settings related to heartbeat
    $heartbeat = Get-HeartbeatSettings -Heartbeat $heartbeat

    $heartbeat.IsOK = $IsOK
    $heartbeat.PlatformIsOK = $PlatformStatus.IsOK
    $heartbeat.PlatformRollupStatus = $PlatformStatus.RollupStatus
    $heartbeat.PlatformAlert = !$IsOK
    $heartbeat.TimeStamp = Get-Date

    if ($Reported) { $heartbeat.PreviousReport = Get-Date }

    # Push heartbeat history onto stack
    Push-HeartbeatHistory -Heartbeat $heartbeat

    $heartbeat | Write-Cache heartbeat
    
    return $heartbeat
}

function global:Initialize-Heartbeat {

    [CmdletBinding()]
    param()

    $heartbeat = [Heartbeat]@{
        IsOK = $true
        PlatformIsOK = $true
        PlatformRollupStatus = "Pending"
        PlatformAlert = $false
        TimeStamp = [datetime]::MinValue
        History = [object[]]::new(10)
        PreviousReport = [datetime]::MinValue
    }

    # Add monitor config settings related to heartbeat
    $heartbeat = Get-HeartbeatSettings -Heartbeat $heartbeat

    $heartbeat | Write-Cache heartbeat

    return $heartbeat

}
Set-Alias -Name hbInit -Value Initialize-Heartbeat -Scope Global