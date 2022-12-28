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

    if ($Id -and !$TaskName) {$TaskName = $(Get-Product -Id $Id).TaskName}

    # $nodes = Get-PlatformTopology nodes -Online -Keys

    $psSession = Use-PSSession+ -ComputerName $ComputerName
    $tasks = $TaskName ? $(Invoke-Command -Session $psSession {Get-ScheduledTask -TaskName $using:TaskName -ErrorAction SilentlyContinue}) : $(Invoke-Command -Session $psSession {Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -like "*$($using:Overwatch.Name)*"}})
    # Remove-PsSession $psSession
    if (!$tasks) {return}

    if ($ExcludeId) {$tasks = $tasks | Where-Object {$_.TaskName -ne $(Get-Product $ExcludeId).Name}}
    if ($ExcludeTaskName) {$tasks = $tasks | Where-Object {$_.TaskName -ne $ExcludeTaskName}}

    $platformTasks = @()
    $tasks | ForEach-Object {
        $task = $_
        $taskProduct = Get-Product | Where-Object {$_.TaskName -eq $task.TaskName}
        $platformTask = [PlatformCim]@{
            Class = "Task"
            Name = $task.TaskName
            DisplayName = $taskProduct.TaskName
            Instance = $task
            Description = $task.Description
            Required = $true
            Node = $env:COMPUTERNAME
            Status = $($taskState[$task.State])
            StatusOK = $taskStateOK
            IsOK = $taskStateOK -contains $($taskState[$task.State])
            ProductId = $taskProduct.Id
        }
        $platformTask | Add-Member -NotePropertyName ScheduledTaskInfo -NotePropertyValue $(Get-ScheduledTaskInfo -TaskName $task.TaskName)
        $platformTasks += $platformTask
    }

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

    Write-Host+ -Iff (!$Quiet)

    $platformTasks = Get-PlatformTask
    if ($Enabled) {
        $platformTasks = $platformTasks | Where-Object {$_.Status -in $global:PlatformTaskState.Enabled}
    }

    $platformTasks | ForEach-Object {
        $platformTask = Disable-PlatformTask -PlatformTask $_ -OutputType "PlatformTask" -Timeout $Timeout
        $message = "<$($platformTask.ProductID) <.>32> $($platformTask.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($platformTask.Status -in $global:PlatformTaskState.platformTasks ? "Red" : "DarkGreen")
        Write-Log -EntryType Information -Action "Disable-PlatformTasks" -Target $platformTask.ProductID -Status $platformTask.Status -Force
    }

    Write-Host+ -Iff (!$Quiet)

}

function global:Enable-PlatformTask {

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

    Write-Host+ -Iff (!$Quiet)

    $platformTasks = Get-PlatformTask
    if ($Disabled) {
        $platformTasks = $platformTasks | Where-Object {$_.Status -in $global:PlatformTaskState.Disabled}
    }

    $platformTasks | ForEach-Object {
        $platformTask = Enable-PlatformTask -PlatformTask $_ -OutputType "PlatformTask" -Timeout $Timeout
        $message = "<$($platformTask.ProductID) <.>32> $($platformTask.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($platformTask.Status -in $global:PlatformTaskState.Enabled ? "DarkGreen" : "Red")
        Write-Log -EntryType Information -Action "Enable-PlatformTasks" -Target $platformTask.ProductID -Status $platformTask.Status -Force
    }

    Write-Host+ -Iff (!$Quiet)

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
    $PlatformTask.Status = $PlatformTask.Instance.State.ToString()

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

function global:Show-PlatformTaskStatus {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object[]]$PlatformTask,
        [switch]$Disabled
    ) 

    $platformTasks = Get-PlatformTask -Disabled:$Disabled.IsPresent

    Write-Host+ -Iff $($platformTasks.Count -ge 1)

    foreach ($platformTask in $platformTasks) {
        $message = "<$($platformTask.ProductID) <.>32> $($platformTask.Status.ToUpper())"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($platformTask.Status -in $global:PlatformTaskState.Enabled ? "DarkGreen" : "Red")
    }

}

#endregion TASKS