#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

# product id must be set before definitions
$global:Product = @{Id="Monitor"}
. $PSScriptRoot\definitions.ps1

function Open-Monitor {
    param(
        [Parameter(Mandatory=$false)][string]$Status = "RUNNING",
        [Parameter(Mandatory=$false)][string]$StatusColor = "DarkGreen"
    )
    Write-Host+ -ReverseLineFeed 3
    $message = "<$($Overwatch.DisplayName) $($Product.Id) <.>48> $($Status.ToUpper())"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,$StatusColor 
    Write-Host+
}

function Close-Monitor {
    param(
        [Parameter(Mandatory=$false)][string]$Status = "DONE",
        [Parameter(Mandatory=$false)][string]$StatusColor = "DarkGray"
    )
    Write-Host+ -MaxBlankLines 1
    $message = "<$($Overwatch.DisplayName) $($Product.Id) <.>48> $($Status.ToUpper())"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,$StatusColor 
    Write-Host+
}

function global:Send-MonitorMessage {

    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$false)][string]$MessageType = $ReportHeartbeat ? $global:PlatformMessageType.Heartbeat : $global:PlatformMessageType.Information,
        [switch]$ReportHeartbeat
    )

    $heartbeat = Get-Heartbeat
    $heartbeatHistory = Get-HeartbeatHistory

    $action = $ReportHeartbeat ? "HeartbeatReport" : "StatusChange"
    $target = "Platform"
    $entryType = $heartbeat.IsOK ? "Information" : "Warning"

    # if heartbeat is NOT OK, determine criticality
    # if heartbeat has only been NOT OK for 1 interval: Warning
    # if heartbeat has been NOT OK for more than 2+ intervals: Error
    if (!$heartbeat.IsOK) {
        $errorInterval = 2
        $platformTaskInterval = Get-PlatformTaskInterval -Id $Product.Id
        $isOKTimestamp = ($heartbeatHistory | Where-Object {$_.IsOK})[0].TimeStamp
        if ([datetime]::Now -gt $isOKTimestamp.Add($errorInterval*$platformTaskInterval)) {
            $entryType = "Error"
        }
    }

    Set-CursorInvisible

    Write-Host+
    $message = "<  Sending $($target.ToLower()) $($action.ToLower()) <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    Write-Log -Action $action -Target $target -Status $PlatformStatus.RollupStatus -EntryType $entryType -Force

    # send platform status message
    $messagingStatus = Send-PlatformStatusMessage -PlatformStatus $PlatformStatus -MessageType $MessageType -NoThrottle:$ReportHeartbeat.IsPresent

    $message = "$($emptyString.PadLeft(8,"`b")) $($messagingStatus.ToUpper())$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($messagingStatus -eq $global:PlatformMessageStatus.Transmitted ? "DarkGreen" : "DarkYellow")

    Set-CursorVisible

}

Open-Monitor

#region NOOP CHECK

    $platformStatus = Get-PlatformStatus
    if ($global:Platform.Id -eq "None" -and !$global:TestOverwatchControllers -and $platformStatus.RollupStatus -eq "Running") { 

        Write-Log -Action "NOOPCheck" -Target "Platform.Id" -Status "None" -EntryType "Warning" -Force
        Write-Log -Action "NOOPCheck" -Target "TestOverwatchControllers" -Status "False" -Message $message -EntryType "Warning" -Force
        Write-Log -Action "NOOPCheck" -Target $Product.Id -Status "Disabled" -EntryType "Warning" -Force

        Write-Host+ -NoTrace "  NOOP:  The $($platform.Name) platform has no operations configured" -ForegroundColor DarkYellow
        Write-Host+ -NoTrace "  SHUTDOWN: The $($platform.Name) platform is shutting down" -ForegroundColor DarkYellow

        # send message that this node has no operations
        Send-GenericMessage -MessageType Alert -Message "$($global:Overwatch.Name) $($global:Product.Name) is shutting down because no operations are configured" | Out-Null

        # No need for Monitor to run, so disable the platform task
        Disable-PlatformTask $Product.Id

        # send platformstatus
        Send-PlatformStatusMessage -MessageType Alert | Out-Null

        Close-Monitor -Status Disabled -StatusColor Red
        return 

    }

#endregion NOOP CHECK
#region SERVER CHECK

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)

    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $status = "Aborted"
        $message = "$($Product.Id) $($status.ToLower()) because server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Action "EventCheck" -Target "Server" -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        return
    }

#endregion SERVER CHECK
#region SERVER TRACE

    $nodesToTrace = @()
    $nodesToTrace += pt nodes -k -Online
    if ($global:TestOverwatchControllers) {
        $nodesToTrace += $global:OverwatchControllers
    }
    $nodesToTrace = $nodesToTrace | Sort-Object -Unique
    Test-ServerStatus -ComputerName $nodesToTrace # -Quiet

#endregion SERVER TRACE
#region OFFLINE UNTIL NODES

    $ptUntilNodes = pt nodes -until
    if ($ptUntilNodes.Count -gt 0) {

        Write-Host+ -NoTrace
        $message = "<  Offline Until Nodes <.>48> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+ -SetIndentGlobal 4

        foreach ($node in $ptUntilNodes.Keys) {
            if ([datetime]::Now -gt (pt nodes.$node.Until.Expiry)) {
                ptOffline $node -Shutdown:$($ptUntilNodes.$node.Until.PostAction -eq "Shutdown")
            }
        }

        Write-Host+ -SetIndentGlobal -4
        $message = "<  Offline Until Nodes <.>48> COMPLETED"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    }

#endregion OFFLINE UNTIL NODES
#region PLATFORM NONE

    if ($global:Platform.Id -eq "None") { 
        Close-Monitor
        return 
    }

#endregion PLATFORM NONE
#region UPDATE PLATFORM JOBS

    Update-PlatformJob

#endregion UPDATE PLATFORM JOBS
#region GET STATUS

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

#endregion GET STATUS
#region PLATFORM EVENT

    # platform is stopped
    # set $platformStatus.RollupStatus to "Stopped"
    # if platform is stopped, but has NOT exceeded stop timeout, return
    # if stop has exceeded stop timeout, call for intervention, return
    if ($platformStatus.IsStopped) {

        if ([datetime]::MinValue -ne $platformStatus.EventCreatedAt) {
            $message = "  $($platformStatus.Event.ToUpper()) requested at $($platformStatus.EventCreatedAt)"
            Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        }
        if (![string]::IsNullOrEmpty($platformStatus.EventCreatedBy)) {
            $message = "  $($platformStatus.Event.ToUpper()) requested by $($platformStatus.EventCreatedBy)"
            Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        }

        $platformStatus.RollupStatus = "Stopped"
        Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null    

        if ($platformStatus.IsStoppedTimeout -and $platformStatus.Intervention -and ![string]::IsNullOrEmpty($platformStatus.InterventionReason)) {           
            Write-Log -Action "STOP" -Target "Platform" -Status InterventionRequired -Message $platformStatus.InterventionReason -EntryType "Warning" -Force
            $message = "  $($platformStatus.InterventionReason)"
            Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
            Send-TaskMessage -Id $($Product.Id) -Status $platformStatus.RollupStatus -MessageType $PlatformMessageType.Intervention -Message $platformStatus.InterventionReason | Out-Null
        }

        Close-Monitor
        return

    }

    # a platform event is in progress
    # set $platformStatus.RollupStatus to $platformStatus.EventStatus and return
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {

        $message = "  $($platformStatus.Event.ToUpper()) requested at $($platformStatus.EventCreatedAt)"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        $message = "  $($platformStatus.Event.ToUpper()) requested by $($platformStatus.EventCreatedBy)"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow

        $platformStatus.RollupStatus = switch ($platformStatus.Event) {
            "Stop" { "Stopping" }
            default { "$($platformStatus.Event)ing" }
        }
        Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null   
        # $message = "$($global:Product.Id) $($platformStatus.RollupStatus.ToLower()) because "
        # $message += "Platform $($platformStatus.Event.ToUpper()) $($platformStatus.EventStatus.ToUpper())"
        # Write-Log -Action "EventCheck" -Target "Platform" -Status $platformStatus.RollupStatus -Message $message -EntryType "Warning" -Force
        # Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Close-Monitor
        return
    }

#endregion PLATFORM EVENT
#region HEARTBEAT INIT

    # heartbeat is initializing:  set heartbeat, exit Monitor
    if ($heartbeat.PlatformRollupStatus -eq "Unknown") {
        $passesRemaining = $global:Product.Config.FlapDetectionEnabled -and $heartbeat.PlatformRollupStatus -eq "Pending" ? 2 : 1
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace "  Heartbeat has been reset and is initializing"
        Write-Host+ -NoTrace "  Heartbeat initialization will complete in $passesRemaining cycle[s]"
        Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null
        Close-Monitor
        return
    }

#endregion HEARTBEAT INIT
#region MAIN

    Write-Host+ -NoTrace "  Platform Status (Current)" -ForegroundColor Gray
    $message = "<    IsOK <.>48> $($platformStatus.IsOK)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($platformStatus.IsOK ? "DarkGreen" : "Red" )
    $message = "<    RollupStatus <.>48> $($platformStatus.RollupStatus)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($platformStatus.IsOK ? "DarkGreen" : "Red" )  
    Write-Host+

    Write-Host+ -NoTrace "  Heartbeat (Previous)" -ForegroundColor Gray
    $message = "<    IsOK <.>48> $($heartbeat.IsOK)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "Red" )
    $message = "<    PlatformIsOK <.>48> $($heartbeat.PlatformIsOK)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.PlatformIsOK ? "DarkGreen" : "Red" )
    $message = "<    PlatformRollupStatus <.>48> $($heartbeat.PlatformRollupStatus)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.PlatformIsOK ? "DarkGreen" : "Red" )
    $message = "<    Alert <.>48> $($heartbeat.Alert ? "Alert" : "AllClear")"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.Alert ? "Red" : "DarkGreen" )
    Write-Host+

    # check if time to send scheduled heartbeat report
    $reportHeartbeat = $false
    if ($global:Product.Config.ReportEnabled) {

        switch ($global:Product.Config.ReportSchedule.GetType().Name) {
            "ArrayList" {
                foreach ($slot in $global:Product.Config.ReportSchedule) {
                    if ($slot -gt $heartbeat.PreviousReport -and $slot -le $heartbeat.TimeStamp) {
                        $reportHeartbeat = $true
                        break
                    }
                }
            }
            "TimeSpan" {
                $reportHeartbeat = $heartbeat.SincePreviousReport.TotalMinutes -lt $global:Product.Config.ReportSchedule.TotalMinutes
            }
        }
    
    }

    $message = "<  Flap Detection <.>48> $($global:Product.Config.FlapDetectionEnabled ? "Enabled" : "Disabled")"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($global:Product.Config.FlapDetectionEnabled ? "DarkGreen" : "DarkYellow")

    # flap detection is enabled
    if ($global:Product.Config.FlapDetectionEnabled) {

        # when flap detection is enabled, ignore state flapping (OK => NOT OK; NOT OK => OK)
        # alerts are only triggered when the state has been NOT OK for the flap detection period

        # HEARTBEAT
        # platform status OK, heartbeat status OK, NOT in alert
        # set heartbeat, send HEARTBEAT [report] at scheduled time
        if ($platformStatus.IsOK -and $heartbeat.PlatformIsOK -and !$heartbeat.Alert) {

            $message = "<  State assertion <.>48> OK"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

            if ($reportHeartbeat) {
                Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true -Reported | Out-Null
                Send-MonitorMessage -PlatformStatus $platformStatus -ReportHeartbeat | Out-Null
            }
            else {
                Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null        
            }

            Close-Monitor
            return
            
        }

        # ALLCLEAR
        # in alert, platform status OK, heartbeat status OK
        # set heartbeat, send ALLCLEAR message
        if ($platformStatus.IsOK -and $heartbeat.PlatformIsOK -and $heartbeat.Alert) {

            $message = "<  State assertion <.>48> OK (ALLCLEAR)"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

            Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null       
            $messageType = $PlatformMessageType.AllClear
            
        }

        # FLAPPING
        # set heartbeat, return
        if ($platformStatus.IsOK -ne $heartbeat.PlatformIsOK) {

            $message =  "<  State change <.>48> $($platformStatus.IsOK ? "NOT OK => OK" : "OK => NOT OK")"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow

            Set-Heartbeat -PlatformStatus $platformStatus -IsOK $heartbeat.IsOK | Out-Null
            Close-Monitor
            return

        }

        # ALERT
        # platform status NOT OK, heartbeat status NOT OK 
        # platform state is no longer flapping but is consistent
        # set heartbeat, send alert
        if (!$platformStatus.IsOK -and !$heartbeat.PlatformIsOK) {

            $message = "<  State assertion <.>48> NOT OK (ALERT)"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,Red

            Set-Heartbeat -PlatformStatus $platformStatus -IsOK $false | Out-Null
            $messageType = $PlatformMessageType.Alert

        }          
    }
    else {
        
        # no flap detection

        # HEARTBEAT
        # platform status OK
        # set heartbeat, send HEARTBEAT [report] at scheduled time
        if ($platformStatus.IsOK -and $heartbeat.PlatformIsOK) {

            $message = "<  State assertion <.>48> OK"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

            if ($reportHeartbeat) {
                Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true -Reported | Out-Null
                Send-MonitorMessage -PlatformStatus $platformStatus -ReportHeartbeat | Out-Null
            }
            else {
                Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null        
            }

            Close-Monitor
            return
            
        }

        # state transition from OK => NOT OK
        # set heartbeat, proceed with alert
        if (!$platformStatus.IsOK -and $heartbeat.PlatformIsOK) {
            Set-Heartbeat -PlatformStatus $platformStatus -IsOK $false | Out-Null
            $messageType = $PlatformMessageType.Alert
        }   

        # state transition from NOT OK => OK
        # set heartbeat, proceed with all clear
        if ($platformStatus.IsOK -and !$heartbeat.PlatformIsOK) {
            Set-Heartbeat -PlatformStatus $platformStatus -IsOK $true | Out-Null
            $messageType = $PlatformMessageType.AllClear
        }    

    }

    $heartbeat = Get-Heartbeat
    $heartbeatHistory = Get-HeartbeatHistory
    if (Compare-Object $heartbeatHistory[0] $heartbeatHistory[1] -Property IsOK,PlatformIsOK,PlatformRollupStatus) {
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace "  Heartbeat (Current)" -ForegroundColor Gray
        $message = "<    IsOK <.>48> $($heartbeat.IsOK)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "Red" )
        $message = "<    PlatformIsOK <.>48> $($heartbeat.PlatformIsOK)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.PlatformIsOK ? "DarkGreen" : "Red" )
        $message = "<    PlatformRollupStatus <.>48> $($heartbeat.PlatformRollupStatus)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.PlatformIsOK ? "DarkGreen" : "Red" )
        $message = "<    Alert <.>48> $($heartbeat.Alert ? "Alert" : "AllClear")"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.Alert ? "Red" : "DarkGreen" )
    }

    Send-MonitorMessage -PlatformStatus $platformStatus -MessageType $messageType | Out-Null

    Close-Monitor

    Remove-PSSession+

#endregion MAIN