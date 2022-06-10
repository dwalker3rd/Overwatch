#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"
$global:PostflightPreference = "Continue"

# product id must be set before definitions
$global:Product = @{Id="Monitor"}
. $PSScriptRoot\definitions.ps1

function Open-Monitor {
    Write-Host+ -NoTrace "$($Product.Id)","...","RUNNING" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+ -NoTrace ""
}

function Close-Monitor {
    Write-Host+ -NoTrace ""
    Write-Host+ -NoTrace "$($Product.Id)","...","DONE" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+ -NoTrace ""
}

function Send-MonitorMessage {

    param (
        [Parameter(Mandatory=$true)][PlatformStatus]$PlatformStatus,
        [Parameter(Mandatory=$true)][string]$MessageType,
        [switch]$ReportHeartbeat
    )

    $action = $ReportHeartbeat ? "Report" : "Status"
    $target = $ReportHeartbeat ? "Heartbeat" : "Platform"

    Set-CursorInvisible

    Write-Host+
    $message = "  Sending $($target.ToLower()) $($action.ToLower()) : PENDING"
    Write-Host+ -NoTrace -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray -NoSeparator

    Write-Log -Context $global:Product.Id -Action $status -Target $target -Status $PlatformStatus.RollupStatus -Message $message -EntryType "Warning" -Force

    # send platform status message
    Send-PlatformStatusMessage -PlatformStatus $PlatformStatus -MessageType $MessageType -NoThrottle:$ReportHeartbeat.IsPresent

    $message = "$($emptyString.PadLeft(8,"`b")) TRANSMITTED$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DARKGREEN

    Set-CursorVisible

}

Open-Monitor

#region SERVER CHECK

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)

    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $status = "Aborted"
        $message = "$($Product.Id) $($status.ToLower()) because server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Context $($Product.Id) -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

#endregion SERVER CHECK
#region CHECK FOR ASYNC JOBS

    Update-AsyncJob

#endregion CHECK FOR ASYNC JOBS
#region GET STATUS

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

#endregion GET STATUS
#region PLATFORM CHECK

    # abort if platform is stopped or if a platform event is in progress
    if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because "
        if ($platformStatus.IsStopped) {
            $message += "$($Platform.Name) is STOPPED"
        }
        else {
            $message += "platform $($platformStatus.Event.ToUpper()) is $($platformStatus.EventStatus.ToUpper()) on $($Platform.Name)"
        }
        Write-Log -Context $($global:Product.Id) -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($global:Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

#endregion PLATFORM CHECK
#region MAIN

    # heartbeat is initializing:  set heartbeat, exit Monitor
    if (($global:Product.Config.FlapDetectionEnabled -and $heartbeat.RollupStatusPrevious -eq "Pending") -or 
        (!$global:Product.Config.FlapDetectionEnabled -and $heartbeat.RollupStatus -eq "Pending")) {
            $passesRemaining = $global:Product.Config.FlapDetectionEnabled -and $heartbeat.RollupStatus -eq "Pending" ? 2 : 1
            Write-Host+ -MaxBlankLines 1
            Write-Host+ -NoTrace "  Heartbeat has been reset and is initializing"
            Write-Host+ -NoTrace "  Heartbeat initialization will complete in $passesRemaining cycle[s]"
            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
            Close-Monitor
            return
        }
    
    $entryType = $platformStatus.IsOK ? "Information" : "Error"

    Write-Host+ -NoTrace "  Platform Status" -ForegroundColor Gray
    $message = "    Current | $($platformStatus.RollupStatus)"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 48 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator
    if ($heartbeat.Current -ne [datetime]::MinValue) {
        $message = "    $($heartbeat.Current.ToString("u")) | $($heartbeat.RollupStatus)"
        Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 48 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator
    }
    if ($heartbeat.Previous -ne [datetime]::MinValue) {
        $message = "    $($heartbeat.Previous.ToString("u")) | $($heartbeat.RollupStatusPrevious)"
        Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 48 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator
    } 
    Write-Host+

    $platformEventStatusColor = $platformStatus.Event ? ($platformStatus.EventStatus -and $platformStatus.EventStatus -ne $PlatformEventStatus.Completed ? "DarkYellow" : "DarkGreen") : "DarkGray"
    Write-Host+ -NoTrace "  Platform Event" -ForegroundColor Gray
    $message = "    Event | $("$($platformStatus.Event ? $($platformStatus.Event.ToUpper()) : "None")")"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 48 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,$platformEventStatusColor -NoSeparator
    $message = "    Status | $($($platformStatus.EventStatus ? $($platformStatus.EventStatus) : "None"))"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 48 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,$platformEventStatusColor -NoSeparator
    $message = "    Update | $($platformStatus.EventHasCompleted ? $platformStatus.EventCompletedAt : ($platformStatus.Event ? $platformStatus.EventUpdatedAt : "None"))"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 48 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,$platformEventStatusColor -NoSeparator

    # check if time to send scheduled heartbeat report
    $reportHeartbeat = $false
    if ($global:Product.Config.ReportEnabled) {

        switch ($global:Product.Config.ReportSchedule.GetType().Name) {
            "ArrayList" {
                foreach ($slot in $global:Product.Config.ReportSchedule) {
                    if ($slot -gt $heartbeat.PreviousReport -and $slot -le $heartbeat.Current) {
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
    
    # current status OK, previous status OK, previous status before that OK
    # set heartbeat and return
    if ($platformStatus.IsOK -and $heartbeat.IsOK -and $heartbeat.IsOKPrevious) {

        if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
            $message = "  State change (none) : OK => OK"
            Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGreen -NoSeparator
        }

        if ($reportHeartbeat) {
            Set-Heartbeat -PlatformStatus $platformStatus -Reported | Out-Null
            Send-MonitorMessage -PlatformStatus $platformStatus -MessageType $global:PlatformMessageType.Information -ReportHeartbeat
        }
        else {
            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null        
        }

        Close-Monitor
        return
        
    }

    Write-Host+
    $message = "  Flap Detection : $($global:Product.Config.FlapDetectionEnabled ? "Enabled" : "Disabled")"
    Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($global:Product.Config.FlapDetectionEnabled ? "DarkGreen" : "DarkYellow") -NoSeparator

    # flap detection is enabled
    if ($global:Product.Config.FlapDetectionEnabled) {

        # when flap detection is enabled, ignore state flapping (OK => NOT OK; NOT OK => OK)
        # alerts are only triggered when the state has been NOT OK for the flap detection period

        # current status OK, previous status OK, previous status before that NOTOK
        # set heartbeat, proceed with all clear
        if ($platformStatus.IsOK -and $heartbeat.IsOK -and !$heartbeat.IsOKPrevious) {

            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "  State change (none) : OK => OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGreen -NoSeparator
            }

            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null        
            
        }

        # OK => NOT OK
        # platform state is flapping (even if this is the first state transition)
        # no alert until NOT OK state duration exceeds flap detection period
        if (!$platformStatus.IsOK -and $heartbeat.IsOK) {

            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "  State change : OK => NOT OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
            }

            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
            Close-Monitor
            return

        }

        # NOT OK => OK
        # althought this is a state transition from NOT OK => OK, the platform state is still flapping
        # no all clear required
        if ($platformStatus.IsOK -and !$heartbeat.IsOK) {
            
            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "  State change : NOT OK => OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGreen -NoSeparator
            }

            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
            Close-Monitor
            return 

        } 

        # current status NOT OK, previous status NOT OK 
        # platform state is no longer flapping but is consistent
        # check if NOT OK state duration exceeds flap detection period
        # no alert until NOT OK state duration exceeds flap detection period
        if (!$platformStatus.IsOK -and !$heartbeat.IsOK) {
            
            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "  State change (none) : NOT OK => NOT OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
            }

            # NOT OK state has NOT exceeded the flap detection period
            # no alert until NOT OK state duration exceeds flap detection period
            if ((Get-Date)-$heartbeat.Previous -lt $global:Product.Config.FlapDetectionPeriod) {

                $message = "  State assertion : $(((Get-Date)-$heartbeat.Previous).Minutes)m $(((Get-Date)-$heartbeat.Previous).Seconds)s remaining"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
                Write-Log -Context $Product.Id -Action "Flap Detection" -Target "Platform" -Status "Pending" -Message $message -EntryType $entryType -Force
                
                Close-Monitor
                return 

            }
            # NOT OK state has exceeded the flap detection period
            # proceed with alert
            else {

                $message = "  State assertion : NOT OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed -NoSeparator
                Write-Log -Context $Product.Id -Action "Flap Detection" -Target "Platform" -Status $platformStatus.RollupStatus -Message $message -EntryType $entryType -Force

            }

        }          
    }
    else { 
        # no flap detection, state transition from NOT OK => OK
        # set heartbeat, proceed with all clear
        if ($platformStatus.IsOK -and !$heartbeat.IsOK) {
            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
        }    
    }

    # platform is stopped
    # if stop has exceeded stop timeout, set intervention flag
    if ($platformStatus.IsStopped) {

        $message = "  $($platformStatus.Event.ToUpper()) requested at : $($platformStatus.EventCreatedAt)"
        Write-Host+ -NoTrace $message.Split(":",2)[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":",2)[0]).Length)),$message.Split(":",2)[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
        $message = "  $($platformStatus.Event.ToUpper()) requested by : $($platformStatus.EventCreatedBy)"
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator

        if (!$platformStatus.IsStoppedTimeout) {
            Close-Monitor
            return
        } 
        else {
            $platformStatus.Intervention = $true
        }

    }

    # message/log when platform event is active
    if ($platformStatus.Event -and !$platformStatus.EventHasCompleted) {
        $message = "  $($platformStatus.Event.ToUpper()) : $($platformStatus.EventStatus.ToUpper())"
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
    }

    # if intervention flag has been set, request/signal intervention
    # intervention signal/request sent by Send-TaskMessage
    if ($platformStatus.Intervention) {
        $status = "Intervention Required!"
        $message = "  $status : $($platformStatus.InterventionReason)"
        Write-Log -Context $Product.Id -Action "Stop" -Target "Platform" -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed -NoSeparator
        Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Alert -Message $platformStatus.InterventionReason
        Close-Monitor
        return
    }

    # determine message type
    $messageType = $PlatformMessageType.Information
    if ($global:Product.Config.FlapDetectionEnabled -and $platformStatus.IsOK -and $heartbeat.IsOK -and !$heartbeat.IsOKPrevious) { $messageType = $PlatformMessageType.AllClear }
    if (!$global:Product.Config.FlapDetectionEnabled -and $platformStatus.IsOK -and !$heartbeat.IsOK) { $messageType = $PlatformMessageType.AllClear }
    if (!$platformStatus.IsOK) { $messageType = $PlatformMessageType.Alert }

    $entryType = switch ($messageType) {
        $PlatformMessageType.Information { "Information" }
        $PlatformMessageType.AllClear { "Information" }
        $PlatformMessageType.Warning { "Warning" }
        $PlatformMessageType.Alert { "Error" }
    }

    Send-MonitorMessage -PlatformStatus $platformStatus -MessageType $messageType

    Close-Monitor

#endregion MAIN