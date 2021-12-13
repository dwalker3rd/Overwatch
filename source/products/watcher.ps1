#Requires -RunAsAdministrator
#Requires -Version 7

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"

# product id must be set before include files
$global:Product = @{Id="Watcher"}
. $PSScriptRoot\definitions.ps1

# Show-CimInstanceEvent -Class Win32_Process -Event __InstanceCreationEvent -Name AlteryxServerHost
# Show-CimInstanceEvent -Class Win32_Process -Event __InstanceDeletionEvent -Name AlteryxServerHost

Read-Log Watcher -tail 10 -View Watcher | Format-Table