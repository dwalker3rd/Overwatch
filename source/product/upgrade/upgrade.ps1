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

$build = ""
$version = ""

if ([string]::IsNullOrEmpty($build) -or $build -le $global:Platform.Build) {
    throw "Unable to upgrade Tableau Server if `$build has not been specified."
}

#region STOP PLATFORM

    Stop-Platform -Reason "Upgrade to Tableau Server $version"

#endregion STOP PLATFORM
#region UPGRADE

    . "F:\Program Files\Tableau\Tableau Server\packages\scripts.$($build)\upgrade-tsm.cmd" --no-prompt  

#endregion UPGRADE
#region START PLATFORM

    Start-Sleep -Seconds 10
    Get-PlatformInfo -ResetCache
    Start-Sleep -Seconds 10
    Start-Platform

#endregion START PLATFORM

Remove-PSSession+