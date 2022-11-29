$PlatformEventHistoryMax = 72 # 6 hours if the interval is 5 minutes

function global:Set-PlatformEvent {
            
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Event,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$false)][string]$EventReason,
        [Parameter(Mandatory=$false)][ValidateSet("InProgress","In Progress","Completed","Failed","Reset","Testing")][string]$EventStatus,
        [Parameter(Mandatory=$false)][string]$EventStatusTarget,
        [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus)

    )

    if ($EventStatus -eq "InProgress") {$EventStatus = "In Progress"}
    
    $PlatformStatus.Event = (Get-Culture).TextInfo.ToTitleCase($Event)
    $PlatformStatus.EventStatus = (Get-Culture).TextInfo.ToTitleCase($EventStatus)
    $PlatformStatus.EventReason = $EventReason
    $PlatformStatus.EventStatusTarget = (Get-Culture).TextInfo.ToTitleCase($EventStatusTarget ? $EventStatusTarget : $PlatformEventStatusTarget.$($Event))
    $PlatformStatus.EventCreatedAt = [datetime]::Now
    $PlatformStatus.EventCreatedBy = (Get-Culture).TextInfo.ToTitleCase($Context)
    $PlatformStatus.EventCompletedAt = [datetime]::MinValue
    $PlatformStatus.EventHasCompleted = $EventStatus -eq "Completed" ? $true : $false

    Update-PlatformEventHistory -PlatformStatus $PlatformStatus

    $PlatformStatus | Write-Cache platformstatus

    Write-Log -EntryType Event -Action $PlatformStatus.Event -Target Platform -Status $PlatformStatus.EventStatus -Message $PlatformStatus.EventReason

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

    Write-Log -EntryType Event -Action $PlatformStatus.Event -Target Platform -Status $PlatformStatus.EventStatus -Message $PlatformStatus.EventReason

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

function global:Get-PlatformEventHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Event,
        [Parameter(Mandatory=$false)][string]$Context,
        [Parameter(Mandatory=$false)][string]$EventReason,
        [Parameter(Mandatory=$false)][ValidateSet("In Progress","InProgress","Completed","Failed","Reset","Testing")][string]$EventStatus,
        [Parameter(Mandatory=$false)][string]$EventStatusTarget,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Since")][object]$After,
        [Parameter(Mandatory=$false)][Alias("Until")][object]$Before,
        # [Parameter(Mandatory=$false)][datetime]$At,
        [Parameter(Mandatory=$false)][Alias("Last")][int32]$Newest,
        [Parameter(Mandatory=$false)][Alias("First")][int32]$Oldest,
        [Parameter(Mandatory=$false)][int32]$Days,
        [Parameter(Mandatory=$false)][int32]$Hours,
        [Parameter(Mandatory=$false)][int32]$Minutes,
        [Parameter(Mandatory=$false)][string]$View,
        [Parameter(Mandatory=$false)][ValidateSet("EventCreatedAt","EventUpdatedAt","EventCompletedAt")][string]$Property = "EventUpdatedAt",
        [switch]$Today,
        [switch]$Yesterday,
        [switch]$Descending
    )

    if ($EventStatus -eq "InProgress") {$EventStatus = "In Progress"}

    # $After/$Before is a datetime passed as an object
    # This allows using strings to specify today or yesterday

    $After = $Days ? ([datetime]::Today).AddDays(-1 * [math]::Abs($Days)) : $After
    $After = $Hours ? ([datetime]::Now).AddHours(-1 * [math]::Abs($Hours)) : $After
    $After = $Minutes ? ([datetime]::Now).AddMinutes(-1 * [math]::Abs($Minutes)) : $After

    If (![string]::IsNullOrEmpty($After)) {
        $After = switch ($After) {
            "Today" { [datetime]::Today }
            "Yesterday" { ([datetime]::Today).AddDays(-1) }
            default { 
                switch ($After.GetType().Name) {
                    "String" { Get-Date ($After) }
                    "DateTime" { $After }
                    "TimeSpan" { [datetime]::Today.Add(-$After.Duration()) }
                }
            }
        }
    }

    If (![string]::IsNullOrEmpty($Before)) {
        $Before = switch ($Before) {
            "Today" { [datetime]::Today }
            "Yesterday" { ([datetime]::Today).AddDays(-1) }
            default { 
                switch ($Before.GetType().Name) {
                    "String" { Get-Date ($Before) }
                    "DateTime" { $Before }
                    "TimeSpan" { [datetime]::Today.Add(-$Before.Duration()) }
                }
            }
        }
    }

    if ($(get-cache platformEventHistory).Exists()) {
        $platformEventHistory = [PlatformEvent[]](Read-Cache platformEventHistory)
    }
    else {
        $platformEventHistory = [PlatformEvent[]](Initialize-PlatformEventHistory)
    }
    
    $platformEventHistory = $platformEventHistory | Sort-Object -Property EventCreatedAt

    if ($Event) {$platformEventHistory = $platformEventHistory | Where-Object {$_.Event -eq $Event}}
    if ($EventStatus) {$platformEventHistory = $platformEventHistory | Where-Object {$_.EventStatus -eq $EventStatus}}
    if ($EventStatusTarget) {$platformEventHistory = $platformEventHistory | Where-Object {$_.EventStatusTarget -eq $EventStatusTarget}}
    if ($EventReason) {$platformEventHistory = $platformEventHistory | Where-Object {$_.EventReason -eq $EventReason}}
    if ($Context) {$platformEventHistory = $platformEventHistory | Where-Object {$_.Context -eq $Context}}

    if ($After) {$platformEventHistory = $platformEventHistory | Where-Object {(Get-Date($_.EventCreatedAt) -Millisecond 0) -gt $After -or (Get-Date($_.EventUpdatedAt) -Millisecond 0) -gt $After -or (Get-Date($_.EventCompletedAt) -Millisecond 0) -gt $After}}
    if ($Before) {$platformEventHistory = $platformEventHistory | Where-Object {(Get-Date($_.EventCreatedAt) -Millisecond 0) -lt $Before -or (Get-Date($_.EventUpdatedAt) -Millisecond 0) -lt $Before -or (Get-Date($_.EventCompletedAt) -Millisecond 0) -lt $Before}}
    # if ($At) {
    #     $_event = $platformEventHistory | Where-Object {(@((Get-Date($_.EventCreatedAt) -Millisecond 0),(Get-Date($_.EventUpdatedAt) -Millisecond 0),(Get-Date($_.EventCompletedAt) -Millisecond 0)) | Sort-Object | Select-Object -Last 1) -le (Get-Date($At) -Millisecond 0)} | Select-Object -Last 1
    #     $_timestampDiff = (@((Get-Date($_event.EventCreatedAt) -Millisecond 0),(Get-Date($_event.EventUpdatedAt) -Millisecond 0),(Get-Date($_event.EventCompletedAt) -Millisecond 0)) | Sort-Object | Select-Object -Last 1) - (Get-Date($At) -Millisecond 0)
    #     $platformEventHistory = $_event.EventHasCompleted -and [math]::Abs($_timestampDiff.TotalSeconds) -gt 30 ? $null : $_event
    # }
    if ($Newest) {$platformEventHistory = $platformEventHistory | Select-Object -Last $Newest}
    if ($Oldest) {$platformEventHistory = $platformEventHistory | Select-Object -First $Oldest}

    $sortParams = @{
        Property = $Property
    }
    if ($Descending) { $sortParams += @{ Descending = $true } }

    return $platformEventHistory | Select-Object -Property $($View ? $PlatformEventView.$($View) : $($PlatformEventView.Default)) | Sort-Object @sortParams

}

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

#endregion EVENT