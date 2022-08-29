#Requires -RunAsAdministrator
#Requires -Version 7

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"

$global:Product = @{Id="Cleanup"}
. $PSScriptRoot\definitions.ps1

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

    $platformStatus = Get-PlatformStatus 

    # abort if a platform event is in progress
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $action = "Cleanup"; $target = $global.Platform.Id; $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because "
        if ($platformStatus.IsStopped) {
            $message += "$($Platform.Name) is STOPPED"
        }
        else {
            $message += "platform $($platformStatus.Event.ToUpper()) is $($platformStatus.EventStatus.ToUpper()) on $($Platform.Name)"
        }
        Write-Log -Context $($global:Product.Id) -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        return
    }

# endregion PLATFORM

Cleanup-Platform