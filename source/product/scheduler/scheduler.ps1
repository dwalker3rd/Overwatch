# [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

# param()

# Write-Host+ -ResetAll
# Write-Host+ -MaxBlankLines 1

# $dateAdjustment = New-TimeSpan -Days 0

# $notificationDelta = New-Timespan -Days -2

# $maintenanceStartTime = New-TimeSpan -Hours 6
# $weeklyMaintenanceDuration = New-TimeSpan -Hours 2
# $monthlyMaintenanceDuration = New-Timespan -Hours 8

# $now = ([datetime]::Now).Add($dateAdjustment)
# Write-Host+ -NoTrace -NoTimestamp -Parse "<now <.>32> $($now.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray

# # if ($notify) {
#     $month = [int](Get-Date -UFormat "%m")
#     $year = [int](Get-Date -UFormat "%Y")
#     $day = [int](Get-Date -UFormat %d)
#     $today = (Get-Date -AsUTC "$year/$month/$day 00:00:00").Add($dateAdjustment)
#     Write-Host+ -NoTrace -NoTimestamp -Parse "<today <.>32> $($today.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray

#     $firstDayOfMonth = Get-Date "$year/$month/01"
#     $firstMaintenanceDayofMonth =  (Get-Date "$year/$month/$($weekday - [int](Get-Date -UFormat %u $firstDayofMonth) + 1)")
#     if ((Get-Date $today.ToString('D')) -gt (Get-Date $firstMaintenanceDayOfMonth.ToString('D'))) {
#         $month = $month + 1
#         $firstDayofMonth = Get-Date "$year/$month/01"
#         $firstMaintenanceDayofMonth =  (Get-Date "$year/$month/$($weekday - [int](Get-Date -UFormat %u $firstDayofMonth) + 1)")
#     }
#     Write-Host+ -NoTrace -NoTimestamp -Parse "<firstMaintenanceDayOfMonth <.>32> $($firstMaintenanceDayofMonth.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray
#     $nextMaintenanceDay = (Get-Date ($today).AddDays($weekday - [int](Get-Date -UFormat %u $today)))
#     Write-Host+ -NoTrace -NoTimestamp -Parse "<nextMaintenanceDay <.>32> $($nextMaintenanceDay.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray
# # }

# $maintenanceWindowType = $firstMaintenanceDayofMonth.ToString('D') -eq $nextMaintenanceDay.ToString('D') ? "Monthly" : "Weekly"
# Write-Host+ -NoTrace -NoTimestamp -Parse "<maintenanceWindowType <.>32> $maintenanceWindowType" -ForegroundColor Blue,DarkGray,Gray
# $maintenanceStart = $nextMaintenanceDay.Add($maintenanceStartTime)
# Write-Host+ -NoTrace -NoTimestamp -Parse "<maintenanceStart <.>32> $($maintenanceStart.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray
# $maintenanceDuration = Invoke-Expression "`$$($maintenanceWindowType)MaintenanceDuration"
# Write-Host+ -NoTrace -NoTimestamp -Parse "<maintenanceDuration <.>32> $maintenanceDuration" -ForegroundColor Blue,DarkGray,Gray
# $maintenanceEnd = $maintenanceStart.Add($maintenanceDuration)
# Write-Host+ -NoTrace -NoTimestamp -Parse "<maintenanceEnd <.>32> $($maintenanceEnd.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray

# $notificationStart = $maintenanceStart.Add($notificationDelta)
# Write-Host+ -NoTrace -NoTimestamp -Parse "<notificationStart <.>32> $($notificationStart.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray
# $notificationEnd = $maintenanceEnd
# Write-Host+ -NoTrace -NoTimestamp -Parse "<notificationEnd <.>32> $($notificationEnd.ToString('u'))" -ForegroundColor Blue,DarkGray,Gray

# $isNotificationWindow = $now -ge $notificationStart -and $now -lt $notificationEnd
# Write-Host+ -NoTrace -NoTimestamp -Parse "<isNotificationWindow <.>32> $isNotificationWindow" -ForegroundColor Blue,DarkGray,Gray
# $isMaintenanceWindow = $now -ge $maintenanceStart -and $now -lt $maintenanceEnd
# Write-Host+ -NoTrace -NoTimestamp -Parse "<isMaintenanceWindow <.>32> $isMaintenanceWindow" -ForegroundColor Blue,DarkGray,Gray

# if ($isNotificationWindow) {
#     # Send-UserNotification -Message 
# }

# Write-Host+

# Remove-PSSession+

function global:Get-Schedule {

    [CmdletBinding()]
    param ()

    $scheduleDB = "$($global:Location.Data)\schedule.csv"
    $schedules = Import-Csv -Path $scheduleDB | Where-Object {$_.Platform -eq $global:Platform.ID -and $_.Instance -eq $global:Platform.Instance}

    foreach ($schedule in $schedules) {
        if ($schedule.Weekday) {

            $month = [int](Get-Date -UFormat "%m")
            $year = [int](Get-Date -UFormat "%Y")
            $day = [int](Get-Date -UFormat %d)
            $today = Get-Date -AsUTC "$year/$month/$day"

            $firstDayOfMonth = Get-Date "$year/$month/01"
            $firstWeekdayofMonth =  (Get-Date "$year/$month/$($schedule.weekday - [int](Get-Date -UFormat %u $firstDayofMonth) + 1)")
            if ($today -gt $firstWeekdayOfMonth) {
                $month = $month + 1
                $firstDayofMonth = Get-Date "$year/$month/01"
                $firstWeekdayOfMonth =  (Get-Date "$year/$month/$($schedule.weekday - (Get-WeekdayNumber $firstDayOfMonth) + 1)")
            }

            $nextWeekday = (Get-Date ($today).AddDays($schedule.Weekday - [int](Get-Date -UFormat %u $today)))
            if ((Get-WeekdayOfMonth $nextWeekday) -in $schedule.WeekdayOfMonth.Split(",")) {
                Write-Host+ -NoTrace -NoTimestamp "Up Next!:  $($schedule.WeekdayOfMonth)"
            }
            else {
                Write-Host+ -NoTrace -NoTimestamp "Not Yet!: $($schedule.WeekdayOfMonth)"
            }

        }
    }

}

function Get-WeekdayNumber {

    param (
        [Parameter(Mandatory=$true)][datetime]$Date
    )

    return [int](Get-Date -UFormat %u $Date)
}

function Get-WeekdayOfMonth {

    param (
        [Parameter(Mandatory=$true)][datetime]$Date
    )

    $n = 0
    $day = $Date.Day
    do {
        $day -= 7
        $n++
    } until ($day -lt 0)

    return $n

} 