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

$build = "20233.24.0514.1218"
$version = "2023.3.6"

#region STOP PLATFORM

    Stop-Platform -Reason "Upgrade to Tableau Server $version"

#endregion STOP PLATFORM
#region UPGRADE

    . "F:\Program Files\Tableau\Tableau Server\packages\scripts.$($build)\upgrade-tsm.cmd" --no-prompt  

#endregion UPGRADE
#region START PLATFORM

    Start-Sleep -Seconds 20
    Start-Platform

#endregion START PLATFORM

Remove-PSSession+