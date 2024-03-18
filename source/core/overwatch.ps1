#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"
$global:PostflightPreference = "Continue"
$global:WriteHostPlusPreference = "Continue"

# product id must be set before include files
$global:Product = @{Id="Command"}
. $PSScriptRoot\definitions.ps1

Write-Host+ -ResetAll

Remove-PSSession+