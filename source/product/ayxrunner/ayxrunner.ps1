#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id = "ayxrunner"}
. $PSScriptRoot\definitions.ps1

function script:Send-AyxRunnerMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Intervention,
        [switch]$NoThrottle
    )

    $sections = @()

    $serverInfo = Get-ServerInfo -ComputerName $ComputerName

    $facts = @(
        @{name  = "Message"; value = $Message}
    )

    $sectionMain = @{}
    $sectionMain = @{
        ActivityTitle = $serverInfo.OSName
        ActivitySubtitle = $serverInfo.DisplayName
        ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) Cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
        ActivityImage = (Get-Catalog -Uid OS.Windows11).image
        Facts = $facts
    }

    $sections += $sectionMain

    $msg = @{
        Title = "Overwatch Monitor for the Alteryx Designer Runner workflows"
        Text = "Monitors the health of the Alteryx Designer Runner workflows."
        Sections = $sections
        Type = $MessageType
        Summary = "Overwatch $MessageType`: [$($serverInfo.DisplayName ?? $ComputerName.ToUpper())] $Message"
        Subject = "Overwatch $MessageType`: [$($serverInfo.DisplayName ?? $ComputerName.ToUpper())] $Message"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-ServerInterventionMessage"
    }

    return Send-Message -Message $msg

}

$connectionString = Get-ConnectionString healthinsightplatform | ConvertTo-OdbcConnectionString

$connection = Connect-OdbcData $connectionString

$query = "select * from alteryx_runner_heartbeat"
$heartbeats = Read-OdbcData -Connection $connection -Query $query

foreach ($heartbeat in $heartbeats) {
    $now = [datetime]::Now
    $diff = $now - $heartbeat.timestamp
    # Write-Host+ -NoTimestamp -NoTrace $heartbeat.computer_name, $heartbeat.timestamp, $diff
    if ($diff -ge $global:Product.Config.NotRunningThreshold) {
        Send-AyxRunnerMessage -Message "The Alteryx Designer Runner workflow on $($heartbeat.computer_name) is NOT RUNNING" -ComputerName $heartbeat.computer_name
    }
}