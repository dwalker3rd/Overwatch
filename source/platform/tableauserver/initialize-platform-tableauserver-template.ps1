#region INIT

Set-CursorInvisible

Write-Host+
$message = "<Platform Initialization <.>48> PENDING"
Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

$tsRestApiAvailable = $false
$tsmApiAvailable = $false

try {

    # check for server shutdown/startup events
    $computerName = $null
    try { $computerName = Get-PlatformTopology nodes -Keys } catch {}
    $serverStatus = Get-ServerStatus -ComputerName $computerName
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

    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

}
catch {

    $message = "$($emptyString.PadLeft(8,"`b")) WARNING$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkRed 

    Write-Host+ -NoTrace -NoSeparator "  $($_.Exception.Message)" -ForegroundColor DarkRed
    
    If (!$tsmApiAvailable) { 
        $errorMessage = "  The TSM REST API is unavailable."
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