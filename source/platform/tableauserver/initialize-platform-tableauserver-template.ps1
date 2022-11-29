#region INIT

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Set-CursorInvisible

Write-Host+
$message = "<Platform Initialization <.>48> PENDING"
Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

$tsRestApiAvailable = $true
$tsmRestApiAvailable = $true

try {

    # check for server shutdown/startup events
    $computerName = $null
    try { $computerName = Get-PlatformTopology nodes -Keys } catch {}
    $serverStatus = Get-ServerStatus -ComputerName $computerName
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $tsRestApiAvailable = $tsmRestApiAvailable = $false
        $errormessage = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        throw $errormessage
    }

    # check TSM REST API prerequisites
    foreach ($prerequisite in $global:Catalog.Platform.TableauServer.Api.TsmApi.Prerequisite) {
        $serviceIsRunning = Invoke-Expression "Wait-$($prerequisite.Type) -Name $($prerequisite.Service) -Status $($prerequisite.Status)"
        if (!$serviceIsRunning) {
            $tsmRestApiAvailable = $false
            $service = Get-Service $prerequisite.Service
            $errormessage = "The $($Platform.Name) service `"$($prerequisite.Service)`" is $($service.Status.ToUpper())"
            throw $errormessage
        }
    }

    Initialize-TsmApiConfiguration

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

    # check Tableau Server REST API prerequisites
    foreach ($prerequisite in $global:Catalog.Platform.TableauServer.Api.TableauServerRestApi.Prerequisite) {
        $serviceIsRunning = Invoke-Expression "Wait-$($prerequisite.Type) -Name $($prerequisite.Service) -Status $($prerequisite.Status) -TimeoutInSeconds 15"
        if (!$serviceIsRunning) {
            $tsRestApiAvailable = $false
            $errormessage = "The $($Platform.Name) service `"$($prerequisite.Service)`" is NOT $($prerequisite.Status.ToUpper())"
            throw $errormessage
        }
    }

    Initialize-TSRestApiConfiguration

    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

}
catch {

    $message = "$($emptyString.PadLeft(8,"`b")) WARNING$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkRed 

    Write-Host+ -NoTrace -NoSeparator "  $($_.Exception.Message)" -ForegroundColor DarkRed
    
    If (!$tsmRestApiAvailable) { 
        $errorMessage = "  The TSM REST API is unavailable."
        # Write-Log -Action "Initialize" -Target "TSM REST API" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message
        Write-Host+ -NoTrace -NoSeparator $errorMessage -ForegroundColor DarkRed
    }
    If (!$tsRestApiAvailable) {
        $errorMessage = "  The Tableau Server REST API is unavailable."
        # Write-Log -Action "Initialize" -Target "Tableau Server REST API" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message
        Write-Host+ -NoTrace -NoSeparator $errorMessage -ForegroundColor DarkRed
    }
    
}

Write-Host+
Set-CursorVisible

return

#endregion INIT