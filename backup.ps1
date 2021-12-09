#Requires -RunAsAdministrator
#Requires -Version 7

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"

$global:Product = @{Id="Backup"}
. $PSScriptRoot\definitions.ps1

# check for server shutdown/startup events
$serverStatus = Confirm-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)

switch ($serverStatus) {
    "Startup.InProgress" {return}
    "Shutdown.InProgress" {return}
    default {}
}

if ($serverStatus) {Write-Log -Action 'ServerStatus' -Status $serverStatus -EntryType "Warning"}

Backup-Platform