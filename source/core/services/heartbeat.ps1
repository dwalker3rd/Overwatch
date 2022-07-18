<# 
.Synopsis
Heartbeat functions for the Overwatch Monitor product
.Description
Maintains heartbeat timers and status.
.Parameter Previous
[datetime] The time at which the previous heartbeat occurred.
.Parameter Current
[datetime] The time at which the current heartbeat occurred.
.Parameter Next
[datetime] The time at which the next heartbeat occurred.
.Parameter ReportEnabled
[bool] Whether or not reporting is enabled.
.Parameter ReportFrequency
[timespan] The frequency at which heartbeat reports occur.
.Parameter PreviousReport
[datetime] The time at which the previous status report occurred.
.Parameter SincePreviousReport
[timespan] The time since the previous status report occurred.
.Parameter IsOK
[bool] [bool] Flag which indicates whether the platform status was OK or NOTOK during the previous Monitor check.
.Parameter IsOKPrevious
Flag which indicates whether the previous platform status was OK or NOTOK during the previous Monitor check.
.Parameter FlapDetectionEnabled
[bool] Flag which indicates whether Overwatch uses flap detection to avoid reporting rapid state changes.  
.Parameter FlapDetectionPeriod
[timespan] When flap detection is enabled, the period required before Overwatch reports a NOT OK status.
.Parameter RollupStatus
[string] Platform status description
.Parameter RollupStatusPrevious
[string] Previous platform status description
#>

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

    $heartbeat.Current = Get-Date
    $heartbeat.SincePreviousReport = (Get-Date).Subtract($heartbeat.PreviousReport)

    return $heartbeat
}

function global:Set-Heartbeat {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][PlatformStatus]$PlatformStatus,
        [switch]$Reported
    )

    $heartbeat = Get-Heartbeat
    $heartbeat.Previous = Get-Date
    $heartbeat.IsOKPrevious = $heartbeat.IsOK
    $heartbeat.IsOK = $PlatformStatus.IsOK
    $heartbeat.RollupStatusPrevious = $heartbeat.RollupStatus
    $heartbeat.RollupStatus = $PlatformStatus.RollupStatus

    if ($Reported) {
        $heartbeat.PreviousReport = Get-Date
    }

    $heartbeat | Write-Cache heartbeat
    
    return $heartbeat
}

function global:Initialize-Heartbeat {

    [CmdletBinding()]
    param()

    $now = Get-Date
    # $monitor = Get-Product "Monitor"

    $heartbeat = [Heartbeat]@{
        # ReportEnabled = $monitor.Config.ReportEnabled
        # ReportSchedule = $monitor.Config.ReportEnabled ? $monitor.Config.ReportSchedule :  [timespan]::Zero
        # FlapDetectionEnabled = $monitor.Config.FlapDetectionEnabled
        # FlapDetectionPeriod = $monitor.Config.FlapDetectionPeriod
        PreviousReport = [datetime]::MinValue
        Current = $now
        IsOK = $true
        IsOKPrevious = $true
        RollupStatus = "Pending"
        RollupStatusPrevious = "Pending"
    }

    $heartbeat | Write-Cache heartbeat

    return $heartbeat

}
Set-Alias -Name hbInit -Value Initialize-Heartbeat -Scope Global