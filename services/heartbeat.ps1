<# 
.Synopsis
Heartbeat functions for the Overwatch Monitor product
.Description
Maintains heartbeat timers and status.
.Parameter Last
[datetime] The time at which the last heartbeat occurred.
.Parameter Current
[datetime] The time at which the current heartbeat occurred.
.Parameter Next
[datetime] The time at which the next heartbeat occurred.
.Parameter ReportEnabled
[bool] Whether or not reporting is enabled.
.Parameter ReportFrequency
[timespan] The frequency at which heartbeat reports occur.
.Parameter LastReport
[datetime] The time at which the last status report occurred.
.Parameter SinceLastReport
[timespan] The time since the last status report occurred.
.Parameter IsOK
Flag which indicates whether the platform status was OK or NOTOK during the last Monitor check.
.Parameter FlapDetectionEnabled
Flag which indicates whether Overwatch uses flap detection to avoid reporting rapid state changes.  
.Parameter FlapDetectionPeriod
When flap detection is enabled, the period required before Overwatch reports a NOT OK status.
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
    $heartbeat.SinceLastReport = (Get-Date).Subtract($heartbeat.Last)

    return $heartbeat
}

function global:Set-Heartbeat {

    [CmdletBinding()]
    param (
        [switch]$Reported
    )

    $heartbeat = Get-Heartbeat
    $heartbeat.Last = Get-Date
    $heartbeat.IsOK = (Get-PlatformStatus).IsOK
    # $heartbeat.NotOKCount = $heartbeat.IsOK ? 0 : ($notOKCount += 1)

    if ($Reported) {
        $heartbeat.LastReport = Get-Date
    }

    $heartbeat | Write-Cache heartbeat
    
    return $heartbeat
}

function global:Initialize-Heartbeat {

    [CmdletBinding()]
    param()

    $now = Get-Date
    $monitor = Get-Product "Monitor"

    $heartbeat = [Heartbeat]@{
        ReportEnabled = $monitor.Config.ReportEnabled
        ReportSchedule = $monitor.Config.ReportEnabled ? $monitor.Config.ReportSchedule :  [timespan]::Zero
        FlapDetectionEnabled = $monitor.Config.FlapDetectionEnabled
        FlapDetectionPeriod = $monitor.Config.FlapDetectionPeriod
        LastReport = [datetime]::MinValue
        Current = $now
        IsOK = $true
        # NotOKCount = 0
    }

    $heartbeat | Write-Cache heartbeat

    return $heartbeat

}