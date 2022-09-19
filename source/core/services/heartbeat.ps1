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
.Parameter Alert
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

$HeartbeatHistoryMax = 72 # 6 hours if the interval is 5 minutes

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
    $properties = $heartbeat.psobject.Properties | Where-Object {$_.name -ne "History"}
    $propertyNameLengths = foreach($property in $properties) {$property.Name.Length}
    $maxLength = ($propertyNameLengths | Measure-Object -Maximum).Maximum

    Write-Host+
    foreach ($property in $properties) {
        $message = "<$($property.Name) < >$($maxLength+2)> "
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Green,DarkGray
        $value = switch ($property.Value.GetType().Name) {
            default { $property.Value}
            "ArrayList" {
                "{$($property.Value -join ", ")}"
            }
        }
        Write-Host+ -NoTrace -NoTimestamp ":",$value -ForegroundColor Green,Gray
    }

    Get-HeartbeatHistory | Select-Object -Property TimeStamp, IsOK, Status, PlatformIsOK, PlatformRollupStatus, Alert, Issues | Format-Table

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
    $heartbeat.Status = $PlatformStatus.RollupStatus
    $heartbeat.PlatformIsOK = $PlatformStatus.IsOK
    $heartbeat.PlatformRollupStatus = $PlatformStatus.RollupStatus
    $heartbeat.Alert = !$IsOK
    $heartbeat.Issues = $PlatformStatus.Issues ?? @()
    $heartbeat.TimeStamp = Get-Date

    if ($Reported) { $heartbeat.PreviousReport = Get-Date }

    # Update heartbeat history onto stack
    Update-HeartbeatHistory -Heartbeat $heartbeat

    $heartbeat | Write-Cache heartbeat
    
    return $heartbeat
}

function global:Initialize-Heartbeat {

    [CmdletBinding()]
    param()

    $heartbeat = [Heartbeat]@{
        IsOK = $true
        Status = "Initializing"
        PlatformIsOK = $true
        PlatformRollupStatus = "Unknown"
        Alert = $false
        Issues = @()
        TimeStamp = [datetime]::Now
        History = @()
        PreviousReport = [datetime]::MinValue
    }

    # Add monitor config settings related to heartbeat
    $heartbeat = Get-HeartbeatSettings -Heartbeat $heartbeat

    $heartbeat | Write-Cache heartbeat

    return $heartbeat

}
Set-Alias -Name hbInit -Value Initialize-Heartbeat -Scope Global

function global:Initialize-HeartbeatHistory {

    [CmdletBinding()]
    param()

    $heartbeatHistory = @()
    $heartbeatHistory += [HeartbeatHistory]@{
        IsOK = $true
        Status = "Initializing"
        PlatformIsOK = $true
        PlatformRollupStatus = "Unknown"
        Alert = $false
        Issues = @()
        TimeStamp = [datetime]::Now
    }

    $heartbeatHistory | Write-Cache heartbeatHistory

    return $heartbeatHistory

}

function global:Get-HeartbeatHistory {

    [CmdletBinding()]
    param ()

    if ($(get-cache heartbeatHistory).Exists()) {
        $heartbeatHistory = [HeartbeatHistory[]](Read-Cache heartbeatHistory)
    }
    else {
        $heartbeatHistory = [HeartbeatHistory[]](Initialize-HeartbeatHistory)
    }

    return $heartbeatHistory
}

function Update-HeartbeatHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$Heartbeat
    )

    $heartbeatHistory = [HeartbeatHistory[]](Get-HeartbeatHistory)

    # if the current heartbeat and the last TWO historical entries are identical, 
    # don't push the heartbeat onto the stack.  instead, just update the timestamp of $heartbeatHistory[0]
    # this allows tracking longer periods of heartbeat data without using as much cache storage
    # checking the last two prevents loss of transitions
    $heartbeatUpdatePrev1 = $heartbeatUpdatePrev2 = $true
    if ($heartbeatHistory.Count -gt 1) {
        $heartbeatUpdatePrev1 = Compare-Object $Heartbeat $heartbeatHistory[0] -Property IsOK,Status,PlatformIsOK,PlatformRollupStatus,Alert,Issues
        $heartbeatUpdatePrev2 = Compare-Object $Heartbeat $heartbeatHistory[1] -Property IsOK,Status,PlatformIsOK,PlatformRollupStatus,Alert,Issues
    }
    if (!$heartbeatUpdatePrev1 -and !$heartbeatUpdatePrev2) {
        $heartbeatHistory[0].TimeStamp = $Heartbeat.TimeStamp
    }
    else {
        if ($heartbeatHistory.Count -lt $HeartbeatHistoryMax) {
            $heartbeatHistory += @{}
        }
        for ($i = $heartbeatHistory.Count-1; $i -gt 0; $i--) {
            $heartbeatHistory[$i] = $heartbeatHistory[$i-1]
        }
        $heartbeatHistory[0] = @{
            IsOK = $Heartbeat.IsOK
            Status = $Heartbeat.Status
            PlatformIsOK = $Heartbeat.PlatformIsOK
            PlatformRollupStatus = $Heartbeat.PlatformRollupStatus
            Alert = $Heartbeat.Alert
            Issues = $Heartbeat.Issues
            TimeStamp = $Heartbeat.TimeStamp
        }
    }

    $heartbeatHistory | Write-Cache heartbeatHistory

    return

}