# $global:Product = @{Id = "Backup"}
# . $PSScriptRoot\definitions.ps1

# New-Log -Name "Backup"

if (!(Test-Path -Path $Backup.Path)) {New-Item -ItemType Directory -Path $Backup.Path}

if ($(Get-PlatformTask -Id "Backup")) {
    Unregister-PlatformTask -Id "Backup"
}

# scheduled time as UTC
$at = get-date -date "6:00Z"

Register-PlatformTask -Id "Backup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Backup").ps1" -WorkingDirectory $global:Location.Scripts `
    -Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 60) -RunLevel Highest -SyncAcrossTimeZones