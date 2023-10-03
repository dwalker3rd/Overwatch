#region INIT

Set-CursorInvisible

Write-Host+
$message = "<Platform Initialization <.>48> PENDING"
Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

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

    $platformTopology = Initialize-PlatformTopology -ResetCache
    $platformTopology | Out-Null

    Write-Host+ -Iff $(!$serverStatus) -ReverseLineFeed 1
    $message = "<Platform Initialization <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen

}
catch {

    Write-Host+ -Iff $(!$serverStatus) -ReverseLineFeed 1
    $message = "<Platform Initialization <.>48> WARNING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkRed
    
}

Write-Host+
Set-CursorVisible

return

#endregion INIT