# #Requires -RunAsAdministrator
# #Requires -Version 7

# $global:DebugPreference = "SilentlyContinue"
# $global:InformationPreference = "SilentlyContinue"
# $global:VerbosePreference = "SilentlyContinue"
# $global:WarningPreference = "Continue"
# $global:ProgressPreference = "SilentlyContinue"
# $global:PreflightPreference = "SilentlyContinue"
# $global:PostflightPreference = "SilentlyContinue"
# $global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id = "MailMerge"}
# . $PSScriptRoot\definitions.ps1

function Get-WeekNumber {

    param(
        [Parameter(Mandatory=$true)][datetime]$currentDate
    )

    $culture = [System.Globalization.CultureInfo]::CurrentCulture
    $calendar = $culture.Calendar
    $rule = [System.Globalization.CalendarWeekRule]::FirstDay
    $firstDayOfWeek = $culture.DateTimeFormat.FirstDayOfWeek
    $weekNumber = $calendar.GetWeekOfYear($currentDate, $rule, $firstDayOfWeek)

    return $weekNumber

}

Write-Host+
$message = "<Mail merge <.>48> PENDING"
Write-Host+ -NoTimestamp -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray 

$emailCount = 0

$mailMerges = Import-Csv -Path "$($global:Location.Data)\mailMerge.csv"
foreach ($mailMerge in $mailMerges) {

    $templates = Import-Csv -Path "$($global:Location.Data)\$($mailMerge.templateFilePath)" -Encoding utf8BOM

    $data = Import-Csv -Path "$($global:Location.Data)\$($mailMerge.dataFilePath)"
    $groupByProperties = $mailMerge.groupDataBy -split ","
    $dataGroups = $data | Group-Object -Property $groupByProperties

    $schedules = Get-Content -Raw -Path "$($global:Location.Data)\$($mailMerge.scheduleFilePath)" | ConvertFrom-Json
    $schedules | Out-Null

    $joinScheduleOn = $mailMerge.joinScheduleOn

    for ($i = 0; $i -lt $dataGroups.Count; $i++) {

        $languageCode = $dataGroups[$i].Group[0].languageCode ?? "en"

        foreach ($group in $dataGroups[$i].Group) {
            foreach ($member in $group.psobject.members) {
                if ($member.MemberType -eq "NoteProperty") {
                    Set-Variable -Name $member.Name -Value $member.Value -Scope Script
                }
            }
        }        
        
        $logEntryId = $dataGroups[$i].Name
        $logEntry = read-log $product.Id -Context $Product.Id -Action "Send-SMTP" -Target $logEntryId -Status $global:PlatformMessageStatus.Transmitted -Newest 1

        $scheduleExpression = "`$schedules | Where-Object {`$_.$joinScheduleOn -eq `$$joinScheduleOn}"
        $schedule = Invoke-Expression $scheduleExpression

        $now = Get-Date -AsUTC
        $scheduledDatetime = Get-Date ($now.ToString("yyyy-MM-dd") + " " + $schedule.time)
        if (($schedule.frequency -eq "monthly" -and $now.Day -in $schedule.daysOfMonth -and (!$logEntry -or $logEntry.TimeStamp.Month -ne $now.Month -or $logEntry.TimeStamp.Day -notin $schedule.daysOfMonth)) -or 
            ($schedule.frequency -eq "weekly" -and $now.DayOfWeek -in $schedule.daysOfWeek -and (!$logEntry -or (Get-WeekNumber $logEntry.TimeStamp) -ne (Get-WeekNumber $now) -or $logEntry.TimeStamp.DayOfWeek -notin $schedule.daysOfWeek)) -or 
            ($schedule.frequency -eq "daily" -and (!$logEntry -or $logEntry.TimeStamp.Day -ne $now.Day)) -and 
            $now -ge $scheduledDatetime) {     

            $template = $templates | Where-Object {$_.languageCode -eq $languageCode}

            $from = "no-reply@path.org"
            # $to = $dataGroups[$i].Group.email    
            $to = [array]"dwalker@path.org"
            $subject = Invoke-Expression $template.subject
            $body = Invoke-Expression $template.body

            $status = Send-SMTP -From $from -To $to -Subject $subject -Body $body -BodyFormat HTML

            if ($emailCount -eq 0) {Write-Host+; Write-Host+}
            $emailCount += 1
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "    Email to " -ForegroundColor Gray
            $message = "<$departmentCode $country <.>35> $status"
            Write-Host+ -NoTimestamp -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,($status -eq $global:PlatformMessageStatus.Transmitted ? "DarkGreen" : "DarkRed")
            
            Write-Log $product.Id -Context $Product.Id -Action "Send-SMTP" -Target $logEntryId -Status $status -Force

        }

    }
}

if ($emailCount -eq 0) {
    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen
    Write-Host+ -NoTrace -NoTimestamp "    $emailCount mail merge$($emailCount -eq 1 ? $null : "s") processed"    
}
else {
    Write-Host+ -NoTrace -NoTimestamp "    $emailCount mail merge$($emailCount -eq 1 ? $null : "s") processed"
    Write-Host+
    $message = "<Mail merge <.>48> SUCCESS"
    Write-Host+ -NoTimestamp -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
}
Write-Host+
