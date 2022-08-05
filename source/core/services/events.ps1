$EventHistoryMax = 72 # 6 hours if the interval is 5 minutes

function global:Show-PlatformEvent {

    $platformStatus = Get-PlatformStatus

    $properties = $platformStatus.psobject.Properties | Where-Object {$_.name -like "Event*" -and $_.name -ne "EventHistory"}
    $propertyNameLengths = foreach($property in $properties) {$property.Name.Length}
    $maxLength = ($propertyNameLengths | Measure-Object -Maximum).Maximum

    Write-Host+
    foreach ($property in $properties) {
        $message = "<$($property.Name) < >$($maxLength+2)> "
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Green,DarkGray
        $value = switch ($property.Value.GetType().Name) {
            default { $property.Value}
            "ArrayList" {
                "{$($property.Value -join ", ")}"
            }
        }
        Write-Host+ -NoTrace -NoTimestamp ":",$value -ForegroundColor Green,Gray
    }

    [PlatformStatus[]]$platformStatus.EventHistory | Format-Table -Property Event, EventReason, EventStatus, EventCreatedBy, EventCreatedAt, EventUpdatedAt, EventCompletedAt, EVentHasCompleted, EventStatusTarget

}

function Push-EventHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus
    )

    if (!$PlatformStatus.Event) { return }

    # if the current event and the last historical entry are identical, 
    # don't push the event onto the stack.  instead, just update the timestamp $PlatformStatus.EventHistory[0].EventUpdatedAt
    # this allows tracking longer periods of event data without using as much cache storage
    if ($PlatformStatus.EventHistory.Count -gt 0) {
        $eventUpdate = Compare-Object $PlatformStatus $PlatformStatus.EventHistory[0] -Property Event, EventReason, EventStatus, EventCreatedBy, EventCreatedAt, EventCompletedAt, EVentHasCompleted, EventStatusTarget
        if (!$eventUpdate) {
            $PlatformStatus.EventHistory[0].EventUpdatedAt = $PlatformStatus.EventUpdatedAt
            return
        }
    }

    if ($PlatformStatus.EventHistory.Count -lt $EventHistoryMax) {
        $PlatformStatus.EventHistory += @{}
    }
    for ($i = $PlatformStatus.EventHistory.Count-1; $i -gt 0; $i--) {
        $PlatformStatus.EventHistory[$i] = $PlatformStatus.EventHistory[$i-1]
    }
    
    $PlatformStatus.EventHistory[0] = @{
        Event = $PlatformStatus.Event
        EventStatus = $PlatformStatus.EventStatus
        EventReason = $PlatformStatus.EventReason
        EventStatusTarget = $PlatformStatus.EventStatusTarget
        EventCreatedAt = $PlatformStatus.EventCreatedAt
        EventCreatedBy = $PlatformStatus.EventCreatedBy
        EventUpdatedAt = $PlatformStatus.EventUpdatedAt
        EventCompletedAt = $PlatformStatus.EventCompletedAt
        EventHasCompleted = $PlatformStatus.EventHasCompleted
    }

    return

}

function global:Set-PlatformEvent {
            
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Event,
        [Parameter(Mandatory=$false)][string]$Context,
        [Parameter(Mandatory=$false)][string]$EventReason,
        [Parameter(Mandatory=$false)][ValidateSet('In Progress','Completed','Failed','Reset','Testing')][string]$EventStatus,
        [Parameter(Mandatory=$false)][string]$EventStatusTarget,
        [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus)

    )
    
    $PlatformStatus.Event = $Event
    $PlatformStatus.EventStatus = $EventStatus
    $PlatformStatus.EventReason = $EventReason
    $PlatformStatus.EventStatusTarget = $EventStatusTarget ? $EventStatusTarget : $PlatformEventStatusTarget.$($Event)
    $PlatformStatus.EventCreatedAt = [datetime]::Now
    $PlatformStatus.EventCreatedBy = $Context ?? $global:Product.Id
    $PlatformStatus.EventHasCompleted = $EventStatus -eq "Completed" ? $true : $false

    Push-EventHistory -PlatformStatus $PlatformStatus

    $PlatformStatus | Write-Cache platformstatus

    $result = Send-PlatformEventMessage -PlatformStatus $PlatformStatus -NoThrottle
    $result | Out-Null

    return

}

function global:Reset-PlatformEvent {

    [CmdletBinding()]
    param ()

    $platformStatus = Get-PlatformStatus

    $platformStatus.Event = $null
    $platformStatus.EventReason = $null
    $platformStatus.EventStatus = $null
    $platformStatus.EventStatusTarget = $null
    $platformStatus.EventCreatedAt = [datetime]::MinValue
    $platformStatus.EventUpdatedAt = [datetime]::MinValue
    $platformStatus.EventCreatedBy = $null
    $platformStatus.EventHasCompleted = $false
    $platformStatus.EventHistory = @()

    $platformStatus | Write-Cache platformstatus

    return $platformStatus

}

#endregion EVENT