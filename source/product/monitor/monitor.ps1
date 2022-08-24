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
    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace "$($Product.Id)","...","DONE" -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+
}


function global:Send-MonitorMessage {

    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$false)][string]$MessageType = $ReportHeartbeat ? $global:PlatformMessageType.Heartbeat : $global:PlatformMessageType.Information,
        [switch]$ReportHeartbeat
    )

    $heartbeat = Get-Heartbeat

    $action = $ReportHeartbeat ? "Report" : "Status"
    $target = $ReportHeartbeat ? "Heartbeat" : "Platform"
    $entryType = $heartbeat.IsOK ? "Information" : "Warning"

    # if heartbeat is NOT OK, determine criticality
    # if heartbeat has only been NOT OK for 1 interval: Warning
    # if heartbeat has been NOT OK for more than 2+ intervals: Error
    if (!$heartbeat.IsOK) {
        $errorInterval = 2
        $platformTaskInterval = Get-PlatformTaskInterval -Id $Product.Id
        $isOKTimestamp = ($heartbeat.History | Where-Object {$_.IsOK})[0].TimeStamp
        if ([datetime]::Now -gt $isOKTimestamp.Add($errorInterval*$platformTaskInterval)) {
            $entryType = "Error"
        }
    }

    Set-CursorInvisible

    Write-Host+
    $message = "<  Sending $($target.ToLower()) $($action.ToLower()) <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    Write-Log -Context $global:Product.Id -Action $action -Target $target -Status $heartbeat.RollupStatus -Message "Sending $($target.ToLower()) $($action.ToLower())" -EntryType $entryType -Force

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
        Write-Log -Context $($Product.Id) -Action "EventCheck" -Target "Server" -Status $status -Message $message -EntryType "Warning" -Force
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
#region PLATFORM EVENT

    # platform is stopped
    # if stop has exceeded stop timeout, call for intervention
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
            $status = "Intervention Required!"
            $logMessage = "  $status : $($platformStatus.InterventionReason)"
            Write-Log -Context $Product.Id -Action "EventCheck" -Target "Platform" -Status $status -Message $logMessage -EntryType "Warning" -Force
            $message = "<  $status <.>48> $($platformStatus.InterventionReason)"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,Red
            Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Alert -Message $platformStatus.InterventionReason
            Close-Monitor
            return
        }

    }

    # abort if platform is stopped or if a platform event is in progress
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because "
        $message += "platform $($platformStatus.Event.ToUpper()) is $($platformStatus.EventStatus.ToUpper()) on $($Platform.Name)"
        Write-Log -Context $($global:Product.Id) -Action "EventCheck" -Target "Platform" -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
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
                Send-MonitorMessage -PlatformStatus $platformStatus -ReportHeartbeat
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
                Send-MonitorMessage -PlatformStatus $platformStatus -ReportHeartbeat
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
    if (compare-object $heartbeat.history[0] $heartbeat.history[1] -property IsOK,PlatformIsOK,PlatformRollupStatus) {
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

    Send-MonitorMessage -PlatformStatus $platformStatus -MessageType $messageType

    Close-Monitor

#endregion MAI