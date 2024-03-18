$vizAlertsLogsDirectory = "F:\VizAlerts\tableau-path-org\logs"
$vizAlertsLogFile = "$vizAlertsLogsDirectory\vizalerts.log_2024-03-07.log"

$vizAlertsLog = Get-Content -Path $vizAlertsLogFile
$vizAlertsLogErrors = $vizAlertsLog | Where-Object {$_ -match "\[ERROR\]"} 
Write-Host+ -NoTrace -NoTimeStamp "VizAlerts log file `'$vizAlertsLogFile`'"
Write-Host+ -NoTrace -NoTimeStamp "  $($vizAlertsLog.Count) records"
Write-Host+ -NoTrace -NoTimeStamp "  $($vizAlertsLogErrors.Count) errors"
Write-Host+

$vizAlertsLogErrorsParsed = @()
$vizAlertsLogErrors | ForEach-Object {
    # Write-Host+ -NoTrace -NoTimestamp $_
    $columns = $_ -split "\s-\s"
    $vizAlertsLogErrorsParsed += [PSCustomObject]@{
        logentry = $_
        threadname = $columns[0]
        asctime = [datetime]$columns[1]
        levelname = ([regex]::Matches($columns[2],"\[(.*)\]")).Groups[1].Value
        funcname  = $columns[3]
        message = $columns[4]
    }
}

$vizAlertsErrors = @()
$vizAlertsLogErrorsGroups = $vizAlertsLogErrorsParsed | Sort-Object -Property asctime -Desc | Group-Object -Property threadname, asctime, levelname, funcname, message
foreach ($vizAlertsErrorGroup in $vizAlertsLogErrorsGroups) {
    $vizAlertsErrors += [PSCustomObject]@{
        threadName = $vizAlertsErrorGroup.Group[0].threadname
        startDateTime = $vizAlertsErrorGroup.Group[-1].asctime
        endDateTime = $vizAlertsErrorGroup.Group[0].asctime
        messageType = $vizAlertsErrorGroup.Group[0].levelname
        funcName = $vizAlertsErrorGroup.Group[0].funcname
        message = $vizAlertsErrorGroup.Group[0].message
        count = $vizAlertsErrorGroup.Count
    }
}

$vizAlertsErrors | Select-Object -Property startDateTime, messageType, funcName, count, message | Format-Table