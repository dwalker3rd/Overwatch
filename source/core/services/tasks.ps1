#region TASKS

function global:Register-PlatformTask {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName,
        [Parameter(Mandatory=$true)][string]$Execute,        
        [Parameter(Mandatory=$true)][string]$Argument,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][DateTime]$At,
        [Parameter(Mandatory=$false)][TimeSpan]$RepetitionInterval,
        [Parameter(Mandatory=$false)][TimeSpan]$RepetitionDuration,
        [switch]$Once,
        [switch]$Daily,
        [switch]$Weekly,
        [switch]$Monthly,
        [Parameter(Mandatory=$false)][TimeSpan]$ExecutionTimeLimit,
        [Parameter(Mandatory=$false)][ValidateSet("Limited","Highest")][string]$RunLevel="Highest",
        [Parameter(Mandatory=$false)][System.Management.Automation.PSCredential]$Credentials = $(Get-Credentials "localadmin-$($Platform.Instance)"),
        [switch]$Start,
        [Parameter(Mandatory=$false)][string]$Subscription,
        [switch]$SyncAcrossTimeZones,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][string]$RandomDelay,
        [switch]$Disable
    )

    $product = Get-Product -Id $Id
    if (!$TaskName) {$TaskName = $product.TaskName}
    if (!$Description) {$Description = $product.Description}

    $task = Get-PlatformTask -TaskName $TaskName
    if ($task) {
        Write-Error "The task ""$($TaskName)"" already exists."
        return
    }

    # if ($Once -and !($RepetitionInterval -and $RepetitionDuration)) {throw "RepetitionInterval and RepetitionDuration must be used together."}

    $CimClass = $null
    if ($Once) {$CimClass = "MSFT_TaskTimeTrigger"}
    if ($Daily) {$CimClass = "MSFT_TaskDailyTrigger"}
    if ($Weekly) {throw "Weekly triggers not yet supported."}
    if ($Monthly) {throw "Monthly triggers not yet supported."}

    $triggerProperties = @{
        Enabled = $true
        StartBoundary = $At.ToString($SyncAcrossTimeZones ? "o" : "s")
    }
    if ($RandomDelay) {$triggerProperties.RandomDelay = $RandomDelay}

    $timeTrigger = Get-CimClass $CimClass root/Microsoft/Windows/TaskScheduler | 
        New-CimInstance -ClientOnly -Property $triggerProperties

    if ($Once) {
        if ($RepetitionInterval) {
            $repetition = Get-CimClass MSFT_TaskRepetitionPattern root/Microsoft/Windows/TaskScheduler | `
                New-CimInstance -ClientOnly -Property @{Interval = $([system.xml.xmlconvert]::tostring($RepetitionInterval))}
            if ($RepetitionDuration -eq [TimeSpan]::MaxValue) {
                $repetition.StopAtDurationEnd = $true
            }
            else {
                $repetition.StopAtDurationEnd = $false
                $repetition.Duration = $([system.xml.xmlconvert]::tostring($RepetitionDuration))
            }
            $timeTrigger.Repetition = $repetition
        }
    }
    [ciminstance[]]$triggers = $timeTrigger

    if ($Subscription) {
        $eventTrigger = Get-CimClass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler | 
            New-CimInstance -ClientOnly -Property @{Enabled = $true;Subscription = $Subscription}
        $triggers += $eventTrigger
    }
    
    $actionArgs = @{
        Execute = $Execute
        Argument = $Argument
        WorkingDirectory = $WorkingDirectory
    }
    $action = New-ScheduledTaskAction @actionArgs

    $settings = Get-CimClass MSFT_TaskSettings Root/Microsoft/Windows/TaskScheduler | New-CimInstance -ClientOnly -Property @{
        Enabled = !$Disable
        AllowDemandStart = $true 
        ExecutionTimeLimit = $([system.xml.xmlconvert]::tostring($ExecutionTimeLimit))
    }

    $task = Register-ScheduledTask -TaskName $TaskName `
        -User $Credentials.UserName -Password $Credentials.GetNetworkCredential().Password `
        -Action $action -RunLevel $RunLevel -Trigger $triggers -Settings $settings `
        -Description $Description
    if ($Start) {
        $isStarted = Start-PlatformTask -TaskName $TaskName
        $isStarted | Out-Null
    }

}

function global:Unregister-PlatformTask {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName
    ) 
    
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

    return

}

function global:Get-PlatformTask { 

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$ExcludeId,
        [Parameter(Mandatory=$false)][string]$TaskName,
        [Parameter(Mandatory=$false)][string]$ExcludeTaskName,
        [Parameter(Mandatory=$false)][string]$View,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [switch]$Disabled
    )

    $taskState = @("Unknown","Disabled","Queued","Ready","Running")
    $taskStateOK = @("Queued","Ready","Running")

    $platformTasks = @()
    foreach ($node in $ComputerName) {

        $_taskName = $TaskName
        if ($Id -and !$TaskName) {
            $_taskName = $(Get-Product -Id $Id -ComputerName $node).TaskName
        }

        # if ([string]::IsNullOrEmpty($_taskName)) { continue }

        $psSession = Use-PSSession+ -ComputerName $node
        $tasks = $_taskName ? $(Invoke-Command -Session $psSession {Get-ScheduledTask -TaskName $using:_taskName -ErrorAction SilentlyContinue}) : $(Invoke-Command -Session $psSession {Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -like "*$($using:Overwatch.Name)*"}})
        if (!$tasks) { continue }

        $products = @()
        $maxGetProductAttempts = 3
        $productAttempts = 0
        do {
            $productAttempts++
            try {
                $products += Get-Product -ComputerName $node
                if (!$products) { throw }
            }
            catch {
                # Start-Sleep -Seconds 1
                
            }
        } until ($products -or $productAttempts -gt $maxGetProductAttempts)

        $cimSession = New-CimSession -ComputerName $node

        $tasks | ForEach-Object {
            $task = $_
            $taskProduct = $products | Where-Object {$_.TaskName -eq $task.TaskName}
            $platformTask = [PlatformCim]@{
                Class = "Task"
                Name = $task.TaskName
                DisplayName = $task.TaskName
                Instance = $task
                Description = $task.Description
                Required = $true
                Node = $node
                Status = $($taskState[$task.State])
                StatusOK = $taskStateOK
                IsOK = $taskStateOK -contains $($taskState[$task.State])
                ProductId = $taskProduct.Id
            }
            $platformTask | Add-Member -NotePropertyName ScheduledTaskInfo -NotePropertyValue (Get-ScheduledTaskInfo -CimSession $cimSession -TaskName $task.TaskName)
            $platformTasks += $platformTask
        }

        Remove-CimSession $cimSession

    }

    if ($ExcludeId) {$platformTasks = $platformTasks | Where-Object {$_.TaskName -ne $(Get-Product $ExcludeId).Name}}
    if ($ExcludeTaskName) {$platformTasks = $platformTasks | Where-Object {$_.TaskName -ne $ExcludeTaskName}}
    if ($Disabled) { $platformTasks = $platformTasks | Where-Object {$_.Status -in $global:PlatformTaskState.Disabled}}

    $dynamicView = @()
    $dynamicView += $([PlatformCim]@{}).psobject.properties.name
    $dynamicView += "ScheduledTaskInfo"

    return $platformTasks | Select-Object -Property $($View ? $CimView.$($View) : $dynamicView)

}

function global:Get-PlatformTaskInterval {

    [CmdletBinding()]
    [OutputType([timespan])]
    param (
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName
    )

    if ($Id -and !$TaskName) {$TaskName = $(Get-Product -Id $Id).TaskName}
    $repetitionInterval = ((Get-PlatformTask -TaskName $TaskName).Instance.Triggers.Repetition | Where-Object {$_.Interval}).Interval
    $regexMatchGroups = [regex]::Match($repetitionInterval,$global:RegexPattern.ScheduledTask.RepetitionPattern).Groups | Where-Object {$_.Index -ne 0 -and ![string]::IsNullOrEmpty($_.Value)}
    
    $repetitionIntervalInSeconds = 0
    foreach ($regexMatchGroup in $regexMatchGroups) {
        $multiplier = switch ($regexMatchGroup.Name) {
            "day" { 24 * 60 * 60}
            "hour" { 60 * 60 }
            "minute" { 60 }
            "second" { 1 }
        }
        $repetitionIntervalInSeconds += [int]$regexMatchGroup.Value * [int]$multiplier
    }

    return New-TimeSpan -Seconds $repetitionIntervalInSeconds

}

function global:Wait-PlatformTask {

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByObject")][object]$PlatformTask,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ById")][string]$Id,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByTaskName")][string]$TaskName,
        [Parameter(Mandatory=$false)][ValidateSet("Unknown","Disabled","Queued","Ready","Running")][string[]]$State = $global:PlatformTaskState.Enabled,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [Parameter(Mandatory=$false)][ValidateSet("IsTargetState","PlatformTask.Status","PlatformTask","null")][string]$OutputType = "IsTargetState",
        [switch]$Not
    ) 

    if ($PlatformTask) {
        $Id = $PlatformTask.ProductID
        $TaskName = $PlatformTask.Name
    }
    else {
        $Id = $global:Catalog.Product.$Id.Id
        $TaskName = [string]::IsNullOrEmpty($TaskName) ? (Get-Product -Id $Id).TaskName : $TaskName
        $PlatformTask = Get-PlatformTask -Id $Id 
    }

    $_state = @()
    $_state = $State | ForEach-Object {$global:PlatformTaskState.$_}

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $timerInterval = [Diagnostics.Stopwatch]::StartNew()

    $isTargetState = (!$Not -and $PlatformTask.Status -in $_state) -or ($Not -and $PlatformTask.Status -notin $_state)
    while (!$isTargetState -and ([math]::Round($timer.Elapsed.TotalSeconds,0) -lt $Timeout.TotalSeconds)) {
        Start-Sleep -seconds 1
        $PlatformTask = Get-PlatformTask -TaskName $TaskName
        $isTargetState = (!$Not -and $PlatformTask.Status -in $_state) -or ($Not -and $PlatformTask.Status -notin $_state)
        if ([math]::Round($timerInterval.Elapsed.TotalSeconds,0) -ge 10) {
            $timerInterval.Reset()
            $timerInterval.Start()
        }
    }

    $timerInterval.Stop()
    $timer.Stop()

    return Invoke-Expression "`$$OutputType"

}


function global:Disable-PlatformTask {

    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByObject")][object]$PlatformTask,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ById")][string]$Id,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByTaskName")][string]$TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [Parameter(Mandatory=$false)][ValidateSet("IsTargetState","PlatformTask.Status","PlatformTask","null")][string]$OutputType = "null"
    )

    if ($PlatformTask) {
        $Id = $PlatformTask.ProductID
        $TaskName = $PlatformTask.Name
    }
    else {
        $Id = $global:Catalog.Product.$Id.Id
        $TaskName = [string]::IsNullOrEmpty($TaskName) ? (Get-Product -Id $Id).TaskName : $TaskName
        $PlatformTask = Get-PlatformTask -Id $Id 
    }

    # check if PlatformTask is already disabled
    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Disabled
    if ($isTargetState) {
        return Invoke-Expression "`$$OutputType"
    }

    # disable PlatformTask
    $PlatformTask.Instance = Disable-ScheduledTask -TaskName $TaskName
    $PlatformTask.Status = $PlatformTask.Instance.State.ToString()

    # wait for PlatformTask to be disabled
    $PlatformTask = Wait-PlatformTask -PlatformTask $PlatformTask -State $global:PlatformTaskState.Disabled -OutputType PlatformTask -Timeout $Timeout

    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Disabled
    $isTargetState | Out-Null

    return Invoke-Expression "`$$OutputType"

}

function global:Disable-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Enabled
    ) 

    # Write-Host+ -Iff (!$Quiet)

    $platformTasks = Get-PlatformTask
    if ($Enabled) {
        $platformTasks = $platformTasks | Where-Object {$_.Status -in $global:PlatformTaskState.Enabled}
    }

    $platformTasks | ForEach-Object {
        $platformTask = Disable-PlatformTask -PlatformTask $_ -OutputType "PlatformTask" -Timeout $Timeout
        # $message = "<$($platformTask.ProductID) <.>32> $($platformTask.Status.ToUpper())"
        # Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($platformTask.Status -in $global:PlatformTaskState.platformTasks ? "Red" : "DarkGreen")
        Write-Log -EntryType Information -Action "Disable-PlatformTasks" -Target $platformTask.ProductID -Status $platformTask.Status -Force
    }

    # Write-Host+ -Iff (!$Quiet)

    return $platformTasks

}

function global:Enable-PlatformTask {

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByObject")][object]$PlatformTask,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ById")][string]$Id,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByTaskName")][string]$TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [Parameter(Mandatory=$false)][ValidateSet("IsTargetState","PlatformTask.Status","PlatformTask","null")][string]$OutputType = "null"
    )

    if ($PlatformTask) {
        $Id = $PlatformTask.ProductID
        $TaskName = $PlatformTask.Name
    }
    else {
        $Id = $global:Catalog.Product.$Id.Id
        $TaskName = [string]::IsNullOrEmpty($TaskName) ? (Get-Product -Id $Id).TaskName : $TaskName
        $PlatformTask = Get-PlatformTask -Id $Id 
    }

    # check if PlatformTask is already enabled
    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Enabled
    if ($isTargetState) {
        return Invoke-Expression "`$$OutputType"
    }

    # enable PlatformTask
    $PlatformTask.Instance = Enable-ScheduledTask -TaskName $TaskName
    $PlatformTask.Status = $PlatformTask.Instance.State.ToString()

    # wait for PlatformTask to be enabled
    $PlatformTask = Wait-PlatformTask -PlatformTask $PlatformTask -State $global:PlatformTaskState.Enabled -OutputType PlatformTask -Timeout $Timeout

    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Enabled
    $isTargetState | Out-Null

    return Invoke-Expression "`$$OutputType"

}

function global:Enable-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Disabled
    ) 

    # Write-Host+ -Iff (!$Quiet)

    $platformTasks = Get-PlatformTask
    if ($Disabled) {
        $platformTasks = $platformTasks | Where-Object {$_.Status -in $global:PlatformTaskState.Disabled}
    }

    $platformTasks | ForEach-Object {
        $platformTask = Enable-PlatformTask -PlatformTask $_ -OutputType "PlatformTask" -Timeout $Timeout
        # $message = "<$($platformTask.ProductID) <.>32> $($platformTask.Status.ToUpper())"
        # Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($platformTask.Status -in $global:PlatformTaskState.Enabled ? "DarkGreen" : "Red")
        Write-Log -EntryType Information -Action "Enable-PlatformTasks" -Target $platformTask.ProductID -Status $platformTask.Status -Force
    }

    # Write-Host+ -Iff (!$Quiet)

    return $platformTasks

}

function global:Start-PlatformTask {

    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByObject")][object]$PlatformTask,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ById")][string]$Id,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByTaskName")][string]$TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [Parameter(Mandatory=$false)][ValidateSet("IsTargetState","PlatformTask.Status","PlatformTask","null")][string]$OutputType = "IsTargetState",
        [switch]$Force
    )

    if ($PlatformTask) {
        $Id = $PlatformTask.ProductID
        $TaskName = $PlatformTask.Name
    }
    else {
        $Id = $global:Catalog.Product.$Id.Id
        $TaskName = [string]::IsNullOrEmpty($TaskName) ? (Get-Product -Id $Id).TaskName : $TaskName
        $PlatformTask = Get-PlatformTask -Id $Id 
    }

    # check if PlatformTask is already started
    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Started
    if ($isTargetState) {
        return Invoke-Expression "`$$OutputType"
    }

    # check if PlatformTask is disabled
    if ($PlatformTask.Status -in $global:PlatformTaskState.Disabled) {
        
        # Write-Host+ -Iff $(!($Force.IsPresent) -and !$Quiet) -NoTrace "WARN: The platform task is disabled and cannot be started." -ForegroundColor DarkYellow
        # Write-Host+ -Iff $(!($Force.IsPresent) -and !$Quiet) -NoTrace "INFO: To force the platform task to start, add the -Force switch." -ForegroundColor DarkYellow
        # Write-Host+ -Iff $($Force.IsPresent -and !$Quiet) -NoTrace "INFO: Starting with FORCE." -ForegroundColor DarkYellow
        
        if (!$Force) { 
            return Invoke-Expression "`$$OutputType"
        }
        $Force = $false
        
        Write-Host+

        # enable PlatformTask
        $PlatformTask.Instance = Enable-ScheduledTask -TaskName $TaskName
        $PlatformTask.Status = $PlatformTask.Instance.State.ToString()

    }

    # start task
    $PlatformTask.Instance = Start-ScheduledTask -TaskName $TaskName

    # wait for PlatformTask to be enabled
    $PlatformTask = Wait-PlatformTask -PlatformTask $PlatformTask -State $global:PlatformTaskState.Started -OutputType PlatformTask -Timeout $Timeout

    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Started
    $isTargetState | Out-Null

    return Invoke-Expression "`$$OutputType"

}

function global:Stop-PlatformTask {

    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByObject")][object]$PlatformTask,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ById")][string]$Id,
        [Parameter(Mandatory=$false,Position=0,ParameterSetName="ByTaskName")][string]$TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [Parameter(Mandatory=$false)][ValidateSet("IsTargetState","PlatformTask.Status","PlatformTask","null")][string]$OutputType = "IsTargetState"
    )

    if ($PlatformTask) {
        $Id = $PlatformTask.ProductID
        $TaskName = $PlatformTask.Name
    }
    else {
        $Id = $global:Catalog.Product.$Id.Id
        $TaskName = [string]::IsNullOrEmpty($TaskName) ? (Get-Product -Id $Id).TaskName : $TaskName
        $PlatformTask = Get-PlatformTask -Id $Id 
    }

    # check if PlatformTask is already stopped
    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Stopped
    if ($isTargetState) {
        return Invoke-Expression "`$$OutputType"
    }

    # stop task
    $PlatformTask.Instance = Stop-ScheduledTask -TaskName $TaskName
    $PlatformTask.Status = $PlatformTask.Instance.State.ToString()

    # wait for PlatformTask to be enabled
    $PlatformTask = Wait-PlatformTask -PlatformTask $PlatformTask -State $global:PlatformTaskState.Stopped -OutputType PlatformTask -Timeout $Timeout

    $isTargetState = $PlatformTask.Status -in $global:PlatformTaskState.Stopped
    $isTargetState | Out-Null

    return Invoke-Expression "`$$OutputType"

}

function global:Show-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline,Position=0)][Object]$InputObject,
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [switch]$Disabled,
        [switch]$Refresh,

        [ValidateRange(5,300)]
        [Parameter(Mandatory=$false)]
        [Alias("Interval","IntervalSeconds")]
        [int]$RefreshIntervalSeconds = 5,

        [ValidateRange(0,3600)]
        [Parameter(Mandatory=$false)][int]$MaxRefreshPeriodSeconds = 600
    ) 

    begin {
        $platformTasks = @()
    }
    process {
        $platformTasks += $InputObject
    }
    end {

        # WriteHostPlusPreference is set to SilentlyContinue/Quiet.  nothing to write/output, so return
        if ($global:WriteHostPlusPreference -ne "Continue") { return }

        # restrict refresh feature to non-pipelined data for the local machine (for now)
        # if ((![string]::IsNullOrEmpty($ComputerName) -and $ComputerName -ne $env:COMPUTERNAME) -or $platformTasks) { $Refresh = $false }

        if (!$ComputerName) {
            if (!$platformTasks) {
                $ComputerName = $env:COMPUTERNAME
                $platformTasks = Get-PlatformTask -ComputerName $ComputerName
            }
            elseif (($platformTasks | Get-Member)[0].TypeName -eq "System.String") { 
                $ComputerName = $env:COMPUTERNAME
                $platformTasks = $platformTasks | Foreach-Object {Get-PlatformTask $_ -ComputerName $ComputerName}
            }
            elseif (($platformTasks | Get-Member)[0].TypeName -eq "Selected.PlatformCim") {
                $ComputerName = $platformTasks.Node | Select-Object -Unique
            }
            else {
                # unhandled type
            }
        }
        else {
            if (!$platformTasks) {
                $platformTasks = Get-PlatformTask -ComputerName $ComputerName
            }
        }

        if (!$platformTasks) { return }
        
        if ($Disabled) { $platformTasks = $platformTasks | Where-Object {$_.Status -in $global:PlatformTaskState.Disabled} }
        if (!$platformTasks) { return }

        $_defaultColor = $global:consoleSequence.Default

        $formatData = [ordered]@{}
        $platformTaskSummaryFormatData = Get-FormatData -TypeName OverWatch.PlatformTask.Summary
        $formatDataDisplayEntries = $platformTaskSummaryFormatData.FormatViewDefinition.Control.Rows.Columns.DisplayEntry.Value
        $formatDataHeaders = $platformTaskSummaryFormatData.FormatViewDefinition.Control.Headers
        for ($i = 0; $i -lt $formatDataDisplayEntries.Count; $i++) {
            $formatData += @{
                $formatDataDisplayEntries[$i] = $formatDataHeaders[$i]
            }
        }

        try {

            Set-CursorInvisible

            $RefreshPeriodSecondsTotal = 0
            do {
                $platformTasksFormatted = @()
                foreach ($platformTask in $platformTasks) {

                    $_node = $platformTask.Node.ToLower()
                    $_product = $platformTask.ProductID + " "
                    $_productPadRight = $emptyString.PadLeft($formatData.PlatformTask.Width-1-$_product.Length," ")
                    $_status = $platformTask.Status + " "
                    $_statusPadRight = $emptyString.PadLeft($formatData.Status.Width-1-$_status.Length," ")
                    $_nextRunTime = ""
                    if ($platformTask.ScheduledTaskInfo.NextRunTime) {
                        $_nextRunTime = ($platformTask.ScheduledTaskInfo.NextRunTime).ToString('u') + " "
                    }
                    $_nextRunTimePadRight = $emptyString.PadLeft($formatData.NextRunTime.Width-1-$_nextRunTime.Length," ")
                    $_lastRunTime = ""
                    if ($platformTask.ScheduledTaskInfo.LastRunTime) {
                        $_lastRunTime = ($platformTask.ScheduledTaskInfo.LastRunTime).ToString('u') + " "
                    }
                    $_lastRunTimePadRight = $emptyString.PadLeft($formatData.LastRunTime.Width-1-$_lastRunTime.Length," ")

                    # hresult codes for scheduledtaskinfo ARE int32; however, other hresult codes can be passed thru lasttaskresult.
                    # some of these other codes are greater than [int32]::maxvalue.  To get the text for these error codes, they must 
                    # be converted to hex and then back to int32 which, (1) results in a negative number larger than [int32]::minvalue 
                    # that can (2) now becast as an int32 and (3) passed to the Win32Exception class constructor to retrieve the hresult text 
                    $_lastTaskResult = (New-Object System.ComponentModel.Win32Exception([int32]('0x{0:X}' -f $platformTask.ScheduledTaskInfo.LastTaskResult))).Message
                    if ($_lastTaskResult.Length -ge $formatData.LastTaskResult.Width) {
                        $_lastTaskResult = $_lastTaskResult.Substring(0,$formatData.LastTaskResult.Width-1) + " "
                    }
                    
                    $_lastTaskResultPadRight = $emptyString.PadLeft($formatData.LastTaskResult.Width-$_lastTaskResult.Length," ")

                    $_platformTaskColor = $global:consoleSequence.ForegroundWhite
                    $_statusColor = $global:consoleSequence.ForegroundDarkGray
                    $_nextRunTimeColor = $global:consoleSequence.ForegroundDarkGray
                    $_lastRunTimeColor = $global:consoleSequence.ForegroundDarkGray
                    $_lastTaskResultColor = $global:consoleSequence.ForegroundDarkGray

                    if ($platformTask.Status -in $global:PlatformTaskState.Running) {
                        $_statusColor = $global:consoleSequence.BrightForegroundGreen + $global:consoleSequence.Negative
                        $_lastTaskResultColor = $platformTask.ScheduledTaskInfo.LastTaskResult -ne 0 ? $global:consoleSequence.ForegroundGreen + $global:consoleSequence.Negative : $_lastTaskResultColor
                    }
                    elseif ($platformTask.Status -in $global:PlatformTaskState.Enabled) {
                        $_statusColor = $global:consoleSequence.ForegroundDarkGray
                    }
                    elseif ($platformTask.Status -in $global:PlatformTaskState.Disabled) {
                        $_statusColor = $global:consoleSequence.BrightForegroundRed + $global:consoleSequence.Negative
                        $_lastRunTimeColor = $global:consoleSequence.BrightForegroundRed
                        $_lastTaskResultColor = $platformTask.ScheduledTaskInfo.LastTaskResult -ne 0 ? $global:consoleSequence.BrightForegroundRed + $global:consoleSequence.Negative : $_lastTaskResultColor
                    }
                    elseif ($platformTask.Status -in $global:PlatformTaskState.Unknown -or $_lastTaskResult -contains "administrator has refused") {
                        $_statusColor = $global:consoleSequence.BrightForegroundYellow + $global:consoleSequence.Negative
                        $_lastTaskResultColor = $platformTask.ScheduledTaskInfo.LastTaskResult -ne 0 ? $global:consoleSequence.ForegroundYellow + $global:consoleSequence.Negative : $_lastTaskResultColor
                    }

                    # format summary rows with console sequences to control color
                    $platformTasksFormatted += [PSCustomObject]@{
                        # these fields are NOT displayed
                        PSTypeName = "OverWatch.PlatformTask.Summary"
                        Node = $_node
                        # these fields ARE displayed
                        PlatformTask = "$($_platformTaskColor)$($_product)$($_defaultColor)$($_productPadRight)"
                        Status = "$($_statusColor)$($_status)$($_defaultColor)$($_statusPadRight)"
                        NextRunTime = "$($_nextRunTimeColor)$($_nextRunTime)$($_defaultColor)$($_nextRunTimePadRight)"
                        LastRunTime = "$($_lastRunTimeColor)$($_lastRunTime)$($_defaultColor)$($_lastRunTimePadRight)"
                        LastTaskResult = "$($_lastTaskResultColor)$($_lastTaskResult)$($_defaultColor)$($_lastTaskResultPadRight)"
                    }
                }

                if ($platformTasksFormatted) { Write-Host+ }

                foreach ($node in $ComputerName) {

                    $platformTasksFormattedByNode = $platformTasksFormatted | Where-Object {$_.Node -eq $node}
                    if ($platformTasksFormattedByNode) {
            
                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "   ComputerName: " 
                        Write-Host+ -NoTrace -NoTimestamp $node.ToLower() -ForegroundColor Darkgray
                        Write-Host+

                        # write column labels
                        foreach ($key in $formatData.Keys) {
                            $columnWidth = $formatData.$key.Width+1
                            $header = "$($global:consoleSequence.ForegroundDarkGray)$($formatData.$key.Label)$($emptyString.PadLeft($columnWidth-$formatData.$key.Label.Length))$($_defaultColor)"
                            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $header
                        }
                        Write-Host+
            
                        # underline column labels
                        foreach ($key in $formatData.Keys) {
                            $underlineChar = $formatData.$key.Label.Trim().Length -gt 0 ? "-" : " "
                            $columnWidth = $formatData.$key.Width+1
                            $header = "$($global:consoleSequence.ForegroundDarkGray)$($emptyString.PadLeft($formatData.$key.Label.Length,$underlineChar))$($emptyString.PadLeft($columnWidth-$formatData.$key.Label.Length," "))$($_defaultColor)"
                            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $header
                        }

                        $platformTasksFormattedByNode | Format-Table -HideTableHeaders

                    }

                }

                $RefreshPeriodSecondsTotal += $RefreshIntervalSeconds
                if ($RefreshPeriodSecondsTotal -gt $MaxRefreshPeriodSeconds) {
                    Write-Host+ -NoTrace -NoTimestamp "   Maximum refresh period of $MaxRefreshPeriodSeconds seconds has been reached." -ForegroundColor DarkGray
                    Write-Host+
                    $Refresh = $false
                }
                elseif ($Refresh) {
                    Write-Host+ -NoTrace -NoTimestamp "   Refreshed at $((Get-Date -AsUTC).ToString('u'))" -ForegroundColor DarkGray
                    Start-Sleep -Seconds $RefreshIntervalSeconds
                    Write-Host+ -ReverseLineFeed $($platformTasksFormatted.Count + ($ComputerName.Count * 5) + 4)
                    Write-Host+
                    $platformTasks = Get-PlatformTask -ComputerName $ComputerName
                }

            } until (!$Refresh)
        }
        catch {
            throw
        }
        finally {
            Set-CursorVisible
            Remove-PSSession+
        }

    }

}

#endregion TASKS