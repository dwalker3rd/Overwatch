#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id = "ayxrunner"}
. $PSScriptRoot\definitions.ps1

#region OVERRIDE MICROSOFTTEAMS

    # If using the MicrosoftTeams provider, enter the webhook URI[s] for each message type (see $PlatformMessageType)
    # $MicrosoftTeamsConfig.MessageType defines which message types are forwarded by the MicrosoftTeams provider

    $global:MicrosoftTeamsConfig = @{
        Connector = @{
            AllClear = @("<Microsoft Teams AllClear Webhook>")
            Alert = @("<Microsoft Teams AllClear Webhook>")
            Intervention = @("<Microsoft Teams AllClear Webhook>")               
            Information = @("<Microsoft Teams AllClear Webhook>")
        }
    }
    $global:MicrosoftTeamsConfig.MessageType = $global:MicrosoftTeamsConfig.Connector.Keys

    $providers = Get-Provider -ResetCache
    $providers.Id | ForEach-Object {
        if (Test-Path -Path "$($global:Location.Providers)\provider-$($_).ps1") {
            $null = . "$($global:Location.Providers)\provider-$($_).ps1"
        }
    }    

#endregion OVERRIDE MICROSOFTTEAMS

$ayxRunnerLogPath = "$($global:Location.Logs)\ayxrunner.log"
$ayxRunnerLog = @{}
if (Test-Path $ayxRunnerLogPath) {
    $ayxRunnerLog = Import-Csv -Path $ayxRunnerLogPath
}

$connectionString = Get-ConnectionString healthinsightplatform | ConvertTo-OdbcConnectionString
$connection = Connect-OdbcData $connectionString
$hbComputerNames = (Read-OdbcData -Connection $connection -Query "select computer_name from alteryx_runner_heartbeat").computer_name
$query = @"
select 
	cn.computer_name,
	coalesce(hb.`"timestamp`",cn.max_actual_start_date_time) as timestamp, 
	(case when hb.`"timestamp`" is not null then log.id else null end) as id,
	(case when hb.`"timestamp`" is not null then log.workflow else null end) as workflow,
	(case when hb.`"timestamp`" is not null then log.status else 'Stopped' end) as status,
    log.schedule_id,
    plan.avg_execution_time,
    plan.stddev_execution_time
from
	(select computer_name, max(actual_start_date_time) as max_actual_start_date_time from alteryx_runner_log group by computer_name) cn
	left join alteryx_runner_heartbeat hb on cn.computer_name = hb.computer_name
	left join alteryx_runner_log as log on cn.computer_name = log.computer_name and log.actual_start_date_time = cn.max_actual_start_date_time 
    left join alteryx_runner_execution_plan as plan on log.id = plan.id and log.start_date_time = plan.start_date_time
"@

$currentStatus = @()
$data = Read-OdbcData -Connection $connection -Query $query
foreach ($dataRow in $data) {
    $now = [datetime]::Now

    # computer_name is not in heartbeat table; insert
    if ($dataRow.computer_name -notin $hbComputerNames) {
        $fakeTimestamp = Get-Date($dataRow.timestamp).AddSeconds(1)
        $queryUpdateHeartbeat = "insert into alteryx_runner_heartbeat (computer_name, timestamp) values (`'$($dataRow.computer_name)`', `'$fakeTimestamp`')"
        Update-OdbcData -Connection $connection -Query $queryUpdateHeartbeat
        $queryFakeLogEntry = "select * from alteryx_runner_log where computer_name = `'$($dataRow.computer_name)`' and instance_id = 'ERROR'"
        $dataFakeLogEntry = Read-OdbcData -Connection $connection -Query $queryFakeLogEntry
        if (!$dataFakeLogEntry) {
            $queryFakeLogEntryInsert = "insert into alteryx_runner_log (instance_id, scheduled_start_date_time, computer_name, schedule_id, actual_start_date_time, status) values (`'ERROR`',`'$fakeTimestamp`',`'$($dataRow.computer_name)`',$($dataRow.schedule_id),`'$fakeTimestamp`',`'Stopped`')"
            Update-OdbcData -Connection $connection -Query $queryFakeLogEntryInsert
        }
    }
    
    $diff = $now - $dataRow.timestamp
    if ($dataRow.status -eq "Running") {
        $3stddev = [string]::IsNullOrEmpty($dataRow.stddev_execution_time) ? 0 : 3*(New-TimeSpan -Seconds $dataRow.stddev_execution_time)
        $diff = $diff - ((New-TimeSpan -Seconds $dataRow.avg_execution_time) + $3stddev)
    }
    $notRunning = $dataRow.Status -in ("Waiting","Stopped") -and $diff -ge $global:Product.Config.NotRunningThreshold
    $messageType = $notRunning ? $global:PlatformMessageType.Intervention : $global:PlatformMessageType.Information
    $_currentStatus = [PSCustomObject]@{
        ComputerName = $dataRow.computer_name
        Timestamp = $dataRow.timestamp
        Now = $now
        Diff = [int64]([math]::Ceiling($diff.TotalSeconds))
        NotRunningThreshold = [int64]([math]::Ceiling($global:Product.Config.NotRunningThreshold.TotalSeconds))
        NotRunning = $notRunning
        Id = $dataRow.Id
        Workflow = $dataRow.workflow
        Status = $dataRow.status
        AvgExecutionTime = $dataRow.avg_execution_time
        StdDevExecutionTime = $dataRow.stddev_execution_time
        MessageType = $messageType
    }
    if ($notRunning) {
        $response = Send-AyxRunnerMessage -MessageType $messageType -Status "STOPPED" -ComputerName $dataRow.computer_name -NoThrottle
        $response | Out-Null
        $_currentStatus | Export-CSV -Path $ayxRunnerLogPath -Append
    }
    else {
        $ayxRunnerLogRecords = $ayxRunnerLog | Where-Object {$_.ComputerName -eq $dataRow.computer_name} | Sort-Object -Property Timestamp -Descending
        if ($ayxRunnerLogRecords) {
            $ayxRunnerLogRecord = $ayxRunnerLogRecords[0]
            if ($ayxRunnerLogRecord.NotRunning -eq "True" -and !$_currentStatus.NotRunning) {
                $messageType = $_currentStatus.MessageType = $global:PlatformMessageType.AllClear
                $response = Send-AyxRunnerMessage -MessageType $messageType -Status "RUNNING" -ComputerName $dataRow.computer_name -NoThrottle
                $response | Out-Null
                $_currentStatus | Export-CSV -Path $ayxRunnerLogPath -Append
            }
        }
    }
    $currentStatus += $_currentStatus
}

$connection.Close()

$currentStatus | Select-Object -ExcludeProperty AvgExecutionTime, StdDevExecutionTime, MessageType | Sort-Object -Property ComputerName | Format-Table
