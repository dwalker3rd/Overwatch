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

    $platformStatus | Write-Cache platformstatus

    Write-Log -EntryType Event -Action $PlatformStatus.Event -Target Platform -Status $PlatformStatus.EventStatus -Message $PlatformStatus.EventReason

    return $platformStatus

}

function global:Initialize-PlatformEventHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

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
        ComputerName = $COMPUTERNAME
        TimeStamp = [datetime]::Now
    }

    $platformEventHistory | Write-Cache platformEventHistory

    return $platformEventHistory

}

function Update-PlatformEventHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $platformEventHistory = [PlatformEvent[]](Get-PlatformEventHistory -ComputerName $ComputerName)

    if ($platformEventHistory.Count -gt $PlatformEventHistoryMax) {
        $platformEventHistory = 
            ($platformEventHistory | Sort-Object -Property TimeStamp -Descending)[0..$PlatformEventHistoryMax] | 
                Sort-Object -Property TimeStamp
    }

    $platformEventHistory += [PlatformEvent]@{
        Event = $PlatformStatus.Event
        EventStatus = $PlatformStatus.EventStatus
        EventReason = $PlatformStatus.EventReason
        EventStatusTarget = $PlatformStatus.EventStatusTarget
        EventCreatedBy = $PlatformStatus.EventCreatedBy
        EventCreatedAt = $PlatformStatus.EventCreatedAt
        EventUpdatedAt = $PlatformStatus.EventUpdatedAt
        EventCompletedAt = $PlatformStatus.EventCompletedAt
        EventHasCompleted = $PlatformStatus.EventHasCompleted
        ComputerName = $COMPUTERNAME
        TimeStamp = [datetime]::Now
    }

    $platformEventHistory | Write-Cache platformEventHistory -ComputerName $ComputerName

    return

}

function global:Log-PlatformEventHistory {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    foreach ($node in $ComputerName) {

        $logName = ![string]::IsNullOrEmpty($Name) ? $Name : (Get-EnvironConfig Environ.Instance -ComputerName $node)

        foreach ($platformEvent in (Get-PlatformEventHistory -ComputerName $ComputerName)) {
            $timeStamp = @((Get-Date($platformEvent.EventCreatedAt) -Millisecond 0),(Get-Date($platformEvent.EventUpdatedAt) -Millisecond 0),(Get-Date($platformEvent.EventCompletedAt) -Millisecond 0)) | Sort-Object | Select-Object -Last 1
            Write-Log -Name $logName -Context $platformEvent.EventCreatedBy -EntryType Event -TimeStamp $timeStamp -Action $platformEvent.Event -Target Platform -Status $platformEvent.EventStatus -Message $platformEvent.EventReason
        }

        Repair-Log $logName

    }

}

function global:Get-PlatformEventHistory {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Event,
        [Parameter(Mandatory=$false)][string]$Context,
        [Parameter(Mandatory=$false)][string]$EventReason,
        [Parameter(Mandatory=$false)][ValidateSet("In Progress","InProgress","Completed","Failed","Reset","Testing")][string]$EventStatus,
        [Parameter(Mandatory=$false)][string]$EventStatusTarget,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Since")][object]$After,
        [Parameter(Mandatory=$false)][Alias("Until")][object]$Before,
        [Parameter(Mandatory=$false)][datetime]$At,
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

    if ($(get-cache platformEventHistory -ComputerName $ComputerName).Exists()) {
        $platformEventHistory = [PlatformEvent[]](Read-Cache platformEventHistory -ComputerName $ComputerName)
    }
    else {
        if ($ComputerName -eq $env:COMPUTERNAME) {
            $platformEventHistory = [PlatformEvent[]](Initialize-PlatformEventHistory)
        }
        else {
            return $null
        }
    }

    # retrofixes after class change
    foreach ($_event in $platformEventHistory) {
        if (!$_event.ComputerName) { $_event.ComputerName = $env:COMPUTERNAME }
        if ((Get-Date($_event.EventCreatedAt)) -ne [datetime]::MinValue -and $null -ne $_event.EventCreatedAt) {
            if ((Get-Date($_event.EventUpdatedAt)) -eq [datetime]::MinValue) { $_event.EventUpdatedAt = $_event.EventCreatedAt}
            if ((Get-Date($_event.EventCompletedAt)) -eq [datetime]::MinValue) { $_event.EventCompletedAt = $_event.EventCreatedAt}
        }
        if ($_event.TimeStamp = [datetime]::MinValue) {
            $_event.TimeStamp = (@((Get-Date($_event.EventCreatedAt) -Millisecond 0),(Get-Date($_event.EventUpdatedAt) -Millisecond 0),(Get-Date($_event.EventCompletedAt) -Millisecond 0)) | Sort-Object | Select-Object -Last 1)
        }
    }
    
    $platformEventHistory = $platformEventHistory | Sort-Object -Property TimeStamp

    if ($Event) {$platformEventHistory = $platformEventHistory | Where-Object {$_.Event -eq $Event}}
    if ($EventStatus) {$platformEventHistory = $platformEventHistory | Where-Object {$_.EventStatus -eq $EventStatus}}
    if ($EventStatusTarget) {$platformEventHistory = $platformEventHistory | Where-Object {$_.EventStatusTarget -eq $EventStatusTarget}}
    if ($EventReason) {$platformEventHistory = $platformEventHistory | Where-Object {$_.EventReason -eq $EventReason}}
    if ($Context) {$platformEventHistory = $platformEventHistory | Where-Object {$_.Context -eq $Context}}

    if ($After) {$platformEventHistory = $platformEventHistory | Where-Object {(Get-Date($_.EventCreatedAt) -Millisecond 0) -gt $After -or (Get-Date($_.EventUpdatedAt) -Millisecond 0) -gt $After -or (Get-Date($_.EventCompletedAt) -Millisecond 0) -gt $After}}
    if ($Before) {$platformEventHistory = $platformEventHistory | Where-Object {(Get-Date($_.EventCreatedAt) -Millisecond 0) -lt $Before -or (Get-Date($_.EventUpdatedAt) -Millisecond 0) -lt $Before -or (Get-Date($_.EventCompletedAt) -Millisecond 0) -lt $Before}}
    if ($Before) {$platformEventHistory = $platformEventHistory | Where-Object {(Get-Date($_.EventCreatedAt) -Millisecond 0) -lt $Before -or (Get-Date($_.EventUpdatedAt) -Millisecond 0) -lt $Before -or (Get-Date($_.EventCompletedAt) -Millisecond 0) -lt $Before}}
    if ($At) {
        $_event = $platformEventHistory | Where-Object {(@((Get-Date($_.EventCreatedAt) -Millisecond 0),(Get-Date($_.EventUpdatedAt) -Millisecond 0),(Get-Date($_.EventCompletedAt) -Millisecond 0)) | Sort-Object | Select-Object -Last 1) -le (Get-Date($At) -Millisecond 0)} | Select-Object -Last 1
        $_timestampDiff = (@((Get-Date($_event.EventCreatedAt) -Millisecond 0),(Get-Date($_event.EventUpdatedAt) -Millisecond 0),(Get-Date($_event.EventCompletedAt) -Millisecond 0)) | Sort-Object | Select-Object -Last 1) - (Get-Date($At) -Millisecond 0)
        $platformEventHistory = $_event.EventHasCompleted -and [math]::Abs($_timestampDiff.TotalSeconds) -gt 30 ? $null : $_event
    }
    if ($Newest) {$platformEventHistory = $platformEventHistory | Select-Object -Last $Newest}
    if ($Oldest) {$platformEventHistory = $platformEventHistory | Select-Object -First $Oldest}

    $sortParams = @{
        Property = $Property
    }
    if ($Descending) { $sortParams += @{ Descending = $true } }

    return $platformEventHistory | Select-Object -Property $($View ? $PlatformEventView.$($View) : $($PlatformEventView.Default)) | Sort-Object @sortParams

}

function global:Show-PlatformEvent {

    param(
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    if ($ComputerName -eq $env:COMPUTERNAME) {

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

    }

    $platformEventHistory = Get-PlatformEventHistory -ComputerName $ComputerName
    $platformEventHistory | 
        Sort-Object -Property TimeStamp -Descending | 
            Format-Table -Property ComputerName, Event, EventReason, EventStatus, EventCreatedBy, EventCreatedAt, EventUpdatedAt, EventCompletedAt, EventHasCompleted, EventStatusTarget, TimeStamp

}

#endregion EVENT