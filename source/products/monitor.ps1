#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"

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
    $return = $false
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    $return = switch (($serverStatus -split ",")[1]) {
        "InProgress" {$true}
    }
    if ($return) {
        $message = "Exiting due to server status: $serverStatus"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Write-Log -Action "Monitor" -Message $message -EntryType "Warning" -Status "Exiting" -Force
        return
    }

#endregion SERVER
#region PLATFORM

    # check for platform stop/start/restart events
    $return = $false
    $platformStatus = Get-PlatformStatus 
    $return = $platformStatus.RollupStatus -in @("Stopped","Stopping","Starting","Restarting") -or $platformStatus.Event
    if ($return) {
        $message = "Exiting due to platform status: $($platformStatus.RollUpStatus)"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Write-Log -Action "Monitor" -Message $message -EntryType "Warning" -Status "Exiting" -Force
        return
    }
    
    $heartbeat = Get-Heartbeat
    $entryType = $platformStatus.IsOK ? "Information" : "Error"

    $message = "  Current Status : $($platformStatus.IsOK ? "Running" : "Degraded")"
    Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($platformStatus.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator
    $message = "  Previous Status : $($heartbeat.IsOK ? "Running" : "Degraded")"
    Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($heartbeat.IsOK ? "DarkGreen" : "DarkRed" ) -NoSeparator

    if ($platformStatus.IsOK) {
        Update-AsyncJob
    }

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

        $message = "  SHUTDOWN at : $($platformStatus.EventCreatedAt)" # split should specify max-strings=2
        Write-Log -Action "Monitor" -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":",2)[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":",2)[0]).Length)),$message.Split(":",2)[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator
        $message = "  SHUTDOWN by : $($platformStatus.EventCreatedBy)"
        Write-Log -Action "Monitor" -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkYellow -NoSeparator

        if (!$platformStatus.IsStoppedTimeout) {
            Close-Monitor
            return
        } 
        else {
            $platformStatus.Intervention = $true
        }

        $message = "  SHUTDOWN Time Limit Exceeded!"
        Write-Log -Action "Monitor" -EntryType "Warning" -Message $Message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed -NoSeparator

    }

    if ($platformStatus.Event -and !$platformStatus.EventHasCompleted) {

        $message = "  $($platformStatus.Event.ToUpper()) : completed"
        Write-Log -Action "Monitor" -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGreen -NoSeparator

    }

    if ($platformStatus.Intervention) {

        $message = "  INTERVENTION is required!"
        Write-Log -Action "Monitor" -EntryType "Warning" -Message $message
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 25 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkRed -NoSeparator

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