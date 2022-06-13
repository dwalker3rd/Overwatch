#region INIT

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Set-CursorInvisible

Write-Host+
$message = "<Platform Initialization <.>48> PENDING"
Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

try {

    # check for server shutdown/startup events
    $computerName = $null
    try { $computerName = Get-PlatformTopology nodes -Keys } catch {}
    $serverStatus = Get-ServerStatus -ComputerName $computerName
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper()):The TSM and Tableau Server REST APIs are unavailable."
        throw $message
    }

    Initialize-TsmApiConfiguration
    $platformTopology = Initialize-PlatformTopology -ResetCache
    $platformTopology | Out-Null

    # check for platform events
    $platformStatus = Get-PlatformStatus 
    # abort if platform is stopped or if a platform event is in progress
    if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $message = "$($Platform.Name) is $($($PlatformStatus.IsStopped) ? "STOPPED" : $($platformStatus.EventStatus.ToUpper())):The Tableau Server REST API is unavailable."
        throw $message
    }

    Initialize-TSRestApiConfiguration

    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

}
catch {

    $message = "$($emptyString.PadLeft(8,"`b")) FAIL   $($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkRed 

    Write-Host+ -NoTrace -NoSeparator "  $($_.Exception.Message.Split(":")[0])" -ForegroundColor DarkRed
    Write-Host+ -NoTrace -NoSeparator "  $($_.Exception.Message.Split(":")[1])" -ForegroundColor DarkRed
    Write-Log -Action "Initialize" -Target "Platform" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message.Replace(":",". ")
}

Write-Host+
Set-CursorVisible

return

#endregion INIT