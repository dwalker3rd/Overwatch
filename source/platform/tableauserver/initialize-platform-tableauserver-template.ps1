#region INIT

Set-CursorInvisible

Write-Host+
$message = "<Platform Initialization <.>48> PENDING"
Write-Host+ -NoTrace -Parse -NoNewLine $message -ForegroundColor DarkBlue,DarkGray,DarkGray
$newLineWritten = $false

#region TEST

    # this section ensures that the TableauServerTsmApi provider is running/working
    $prerequisiteTestResults = Test-Prerequisites -Type "Provider" -Id "TableauServerTsmApi" -Quiet
    if (!$prerequisiteTestResults.Pass) {
        Write-Host+; $newLineWritten = $true
        # if the TableauServerTsmApi provider is NOT running, wait for it to start
        $prerequisiteTestResults = Wait-Prerequisites -Type "Provider" -Id "TableauServerTsmApi" -Timeout (New-Timespan -Minutes 10) -Quiet
        # if the TableauServerTsmApi provider did NOT start (timeout), throw an error
        if (!$prerequisiteTestResults.Pass) {
            throw "  $($prerequisiteTestResults.Prerequisites[0].Tests.Reason)"
        }
        # wait a few seconds to give the TableauServerTsmApi provider time to initialize
        Start-Sleep -Seconds 10
        # request status of Tableau Server via the TableauServerTsmApi provider 
        $tableauServerStatus = Get-TableauServerStatus -ResetCache
        if (!$tableauServerStatus) {
            throw "  Unable to GET Tableau Server status from the TableauServerTsmApi provider"
        }
    }

#endregion TEST 

$tsRestApiAvailable = $false
$tsmApiAvailable = $false

try {

    # check for server shutdown/startup events
    $computerName = $null
    try { $computerName = Get-PlatformTopology nodes -Keys } catch {}
    $serverStatus = Get-ServerStatus -ComputerName $computerName -Quiet
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $errormessage = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        throw $errormessage
    }

    Initialize-TsmApiConfiguration
    $tsmApiAvailable = $true

    $platformTopology = Initialize-PlatformTopology -ResetCache
    $platformTopology | Out-Null

    # check for platform events
    $platformStatus = Get-PlatformStatus 
    if ($platformStatus.IsStopped) {
        $tsRestApiAvailable = $false
        $errormessage = "Platform is STOPPED"
        throw $errormessage
    }
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $tsRestApiAvailable = $false
        $errormessage = "$($Platform.Name) $($platformStatus.Event.ToUpper()) is $($platformStatus.EventStatus.ToUpper())"
        throw $errormessage
    }

    Initialize-TSRestApiConfiguration
    $tsRestApiAvailable = $true

    If (!$newLineWritten) {
        Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) READY  " -ForegroundColor DarkGreen
    }
    else {
        $message = "<Platform Initialization <.>48> READY"
        Write-Host+ -NoTrace -Parse -NoNewLine $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
    }

}
catch {

    # Write-Host+ -Iff $(!$serverStatus) -ReverseLineFeed 1
    # $message = "<Platform Initialization <.>48> WARNING"
    # Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkRed

    If (!$newLineWritten) {
        Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) WARNING" -ForegroundColor DarkYellow
    }
    else {
        $message = "<Platform Initialization <.>48> WARNING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkYellow
    }

    Write-Host+ -NoTrace -NoSeparator "  $($_.Exception.Message)" -ForegroundColor DarkRed
    
    If (!$tsmApiAvailable) { 
        $errorMessage = "  The TSM API is unavailable."
        Write-Host+ -NoTrace -NoSeparator $errorMessage -ForegroundColor DarkRed
    }
    If (!$tsRestApiAvailable) {
        $errorMessage = "  The Tableau Server REST API is unavailable."
        Write-Host+ -NoTrace -NoSeparator $errorMessage -ForegroundColor DarkRed
    }
    
}

Write-Host+
Set-CursorVisible

return

#endregion INIT