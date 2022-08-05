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

    [Heartbeat[]]$heartbeat.History | Select-Object -Property TimeStamp, IsOK, Status, PlatformIsOK, PlatformRollupStatus, Alert, Issues | Format-Table

}

function Push-HeartbeatHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$Heartbeat
    )

    # if the current heartbeat and the last historical entry are identical, 
    # don't push the heartbeat onto the stack.  instead, just update the timestamp of $Heartbeat.History[0]
    # this allows tracking longer periods of heartbeat data without using as much cache storage
    if ($Heartbeat.History.Count -gt 0) {
        $heartbeatUpdate = Compare-Object $heartbeat $heartbeat.History[0] -Property IsOK,Status,PlatformIsOK,PlatformRollupStatus,Alert,Issues
        if (!$heartbeatUpdate) {
            $Heartbeat.History[0].TimeStamp = $Heartbeat.TimeStamp
            return
        }
    }

    if ($Heartbeat.History.Count -lt $HeartbeatHistoryMax) {
        $Heartbeat.History += @{}
    }
    for ($i = $Heartbeat.History.Count-1; $i -gt 0; $i--) {
        $Heartbeat.History[$i] = $Heartbeat.History[$i-1]
    }
    
    $Heartbeat.History[0] = @{
        IsOK = $Heartbeat.IsOK
        Status = $Heartbeat.Status
        PlatformIsOK = $Heartbeat.PlatformIsOK
        PlatformRollupStatus = $Heartbeat.PlatformRollupStatus
        Alert = $Heartbeat.Alert
        Issues = $Heartbeat.Issues
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
    $heartbeat.Status = $PlatformStatus.RollupStatus
    $heartbeat.PlatformIsOK = $PlatformStatus.IsOK
    $heartbeat.PlatformRollupStatus = $PlatformStatus.RollupStatus
    $heartbeat.Alert = !$IsOK
    $heartbeat.Issues = $PlatformStatus.Issues
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
        Status = "Initializing"
        PlatformIsOK = $true
        PlatformRollupStatus = "Unknown"
        Alert = $false
        Issues = @()
        TimeStamp = [datetime]::Now
        History = @()
        PreviousReport = [datetime]::MinValue
    }

    $heartbeat.History += @{
        IsOK = $Heartbeat.IsOK
        Status = $Heartbeat.Status
        PlatformIsOK = $Heartbeat.PlatformIsOK
        PlatformRollupStatus = $Heartbeat.PlatformRollupStatus
        Alert = $Heartbeat.Alert
        Issues = $Heartbeat.Issues
        TimeStamp = $Heartbeat.TimeStamp
    }

    # Add monitor config settings related to heartbeat
    $heartbeat = Get-HeartbeatSettings -Heartbeat $heartbeat

    $heartbeat | Write-Cache heartbeat

    return $heartbeat

}
Set-Alias -Name hbInit -Value Initialize-Heartbeat -Scope Global