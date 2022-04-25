#region INIT

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Write-Host+

#region SERVER/PLATFORM CHECK

    $serverEventInProgress = $false
    $platformEventInProgress = $false

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        $serverEventInProgress = $true
    }

    if (!$serverEventInProgress) {
        # check for platform events
        $platformStatus = Get-PlatformStatus 
        # abort if platform is stopped or if a platform event is in progress
        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
            $message = "$($Platform.Name) is $($($PlatformStatus.IsStopped) ? "STOPPED" : $($platformStatus.EventStatus.ToUpper()))"
            Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
            $platformEventInProgress = $true
        }
    }

    if ($serverEventInProgress -or $platformEventInProgress) {
        Write-Host+
    }

#endregion SERVER/PLATFORM CHECK

$message = "Platform Initialization"
$dots = Write-Dots -Length 47 -Adjust (-($message.Length))
Write-Host+ -NoNewline $message,$dots -ForegroundColor DarkBlue,DarkGray

try {

    if ($serverEventInProgress) {
        $message = "  TSM API and Tableau Server REST API are unavailable."
        throw $message
    }

    Initialize-TsmApiConfiguration

    if ($platformEventInProgress) {
        $message = "  Tableau Server REST API is unavailable."
        throw $message
    }

    Initialize-TSRestApiConfiguration

}
catch {
    Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
    Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkRed 
    Write-Host+
    Write-Log -Action "Initialize" -Target "Platform" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message
    return
}

Write-Host+ -NoTimestamp -NoTrace " DONE" -ForegroundColor DarkGreen 
Write-Log -Action "Initialize" -Target "Platform" -Status "Success"

return

#endregion INIT