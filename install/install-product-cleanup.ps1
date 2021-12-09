# $global:Product = @{Id = "Cleanup"}
# . $PSScriptRoot\definitions.ps1

# New-Log -Name "Cleanup"

if ($(Get-PlatformTask -Id "Cleanup")) {
    Unregister-PlatformTask -Id "Cleanup"
}

# scheduled time as UTC
$at = get-date -date "5:45Z"

Register-PlatformTask -Id "Cleanup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Cleanup").ps1" -WorkingDirectory $global:Location.Scripts `
-Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -SyncAcrossTimeZones