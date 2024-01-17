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
        [Parameter(Mandatory=$true)][object]$MessageType,
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

$ayxRunnerLog = Import-Csv -Path "$($Location.Logs)\ayxrunner.log"

$connectionString = Get-ConnectionString healthinsightplatform | ConvertTo-OdbcConnectionString
$connection = Connect-OdbcData $connectionString
$query = @"
select hb.computer_name,hb.`"timestamp`",log.id,log.workflow,log.status,plan.avg_execution_time,plan.stddev_execution_time from alteryx_runner_heartbeat as hb 
inner join alteryx_runner_log as log on hb.computer_name = log.computer_name 
inner join alteryx_runner_execution_plan as plan on log.id = plan.id and log.start_date_time = plan.start_date_time
where log.status in ('Waiting', 'Running')
"@

$currentStatus = @()
$data = Read-OdbcData -Connection $connection -Query $query
foreach ($dataRow in $data) {
    $now = [datetime]::Now
    $diff = $now - $dataRow.timestamp
    if ($dataRow.status -eq "Running") {
        $3stddev = [string]::IsNullOrEmpty($dataRow.stddev_execution_time) ? 0 : 3*(New-TimeSpan -Seconds $dataRow.stddev_execution_time)
        $diff = $diff - ((New-TimeSpan -Seconds $dataRow.avg_execution_time) + $3stddev)
    }
    $notRunning = $diff -ge $global:Product.Config.NotRunningThreshold
    $_currentStatus = [PSCustomObject]@{
        Now = $now
        ComputerName = $dataRow.computer_name
        Timestamp = $dataRow.timestamp
        Diff = [int]([math]::Ceiling($diff.TotalSeconds))
        Status = $dataRow.status
        Id = $dataRow.Id
        Workflow = $dataRow.workflow
        AvgExecutionTime = $dataRow.avg_execution_time
        StdDevExecutionTime = $dataRow.stddev_execution_time
        NotRunningThreshold = $global:Product.Config.NotRunningThreshold.TotalSeconds
        NotRunning = $notRunning
    }
    $ayxRunnerLogRecords = $ayxRunnerLog | Where-Object {$_.ComputerName -eq $dataRow.computer_name} | Sort-Object -Property Timestamp -Descending
    if ($ayxRunnerLogRecords) {
        $ayxRunnerLogRecord = $ayxRunnerLogRecords[0]
        if ($ayxRunnerLogRecord.NotRunning -and !$_currentStatus.NotRunning) {
            Send-AyxRunnerMessage -MessageType $global:PlatformMessageType.AllClear -Message "The Alteryx Designer Runner workflow on $($dataRow.computer_name) is RUNNING" -ComputerName $dataRow.computer_name
            $_currentStatus | Export-CSV -Path "$($global:Location.Logs)\ayxrunner.log" -Append
        }
    }
    if ($diff -ge $global:Product.Config.NotRunningThreshold) {
        $response = Send-AyxRunnerMessage -MessageType $global:PlatformMessageType.Intervention -Message "The Alteryx Designer Runner workflow on $($dataRow.computer_name) is NOT RUNNING" -ComputerName $dataRow.computer_name
        if ($response -ne "Throttled") {
            $_currentStatus | Export-CSV -Path "$($global:Location.Logs)\ayxrunner.log" -Append
        }
    }
    $currentStatus += $_currentStatus
}
$currentStatus | Format-Table *
