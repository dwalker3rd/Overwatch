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
    Write-Host+ -NoTrace "$($Product.Id)","...","RUNNING" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+ -NoTrace ""
}

function Close-Monitor {
    Write-Host+ -NoTrace ""
    Write-Host+ -NoTrace "$($Product.Id)","...","DONE" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+ -NoTrace ""
}

function global:Send-MonitorMessage {

    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$false)][string]$MessageType = $ReportHeartbeat ? $global:PlatformMessageType.Heartbeat : $global:PlatformMessageType.Information,
        [switch]$ReportHeartbeat
    )

    $action = $ReportHeartbeat ? "Report" : "Status"
    $target = $ReportHeartbeat ? "Heartbeat" : "Platform"

    Set-CursorInvisible

    Write-Host+
    $message = "<  Sending $($target.ToLower()) $($action.ToLower()) <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    Write-Log -Context $global:Product.Id -Action $status -Target $target -Status $PlatformStatus.RollupStatus -Message "Sending $($target.ToLower()) $($action.ToLower())" -EntryType "Warning" -Force

    # send platform status message
    $messagingStatus = Send-PlatformStatusMessage -PlatformStatus $PlatformStatus -MessageType $MessageType -NoThrottle:$ReportHeartbeat.IsPresent
    $messagingStatus | Out-Null

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
    
    # $entryType = $platformStatus.IsOK ? "Information" : "Error"

    Write-Host+ -NoTrace "  Platform Status" -ForegroundColor Gray
    $message = "<    Current <.>48> $($platformStatus.RollupStatus)"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.IsOKCurrent ? "DarkGreen" : "DarkRed" )
    if ($heartbeat.Current -ne [datetime]::MinValue) {
        $message = "<    $($heartbeat.Current.ToString("u")) <.>48> $($heartbeat.RollupStatus)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.IsOKCurrent ? "DarkGreen" : "DarkRed" )
    }
    if ($heartbeat.Previous -ne [datetime]::MinValue) {
        $message = "<    $($heartbeat.Previous.ToString("u")) <.>48> $($heartbeat.RollupStatusPrevious)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($heartbeat.IsOKCurrent ? "DarkGreen" : "DarkRed" )
    } 
    Write-Host+

    $platformEventStatusColor = $platformStatus.Event ? ($platformStatus.EventStatus -and $platformStatus.EventStatus -ne $PlatformEventStatus.Completed ? "DarkYellow" : "DarkGreen") : "DarkGray"
    Write-Host+ -NoTrace "  Platform Event" -ForegroundColor Gray
    $message = "<    Event <.>48> $("$($platformStatus.Event ? $($platformStatus.Event.ToUpper()) : "None")")"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$platformEventStatusColor
    $message = "<    Status <.>48> $($($platformStatus.EventStatus ? $($platformStatus.EventStatus) : "None"))"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$platformEventStatusColor
    $message = "<    Update <.>48> $($platformStatus.EventHasCompleted ? $platformStatus.EventCompletedAt : ($platformStatus.Event ? $platformStatus.EventUpdatedAt : "None"))"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$platformEventStatusColor

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
    if ($platformStatus.IsOK -and $heartbeat.IsOKCurrent -and $heartbeat.IsOKPrevious) {

        if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
            $message = "<  State change (none) <.>48> OK => OK"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGreen
        }

        if ($reportHeartbeat) {
            Set-Heartbeat -PlatformStatus $platformStatus -Reported | Out-Null
            Send-MonitorMessage -PlatformStatus $platformStatus -ReportHeartbeat
        }
        else {
            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null        
        }

        Close-Monitor
        return
        
    }

    Write-Host+
    $message = "<  Flap Detection <.>48> $($global:Product.Config.FlapDetectionEnabled ? "Enabled" : "Disabled")"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($global:Product.Config.FlapDetectionEnabled ? "DarkGreen" : "DarkYellow")

    # flap detection is enabled
    if ($global:Product.Config.FlapDetectionEnabled) {

        # when flap detection is enabled, ignore state flapping (OK => NOT OK; NOT OK => OK)
        # alerts are only triggered when the state has been NOT OK for the flap detection period

        # current status OK, previous status OK, previous status before that NOTOK
        # set heartbeat, proceed with all clear
        if ($platformStatus.IsOK -and $heartbeat.IsOKCurrent -and !$heartbeat.IsOKPrevious) {

            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "<  State change (none) <.>48> OK => OK"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGreen
            }

            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null        
            
        }

        # OK => NOT OK
        # platform state is flapping (even if this is the first state transition)
        # no alert until NOT OK state duration exceeds flap detection period
        if (!$platformStatus.IsOK -and $heartbeat.IsOKCurrent) {

            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "<  State change <.>48> OK => NOT OK"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
            }

            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
            Close-Monitor
            return

        }

        # NOT OK => OK
        # althought this is a state transition from NOT OK => OK, the platform state is still flapping
        # no all clear required
        if ($platformStatus.IsOK -and !$heartbeat.IsOKCurrent) {
            
            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "<  State change <.>48> NOT OK => OK"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
            }

            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
            Close-Monitor
            return 

        } 

        # current status NOT OK, previous status NOT OK 
        # platform state is no longer flapping but is consistent
        # check if NOT OK state duration exceeds flap detection period
        # no alert until NOT OK state duration exceeds flap detection period
        if (!$platformStatus.IsOK -and !$heartbeat.IsOKCurrent) {
            
            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "<  State change (none) <.>48> NOT OK => NOT OK"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
            }

            # NOT OK state has NOT exceeded the flap detection period
            # no alert until NOT OK state duration exceeds flap detection period
            if ((Get-Date)-$heartbeat.Previous -lt $global:Product.Config.FlapDetectionPeriod) {

                $message = "<  State assertion <.>48> $(((Get-Date)-$heartbeat.Previous).Minutes)m $(((Get-Date)-$heartbeat.Previous).Seconds)s remaining"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
                # Write-Log -Context $Product.Id -Action "Flap Detection" -Target "Platform" -Status "Pending" -Message $message -EntryType $entryType -Force
                
                Close-Monitor
                return 

            }
            # NOT OK state has exceeded the flap detection period
            # proceed with alert
            else {

                $message = "<  State assertion <.>48> NOT OK"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkRed
                # Write-Log -Context $Product.Id -Action "Flap Detection" -Target "Platform" -Status $platformStatus.RollupStatus -Message $message -EntryType $entryType -Force

            }

        }          
    }
    else { 
        # no flap detection, state transition from NOT OK => OK
        # set heartbeat, proceed with all clear
        if ($platformStatus.IsOK -and !$heartbeat.IsOKCurrent) {
            Set-Heartbeat -PlatformStatus $platformStatus | Out-Null
        }    
    }

    # platform is stopped
    # if stop has exceeded stop timeout, set intervention flag
    if ($platformStatus.IsStopped) {

        $message = "<  $($platformStatus.Event.ToUpper()) requested at <.>48> $($platformStatus.EventCreatedAt)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
        $message = "<  $($platformStatus.Event.ToUpper()) requested by <.>48> $($platformStatus.EventCreatedBy)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow

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
        $message = "<  $($platformStatus.Event.ToUpper()) <.>48> $($platformStatus.EventStatus.ToUpper())"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
    }

    # if intervention flag has been set, request/signal intervention
    # intervention signal/request sent by Send-TaskMessage
    if ($platformStatus.Intervention) {
        $status = "Intervention Required!"
        $logMessage = "  $status : $($platformStatus.InterventionReason)"
        Write-Log -Context $Product.Id -Action "Stop" -Target "Platform" -Status $status -Message $logMessage -EntryType "Warning" -Force
        $message = "<  $status <.>48> $($platformStatus.InterventionReason)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkRed
        Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Alert -Message $platformStatus.InterventionReason
        Close-Monitor
        return
    }

    # determine message type
    $messageType = $PlatformMessageType.Information
    if ($global:Product.Config.FlapDetectionEnabled -and $platformStatus.IsOK -and $heartbeat.IsOKCurrent -and !$heartbeat.IsOKPrevious) { $messageType = $PlatformMessageType.AllClear }
    if (!$global:Product.Config.FlapDetectionEnabled -and $platformStatus.IsOK -and !$heartbeat.IsOKCurrent) { $messageType = $PlatformMessageType.AllClear }
    if (!$platformStatus.IsOK) { $messageType = $PlatformMessageType.Alert }

    # $entryType = switch ($messageType) {
    #     $PlatformMessageType.Information { "Information" }
    #     $PlatformMessageType.AllClear { "Information" }
    #     $PlatformMessageType.Warning { "Warning" }
    #     $PlatformMessageType.Alert { "Error" }
    # }

    Send-MonitorMessage -PlatformStatus $platformStatus -MessageType $messageType

    Close-Monitor

#endregion MAIN