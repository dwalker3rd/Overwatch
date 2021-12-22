#Requires -RunAsAdministrator

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"

# product id must be set before includes execute
$global:Product  = @{Id="Monitor"}
. $PSScriptRoot\definitions.ps1

Send-ServerStatusMessage -ComputerName $env:COMPUTERNAME -Event "Shutdown" -Status "In Progress" -Reason "Triggered by Windows Server OnShutdown scripts" -Level $PlatformMessageType.Alert -TimeCreated [DateTime]::Now

Write-Log -EntryType 'Warning' -Action 'Shutdown' -Status 'Shutdown' -Message "$($MyInvocation.MyCommand): Triggered by Windows Server OnShutdown scripts"