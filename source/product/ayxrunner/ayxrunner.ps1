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

#region OVERRIDE MICROSOFTTEAMS

    # If using the MicrosoftTeams provider, enter the webhook URI[s] for each message type (see $PlatformMessageType)
    # $MicrosoftTeamsConfig.MessageType defines which message types are forwarded by the MicrosoftTeams provider

    $global:MicrosoftTeamsConfig = @{
        Connector = @{
            AllClear = @("***REMOVED***")
            Alert = @("***REMOVED***")
            Intervention = @("***REMOVED***")                
            Information = @("***REMOVED***")
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
$query = @"
select cn.computer_name,hb.`"timestamp`",log.id,log.workflow,log.status,plan.avg_execution_time,plan.stddev_execution_time from
(select distinct plancn.computer_name from alteryx_runner_execution_plan as plancn
left join alteryx_runner_heartbeat as hbcn on hbcn.computer_name = plancn.computer_name) cn
left join alteryx_runner_heartbeat hb on cn.computer_name = hb.computer_name
left join alteryx_runner_log as log on hb.computer_name = log.computer_name 
left join alteryx_runner_execution_plan as plan on log.id = plan.id and log.start_date_time = plan.start_date_time
where log.status in ('Waiting', 'Running') or log.status is null
"@

$currentStatus = @()
$data = Read-OdbcData -Connection $connection -Query $query
foreach ($dataRow in $data) {
    $now = [datetime]::Now

    # assumption: this computer_name is no longer in the heartbeat table 
    if ([string]::IsNullOrEmpty($dataRow.timestamp)) {
        $queryMaxLogEntry = "select max(actual_end_date_time) as max_actual_end_data_time from alteryx_runner_log where computer_name = `'$($dataRow.computer_name)`'"
        $dataMaxLogEntry = Read-OdbcData -Connection $connection -Query $queryMaxLogEntry
        $dataRow.timestamp = ![string]::IsNullOrEmpty($dataMaxLogEntry.max_actual_end_data_time) ? $dataMaxLogEntry.max_actual_end_data_time : [datetime]::MinValue
        $queryUpdateHeartbeat = "insert into alteryx_runner_heartbeat (computer_name, timestamp) values (`'$($dataRow.computer_name)`', `'$($dataRow.timestamp)`')"
        Update-OdbcData -Connection $connection -Query $queryUpdateHeartbeat
        $dataRow.status = "Not Running"
    }
    
    $diff = $now - $dataRow.timestamp
    if ($dataRow.status -eq "Running") {
        $3stddev = [string]::IsNullOrEmpty($dataRow.stddev_execution_time) ? 0 : 3*(New-TimeSpan -Seconds $dataRow.stddev_execution_time)
        $diff = $diff - ((New-TimeSpan -Seconds $dataRow.avg_execution_time) + $3stddev)
    }
    $notRunning = $dataRow.Status -in ("Waiting","Not Running") -and $diff -ge $global:Product.Config.NotRunningThreshold
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
        $response = Send-AyxRunnerMessage -MessageType $messageType -Status "NOT RUNNING" -ComputerName $dataRow.computer_name -NoThrottle
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
