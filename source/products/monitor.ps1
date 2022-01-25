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
    # Write-Host+ ""
    Write-Host+ -NoTrace "$($Product.Id)","...","RUNNING" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+ -NoTrace ""
}

function Close-Monitor {
    Write-Host+ -NoTrace ""
    Write-Host+ -NoTrace "$($Product.Id)","...","DONE" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+ -NoTrace ""
}

Open-Monitor

#region SERVER

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)

    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $status = "Aborted"
        $message = "$($Product.Id) $($status.ToLower()) because server $(($serverStatus -split ".")[0].ToUpper()) is $(($serverStatus -split ".")[1].ToUpper())"
        Write-Log -Context $($Product.Id) -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

#endregion SERVER
#region PLATFORM
    
    $heartbeat = Get-Heartbeat
    $platformStatus = Get-PlatformStatus 
    $entryType = $platformStatus.IsOK ? "Information" : "Error"

    Write-Host+ -NoTrace "  Platform Status" -ForegroundColor Gray
    $message = "    Current : $($platformStatus.IsOK ? "Running" : "Degraded")"
    Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($platformStatus.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator
    $message = "    Previous : $($heartbeat.IsOK ? "Running" : "Degraded")"
    Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator
    Write-Host+

    $platformEventStatusColor = $platformStatus.Event ? ($platformStatus.EventStatus -and $platformStatus.EventStatus -ne $PlatformEventStatus.Completed ? "DarkYellow" : "DarkGreen") : "DarkGray"
    Write-Host+ -NoTrace "  Platform Event" -ForegroundColor Gray
    $message = "    Event | $("$($platformStatus.Event ? $($platformStatus.Event.ToUpper()) : "None")")"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 25 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,$platformEventStatusColor -NoSeparator
    $message = "    Status | $($($platformStatus.EventStatus ? $($platformStatus.EventStatus) : "None"))"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 25 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,$platformEventStatusColor -NoSeparator
    $message = "    Update | $($platformStatus.EventHasCompleted ? $platformStatus.EventCompletedAt : ($platformStatus.Event ? $platformStatus.EventUpdatedAt : "None"))"
    Write-Host+ -NoTrace $message.Split("|")[0],(Write-Dots -Length 25 -Adjust (-($message.Split("|")[0]).Length)),$message.Split("|")[1] -ForegroundColor Gray,DarkGray,$platformEventStatusColor -NoSeparator
    Write-Host+

    Update-AsyncJob

    # check if time to send heartbeat
    $reportHeartbeat = $false
    if ($heartbeat.ReportEnabled) {

        switch ($heartbeat.ReportSchedule.GetType().Name) {
            "ArrayList" {
                foreach ($slot in $heartbeat.ReportSchedule) {
                    if ($slot -gt $heartbeat.LastReport -and $slot -le $heartbeat.Current) {
                        $reportHeartbeat = $true
                        break
                    }
                }
            }
            "TimeSpan" {
                $reportHeartbeat = $heartbeat.SinceLastReport.TotalMinutes -lt $heartbeat.ReportSchedule.TotalMinutes
            }
        }
    
    }
    
    # current status OK, previous status OK
    if ($platformStatus.IsOK -and $heartbeat.IsOK) {

        if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
            $message = "  State change (none) : OK => OK"
            Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGreen -NoSeparator
            Write-Log -EntryType $entryType -Action "Heartbeat" -Message $message
        }

        if ($reportHeartbeat) {
            Set-Heartbeat -Reported | Out-Null
        }
        else {
            Set-Heartbeat | Out-Null        
            Close-Monitor
            return
        }
        

    }

    $message = "  Flap Detection : $($heartbeat.FlapDetectionEnabled ? "Enabled" : "Disabled")"
    Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($heartbeat.FlapDetectionEnabled ? "DarkGreen" : "DarkYellow") -NoSeparator
    Write-Log -EntryType $entryType -Action "Heartbeat" -Message $message

    if ($heartbeat.FlapDetectionEnabled) {

        # current status NOT OK, previous status OK
        if (!$platformStatus.IsOK -and $heartbeat.IsOK) {

            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "  State change : OK => NOT OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
                Write-Log -EntryType $entryType -Action "Heartbeat" -Message $message
            }

            Set-Heartbeat | Out-Null
            Close-Monitor
            return

        }

        # current status NOT OK, previous status NOT OK 
        # check FlapDetectionPeriod
        if (!$platformStatus.IsOK -and !$heartbeat.IsOK) {
            
            if ($VerbosePreference -eq "Continue" -or $global:DebugPreference -eq "Continue") {
                $message = "  State change (none) : NOT OK => NOT OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
                Write-Log -EntryType $entryType -Action "Heartbeat" -Message $message
            }

            if ((Get-Date)-$heartbeat.Last -lt $heartbeat.FlapDetectionPeriod) {
                $message = "  State assertion : $(((Get-Date)-$heartbeat.Last).Minutes)m $(((Get-Date)-$heartbeat.Last).Seconds)s remaining"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
                Write-Log -EntryType $entryType -Action "Heartbeat" -Message $message
                
                Close-Monitor
                return 
            }
            else {
                $message = "  State assertion : NOT OK"
                Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed -NoSeparator
                Write-Log -EntryType $entryType -Action "Heartbeat" -Message $message
            }

        }          
    } 

    # all clear
    if ($platformStatus.IsOK -and !$heartbeat.IsOK) {
        Set-Heartbeat | Out-Null
    }

    if ($platformStatus.IsStopped) {

        $message = "  $($platformStatus.Event.ToUpper()) requested at : $($platformStatus.EventCreatedAt)" # split should specify max-strings=2
        Write-Log -Action $($Product.Id) -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":",2)[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":",2)[0]).Length)),$message.Split(":",2)[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
        $message = "  $($platformStatus.Event.ToUpper()) requested by : $($platformStatus.EventCreatedBy)"
        Write-Log -Action $($Product.Id) -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator

        if (!$platformStatus.IsStoppedTimeout) {
            Close-Monitor
            return
        } 
        else {
            $platformStatus.Intervention = $true
        }

    }

    if ($platformStatus.Event -and !$platformStatus.EventHasCompleted) {

        $message = "  $($platformStatus.Event.ToUpper()) : $($platformStatus.EventStatus.ToUpper())"
        Write-Log -Action $($Product.Id) -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator

    }

    if ($platformStatus.Intervention) {

        $status = "Intervention"
        $message = "  $status : $($platformStatus.InterventionReason)"
        Write-Log -Action $($Product.Id) -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed -NoSeparator
        Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Alert -Message $platformStatus.InterventionReason

    }

    $messageType = $PlatformMessageType.Information
    if ($platformStatus.IsOK) {
        if (!$heartbeat.IsOK) {
            $messageType = $PlatformMessageType.AllClear
        }
    }
    else {
        $messageType = $PlatformMessageType.Alert
    }

    $message = "  Sending message : SENT"
    Write-Host+ -NoTrace -NoNewLine $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)) -ForegroundColor Gray,DarkGray -NoSeparator

    Send-PlatformStatusMessage -PlatformStatus $platformStatus -MessageType $messageType

    Write-Host+ -NoTrace -NoTimeStamp $message.Split(":")[1] -ForegroundColor DarkGreen -NoSeparator

    Close-Monitor

#endregion PLATFORM