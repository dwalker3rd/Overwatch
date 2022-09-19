$PlatformEventHistoryMax = 72 # 6 hours if the interval is 5 minutes

function global:Show-PlatformEvent {

    $platformStatus = Get-PlatformStatus -CacheOnly

    $properties = $platformStatus.psobject.Properties | Where-Object {$_.name -like "Event*" -and $_.name -ne "EventHistory" -or $_.name -like "IsStopped*" -or $_.name -like "Intervention*"}
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

    Get-PlatformEventHistory | Format-Table -Property Event, EventReason, EventStatus, EventCreatedBy, EventCreatedAt, EventUpdatedAt, EventCompletedAt, EVentHasCompleted, EventStatusTarget

}

function global:Set-PlatformEvent {
            
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Event,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$false)][string]$EventReason,
        [Parameter(Mandatory=$false)][ValidateSet('In Progress','Completed','Failed','Reset','Testing')][string]$EventStatus,
        [Parameter(Mandatory=$false)][string]$EventStatusTarget,
        [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus)

    )
    
    $PlatformStatus.Event = (Get-Culture).TextInfo.ToTitleCase($Event)
    $PlatformStatus.EventStatus = (Get-Culture).TextInfo.ToTitleCase($EventStatus)
    $PlatformStatus.EventReason = $EventReason
    $PlatformStatus.EventStatusTarget = (Get-Culture).TextInfo.ToTitleCase($EventStatusTarget ? $EventStatusTarget : $PlatformEventStatusTarget.$($Event))
    $PlatformStatus.EventCreatedAt = [datetime]::Now
    $PlatformStatus.EventCreatedBy = (Get-Culture).TextInfo.ToTitleCase($Context)
    $PlatformStatus.EventHasCompleted = $EventStatus -eq "Completed" ? $true : $false

    Update-PlatformEventHistory -PlatformStatus $PlatformStatus

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
    $platformStatus.EventCreatedBy = $null
    $platformStatus.EventCreatedAt = [datetime]::MinValue
    $platformStatus.EventUpdatedAt = [datetime]::MinValue
    $platformStatus.EventCompletedAt = [datetime]::MinValue
    $platformStatus.EventHasCompleted = $false
    $platformStatus.EventHistory = @()

    $platformStatus | Write-Cache platformstatus

    return $platformStatus

}

function global:Initialize-PlatformEventHistory {

    [CmdletBinding()]
    param()

    $platformEventHistory = @()
    $platformEventHistory += [PlatformEvent]@{
        Event = $null
        EventStatus = $null
        EventReason = $null
        EventStatusTarget = $null
        EventCreatedBy = $null
        EventCreatedAt = [datetime]::MinValue
        EventUpdatedAt = [datetime]::MinValue
        EventCompletedAt = [datetime]::MinValue
        EventHasCompleted = $false
    }

    $platformEventHistory | Write-Cache platformEventHistory

    return $platformEventHistory

}

function global:Get-PlatformEventHistory {

    [CmdletBinding()]
    param ()

    if ($(get-cache platformEventHistory).Exists()) {
        $platformEventHistory = [PlatformEvent[]](Read-Cache platformEventHistory)
    }
    else {
        $platformEventHistory = [PlatformEvent[]](Initialize-PlatformEventHistory)
    }

    return $platformEventHistory
}

function Update-PlatformEventHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus
    )

    $platformEventHistory = [PlatformEvent[]](Get-PlatformEventHistory)

    if ($platformEventHistory.Count -lt $PlatformEventHistoryMax) {
        $platformEventHistory += @{}
    }
    for ($i = $platformEventHistory.Count-1; $i -gt 0; $i--) {
        $platformEventHistory[$i] = $platformEventHistory[$i-1]
    }
    $platformEventHistory[0] = @{
        Event = $PlatformStatus.Event
        EventStatus = $PlatformStatus.EventStatus
        EventReason = $PlatformStatus.EventReason
        EventStatusTarget = $PlatformStatus.EventStatusTarget
        EventCreatedBy = $PlatformStatus.EventCreatedBy
        EventCreatedAt = $PlatformStatus.EventCreatedAt
        EventUpdatedAt = $PlatformStatus.EventUpdatedAt
        EventCompletedAt = $PlatformStatus.EventCompletedAt
        EventHasCompleted = $PlatformStatus.EventHasCompleted
    }

    $platformEventHistory | Write-Cache platformEventHistory

    return

}

#endregion EVENT