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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
        $isStarted = Start-PlatformTask -TaskName $TaskName -Quiet
        $isStarted | Out-Null
    }

}
Set-Alias -Name taskRegister -Value Register-PlatformTask -Scope Global

function global:Get-PlatformTask { 

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$ExcludeId,
        [Parameter(Mandatory=$false)][string]$TaskName,
        [Parameter(Mandatory=$false)][string]$ExcludeTaskName,
        [Parameter(Mandatory=$false)][string]$View,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    $taskState = @("Unknown","Disabled","Queued","Ready","Running")
    $taskStateOK = @("Queued","Ready","Running")

    if ($Id -and !$TaskName) {$TaskName = $(Get-Product -Id $Id).TaskName}

    # $nodes = Get-PlatformTopology nodes -Online -Keys

    $psSession = Get-PSSession+ -ComputerName $ComputerName
    $tasks = $TaskName ? $(Invoke-Command -Session $psSession {Get-ScheduledTask -TaskName $using:TaskName -ErrorAction SilentlyContinue}) : $(Invoke-Command -Session $psSession {Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -like "*$($using:Overwatch.Name)*"}})
    Remove-PsSession $psSession
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

    $dynamicView = @()
    $dynamicView += $([PlatformCim]@{}).psobject.properties.name
    $dynamicView += "ScheduledTaskInfo"
    return $platformTasks | Select-Object -Property $($View ? $CimView.$($View) : $dynamicView)

}
Set-Alias -Name taskGet -Value Get-PlatformTask -Scope Global

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
Set-Alias -Name taskInterval -Value Get-PlatformTask -Scope Global

function global:Wait-PlatformTask {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName,
        [Parameter(Mandatory=$false)][ValidateSet("Unknown","Disabled","Queued","Ready","Running")][string[]]$State = "Ready",
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Not
    ) 

    $Id = $global:Catalog.Product.$Id.Id
    $State = $State | ForEach-Object {(Get-Culture).TextInfo.ToTitleCase($_)}
    $task = Get-PlatformTask -Id $Id

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $timerInterval = [Diagnostics.Stopwatch]::StartNew()

    while (((!$Not -and $task.Status -notin $State) -or ($Not -and $task.Status -in $State)) -and 
        ([math]::Round($timer.Elapsed.TotalSeconds,0) -lt $Timeout.TotalSeconds)) {
            Start-Sleep -seconds 1
            $task = Get-PlatformTask -TaskName $TaskName
            if ([math]::Round($timerInterval.Elapsed.TotalSeconds,0) -ge 10) {
                $timerInterval.Reset()
                $timerInterval.Start()
            }
        }

    $timerInterval.Stop()
    $timer.Stop()

    return ((!$Not -and $task.Status -in $State) -or ($Not -and $task.Status -notin $State))

}
Set-Alias -Name taskWait -Value Wait-PlatformTask -Scope Global

function global:Stop-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet
    ) 

    Write-Host+ -Iff (!$Quiet)

    $productsWithTask = Get-Product | Where-Object {$_.HasTask}
    foreach ($productWithTask in $productsWithTask) {
        $task = Get-PlatformTask -Id $productWithTask.Id
        $message = "<$($productWithTask.Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
        Write-Log -EntryType "Warning" -Action "Stop-PlatformTasks" -Target $productWithTask.Id -Status $task.Status -Force
    }

    Write-Host+ -Iff (!$Quiet)

}

function global:Disable-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet
    ) 

    Write-Host+ -Iff (!$Quiet)

    $productsWithTask = Get-Product | Where-Object {$_.HasTask}
    foreach ($productWithTask in $productsWithTask) {
        $isDisabled = Disable-PlatformTask -Id $productWithTask.Id -Timeout $Timeout -Quiet
        $isDisabled | Out-Null
        $task = Get-PlatformTask -Id $productWithTask.Id
        $message = "<$($productWithTask.Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
        Write-Log -EntryType "Warning" -Action "Disable-PlatformTasks" -Target $productWithTask.Id -Status $task.Status -Force
    }

    Write-Host+ -Iff (!$Quiet)

}

function global:Disable-PlatformTask {

    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")        

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet,
        [switch]$Force
    ) 

    $Id = $global:Catalog.Product.$Id.Id
    $task = Get-PlatformTask -Id $Id 

    # check if task is disabled
    if ($task.Status -in "Disabled") {
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Red
        return $true
    }

    # check if task is running
    if ($task.Status -in "Running","Queued") {
        if ($Force) {
            $isStopped = Stop-PlatformTask -Id $Id -Quiet
            $isStopped | Out-Null
            $task = Get-PlatformTask -Id $Id 
        }
        else {
            $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
            Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
            return $false
        }
    }

    $task = Disable-ScheduledTask -TaskName $TaskName 

    # wait for task to be disabled
    $isTargetState = Wait-PlatformTask -Id $Id -TaskName $TaskName -State "Disabled" -Timeout $Timeout

    if (!$Quiet) {
        $task = Get-PlatformTask -Id $Id
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
    }

    return $isTargetState

}
Set-Alias -Name taskDisable -Value Disable-PlatformTask -Scope Global

function global:Enable-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet
    ) 

    Write-Host+ -Iff (!$Quiet)

    $productsWithTask = Get-Product | Where-Object {$_.HasTask}
    foreach ($productWithTask in $productsWithTask) {
        $isEnabled = Enable-PlatformTask -Id $productWithTask.Id -Timeout $Timeout -Quiet
        $isEnabled | Out-Null
        $task = Get-PlatformTask -Id $productWithTask.Id
        $message = "<$($productWithTask.Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
        Write-Log -EntryType "Information" -Action "Enable-PlatformTasks" -Target $productWithTask.Id -Status $task.Status -Force
    }

    Write-Host+ -Iff (!$Quiet)

}
Set-Alias -Name Start-PlatformTasks -Value Enable-PlatformTasks -Scope Global

function global:Enable-PlatformTask {

    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet
    )

    $Id = $global:Catalog.Product.$Id.Id
    $task = Get-PlatformTask -Id $Id 

    # check if task is disabled
    if ($task.Status -notin "Disabled") {
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        return $true
    }

    # enable task
    $task = Enable-ScheduledTask -TaskName $TaskName

    # wait for task to be enabled
    $isTargetState = Wait-PlatformTask -Id $Id -TaskName $TaskName -State "Ready" -Timeout $Timeout

    if (!$Quiet) {
        $task = Get-PlatformTask -Id $Id
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
    }

    return $isTargetState

}
Set-Alias -Name taskEnable -Value Enable-PlatformTask -Scope Global

function global:Start-PlatformTask {
    
    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet,
        [switch]$Force
    ) 

    $Id = $global:Catalog.Product.$Id.Id
    $task = Get-PlatformTask -Id $Id 
    Write-Verbose "$($Id) $($task.Status)"

    # check if task is disabled
    if ($task.Status -in "Disabled") {
        if ($Force) {
            $isEnabled = Enable-PlatformTask -Id $Id -Quiet
            $isEnabled | Out-Null
            $task = Get-PlatformTask -Id $Id 
        }
        else {
            $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
            Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Red
            return $false
        }
    }

    # check if task is already running
    if ($task.Status -in "Running","Queued") {
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        return $true
    }

    # start task
    Start-ScheduledTask -TaskName $TaskName

    # wait for task to start running
    $isTargetState = Wait-PlatformTask -Id $Id -TaskName $TaskName -State "Running" -Timeout $Timeout

    if (!$Quiet) {
        $task = Get-PlatformTask -Id $Id
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
    }

    return $isTargetState

}
Set-Alias -Name taskStart -Value Start-PlatformTask -Scope Global

function global:Stop-PlatformTask {

    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName,
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60),
        [switch]$Quiet
    ) 

    $Id = $global:Catalog.Product.$Id.Id
    $task = Get-PlatformTask -Id $Id 

    # check if task is already stopped
    if ($task.Status -notin "Ready","Running","Queued") {
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        return $true
    }

    # stop task
    Stop-ScheduledTask -TaskName $TaskName

    # wait for task to stop running
    $isTargetState = Wait-PlatformTask -Id $Id -TaskName $TaskName -State "Running" -Not -Timeout $Timeout

    if (!$Quiet) {
        $task = Get-PlatformTask -Id $Id
        $message = "<$($Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -notin "Ready","Running","Queued" ? "Red" : "DarkGreen")
    }

    return $isTargetState

}
Set-Alias -Name taskStop -Value Stop-PlatformTask -Scope Global

function global:Suspend-PlatformTask {

    # Suspend = Stop and Disable
    # Valid task states are ("Unknown","Disabled","Queued","Ready","Running")
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Quiet
    ) 

    $task = Get-PlatformTask -Id $Id
    
    # stop task if running
    $isStopped = !($task.Status -in "Queued","Running")
    if (!$isStopped) {$isStopped = Stop-PlatformTask -Id $Id -Quiet:$Quiet.IsPresent}

    $isDisabled = $false
    if ($isStopped) {
        $isDisabled = Disable-PlatformTask -Id $Id
        $task = Get-PlatformTask -Id $Id
        if (!$isDisabled) {
            Write-Host+ -NoTrace "$($Id) $($task.Status)" -ForegroundColor DarkYellow
            Write-Log -Context $Id -Action "Disable" -EntryType "Warning" -Status $task.Status
        } else {
            Write-Log -Context $Id -Action "Disable" -EntryType "Information" -Status $task.Status
            Send-TaskMessage -Id $Id -Status "Disabled"
        }
    } else {
        Write-Host+ -NoTrace "$($Id) $($task.Status)"
        Write-Log -Context $Id -Action "Stop" -EntryType "Warning" -Status "Failure" -Message "$($Id) $($task.Status)"
    }

    return $isStopped -and $isDisabled
    
}
Set-Alias -Name taskSuspend -Value Suspend-PlatformTask -Scope Global

function global:Resume-PlatformTask {

    # Resume = Disabled
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [switch]$Quiet
    ) 

    $task = Get-PlatformTask -Id $Id

    $isEnabled = Enable-PlatformTask -Id $Id -Quiet:$Quiet.IsPresent
    if (!$isEnabled) {
        Write-Host+ -NoTrace "$($Id) $($task.Status)"
        Write-Log -Context $Id -Action "Enable" -EntryType "Warning" -Status $task.Status
        Send-TaskMessage -Id $Id -Status "Disabled" -MessageType $PlatformMessageType.Alert
    } else {
        Write-Log -Context $Id -Action "Enable" -EntryType "Information" -Status $task.Status
        Send-TaskMessage -Id $Id -Status "Enabled"
    }

    return $isEnabled
    
}
Set-Alias -Name taskResume -Value Resume-PlatformTask -Scope Global

function global:Unregister-PlatformTask {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$TaskName = (Get-Product -Id $Id).TaskName
    ) 

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

    return

}
Set-Alias -Name taskUnRegister -Value Unregister-PlatformTask -Scope Global

function global:Show-PlatformTasks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][timespan]$Timeout = (New-TimeSpan -Seconds 60)
    ) 

    Write-Host+

    $productsWithTask = Get-Product | Where-Object {$_.HasTask}
    foreach ($productWithTask in $productsWithTask) {
        $task = Get-PlatformTask -Id $productWithTask.Id
        $message = "<$($productWithTask.Id) <.>32> $($task.Status.ToUpper())"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($task.Status -in ("Ready","Running") ? "DarkGreen" : "Red")
    }

    Write-Host+

}

#endregion TASKS