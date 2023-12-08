#region PLATFORMINFO

function global:Get-PlatformInfo {

    [CmdletBinding()]
    param (
        [switch][Alias("Update")]$ResetCache
    )

    if ($(Get-Cache platforminfo).Exists -and !$ResetCache) {
        $platformInfo = Read-Cache platforminfo
        if ($platformInfo) {
            $global:Platform.Version = $platformInfo.Version
            $global:Platform.Build = $platformInfo.Build
            return
        }
    }
    
    $global:Platform.Version = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.Version
    $global:Platform.Build = Invoke-Command $global:Catalog.Platform.AlteryxDesigner.Installation.Build

    Write-Cache platforminfo -InputObject @{Version=$global:Platform.Version;Build=$global:Platform.Build}

    return

}

#endregion PLATFORMINFO
#region PROCESS

function global:Get-PlatformProcess {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$View,
        [switch]$ResetCache
    )

    $platformTopology = Get-PlatformTopology -Online
    if ([string]::IsNullOrEmpty($ComputerName)) {
        $ComputerName = $platformTopology.nodes.Keys
    }

    # if (!$ResetCache) {
    #     if ((Get-Cache platformprocesses).Exists) {
    #         Write-Host+ -IfDebug "Read-Cache platformprocesses" -ForegroundColor DarkYellow
    #         $platformProcesses = Read-Cache platformprocesses -MaxAge (New-TimeSpan -Seconds 10)
    #         if ($platformProcesses) {
    #             return $platformProcesses | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)
    #         }
    #     }
    # }

    Write-Host+ -IfVerbose "Get processes from node[s]: RUNNING ..."  -ForegroundColor DarkYellow
    $cimSession = New-CimSession -ComputerName $ComputerName
    $processes = Get-CimInstance -ClassName Win32_Process -CimSession $cimSession -Property * |
        Where-Object {$_.Name.Replace(".exe","") -in $PlatformProcessConfig.Name} 
    Remove-CimSession $cimSession
    
    Write-Host+ -IfVerbose "Get processes from node[s]: COMPLETED" -ForegroundColor DarkYellow
    
    $platformProcesses = $null
    $platformProcesses += @(
        $processes | ForEach-Object {
            $process = $_
            $parent = $processes | Where-Object {$_.ProcessId -eq $process.ParentProcessId -and $_.PSComputerName -eq $process.PSComputerName}
            "noop" | out-null
            $PlatformProcessConfig | ForEach-Object {
                if ($process.Name.Replace(".exe","") -eq $_.Name) {
                    $orphaned = !$parent -and $null -ne $_.ParentName -and "" -notin $_.ParentName
                    [PlatformCim]@{
                        Class = $_.Class
                        Id = $process.ProcessId
                        Name = $_.Name
                        DisplayName = $_.DisplayName
                        StatusOK = $_.StatusOK
                        Required = $_.Required
                        Transient = $_.Transient
                        Status = $orphaned ? "Orphaned" : "Active"
                        IsOK = !$orphaned # -and ...
                        Instance = $process
                        Node = $process.PSComputerName 
                        ParentName = $parent ? $parent.Name.Replace(".exe","") : $null
                        ParentId = $process.ParentProcessId
                        ParentInstance = $parent
                        Component = $platformTopology.Nodes[$process.PSComputerName].Components.Keys
                    }
                }
            }
        }
    
        foreach ($node in $ComputerName) {
            $PlatformProcessConfig | Where-Object { $_.Name -notin $processes.Name -and $_.Required -and $platformTopology.Nodes.$node.Components -contains $_.Component} | ForEach-Object {
                [PlatformCim]@{
                    Class = $_.Class
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    StatusOK = $null
                    Required = $_.Required
                    Transient = $_.Transient
                    Status = $_.Required ? $($_.Transient ? "Inactive" : "NOT Responding") : "Inactive"
                    IsOK = $_.Required ? $($_.Transient ? $true : $false) : $true
                    Instance = $null
                    Node = $node 
                    ParentName = $_.ParentName
                    ParentInstance = $null
                    Component = $_.Component
                }
            }
        } 
    )

    # $platformProcesses | Write-Cache platformprocesses

    return $platformProcesses | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)

}

#endregion PROCESS
#region SERVICE

function global:Get-PlatformServices {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$View
    )

    $platformTopology = Get-PlatformTopology -Online
    if ([string]::IsNullOrEmpty($ComputerName)) {
        $ComputerName = $platformTopology.nodes.Keys
    }

    $cimSession = @()
    foreach ($node in $ComputerName) {
        $owt = Get-OverwatchTopology nodes.$node
        $creds = Get-Credentials "localadmin-$($owt.Environ)" -ComputerName $owt.Controller -LocalMachine
        $cimSession += New-CimSession -ComputerName $node -Credential $creds -Authentication CredSsp -ErrorAction SilentlyContinue
    }

    $services = Get-CimInstance -ClassName Win32_Service -CimSession $cimSession -Property * |
        Where-Object {$_.Name -eq $PlatformServiceConfig.Name} 

    Remove-CimSession $cimSession

    $PlatformServices = @(
        $services | ForEach-Object {
            $service = $_
            $PlatformServiceConfig | ForEach-Object {
                if ($service.Name -eq $_.Name) {
                    [PlatformCim]@{
                        Class = $_.Class
                        Name = $_.Name
                        DisplayName = $_.DisplayName
                        StatusOK = $_.StatusOK
                        Required = $_.Required
                        Transient = $_.Transient
                        Status = $service.State
                        IsOK = ($_.StatusOK -contains $service.State) 
                        Instance = $service
                        Node = $service.PSComputerName.ToLower() 
                        Component = $platformTopology.Nodes[$service.PSComputerName].Components.Keys
                    }
                }
            }
        }

        # $PlatformServiceConfig | Where-Object { $_.Name -notin $services.Name -and $_.Required} | ForEach-Object {
        #     [PlatformCim]@{
        #         Class = $_.Class
        #         Name = $_.Name
        #         DisplayName = $_.DisplayName
        #         StatusOK = $_.StatusOK
        #         Required = $_.Required
        #         Transient = $_.Transient
        #         Status = $_.Required ? $($_.Transient ? "Inactive" : "NOT Responding") : "Inactive"
        #         IsOK = $_.Required ? $($_.Transient ? $true : $false) : $true
        #         Instance = $null
        #         Node = $service.PSComputerName.ToLower() 
        #     }
        # }
    )

    return $PlatformServices | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)
}

#endregion SERVICE
#region STATUS

function global:Show-PlatformStatus {

    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues
    )

    if (!$Summary -and !$All -and !$Required -and !$Issues) { $Required = $true; $Issues = $true }

    $platformStatus = Get-PlatformStatus -Reset -Quiet
    $_platformStatusRollupStatus = 
        switch ($platformStatus.RollupStatus) {
            "Inactive" {
                switch ($platformStatus.RollupStatus) {
                    "Inactive" {
                        $platformStatus.RollupStatus + ($platformStatus.IsOK ? " (IsOK)" : " (IsNotOK)")
                    }
                    default {
                        $platformStatus.RollupStatus
                    }
                }
            }
            default {
                $platformStatus.RollupStatus
            }
        }
    # if ((![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
    #     $_platformStatusRollupStatus = switch ($platformStatus.Event) {
    #         "Start" { "Starting" }
    #         "Stop"  { "Stopping" }
    #     }
    # }

    Write-Host+
    $message = "<$($global:Platform.Instance) Status <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    #region STATUS    
    
        Write-Host+

        # # check platform status and for any active events
        # $platformStatus = Get-PlatformStatus -ResetCache -Quiet

        $alteryxDesignerStatus = Get-AlteryxDesignerStatus
        # $nodeStatusHashTable = (Get-AlteryxDesignerStatus).Nodes

        $nodeStatus = @()
        foreach ($node in (Get-PlatformTopology nodes -keys)) {
            $nodeStatus += [PsCustomObject]@{
                Role = pt nodes.$node.components -k
                Alias = ptBuildAlias $node
                Node = $node
                IsOK = $alteryxDesignerStatus.Nodes[$node].IsOK
                Status = 
                    switch ($alteryxDesignerStatus.Nodes[$node].Status) {
                        "Inactive" {
                            $alteryxDesignerStatus.Nodes[$node].Status + ($alteryxDesignerStatus.Nodes[$node].IsOK ? " (IsOK)" : " (IsNotOK)")
                        }
                        default {
                            $alteryxDesignerStatus.Nodes[$node].Status
                        }
                    }
            }
        }

        $nodeStatus = $nodeStatus | Sort-Object -Property Role, Node
        
        foreach ($_nodeStatus in $nodeStatus) {
            $message = "<  $($_nodeStatus.Role) ($($_nodeStatus.Node)) <.>38> $($_nodeStatus.Status)"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($_nodeStatus.Status)
        }
        # $nodeStatus | Sort-Object -Property Node | Format-Table -Property Node, Alias, Status

    #endregion STATUS      
    #region EVENTS            

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  Event < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.Event -ForegroundColor DarkGray, $global:PlatformEventColor.($platformStatus.Event)
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  EventStatus < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.EventStatus -ForegroundColor DarkGray, $global:PlatformEventStatusColor.($platformStatus.EventStatus)
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  EventCreatedBy < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.EventCreatedBy -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  EventCreatedAt < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.EventCreatedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  EventUpdatedAt < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.EventUpdatedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  EventCompletedAt < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.EventCompletedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse "<  EventHasCompleted < >$($maxLength+4)> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp ":", $platformStatus.EventHasCompleted -ForegroundColor DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"
        }

    #endregion EVENTS     
    #region ISSUES           

        if ($global:WriteHostPlusPreference -eq "Continue") {
            $platformIssues = $platformStatus.platformIssues
            if ($Issues -and $platformIssues) {
                $platformIssues | Format-Table -Property Node, Class, Name, Status, Component
            }
        }
        
    #endregion ISSUES
    #region SERVICES         

        if ($global:WriteHostPlusPreference -eq "Continue") {
            if ($All -or ($Issues -and $platformIssues)) {
                $_components = Get-PlatformCimInstance | Where-Object {$_.Class -in ("Service","Process")}
                if ($Required) { $_components = $_components | Where-Object {$_.Required} }
                if ($Issues) { $_components = $_components | Where-Object {!$_.IsOK} }
                $_components | Sort-Object -Property Node, Name | Format-Table -GroupBy Node -Property Node, @{Name='Alias';Expression={ptBuildAlias $_.Node}}, Class, Name, Status, Required, Transient, IsOK, Component
            }
        }

    #endregion SERVICES   
    
    Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)
    
    $message = "<$($global:Platform.Instance) Status <.>48> $($_platformStatusRollupStatus.ToUpper())"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($_platformStatusRollupStatus)    

}
Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global

function global:Get-AlteryxDesignerStatus {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][ValidateSet("Designer")][string]$Component
    )

    if ([string]::IsNullOrEmpty($ComputerName)) {
        $ComputerName = Get-PlatformTopology nodes -Keys -Online
    }

    $platformTopology = Get-PlatformTopology

    if (![string]::IsNullOrEmpty($Component)) {
        $Component = (Get-Culture).TextInfo.ToTitleCase($Component)
        $ComputerName = $platformTopology.Components.$component.Nodes
    }

    $processIsOK = $true
    $processStatus = @()
    $processNodes = @{}

    $platformCimInstance = Get-PlatformProcess -ComputerName $ComputerName

    $designerProcess = $platformCimInstance | Where-Object {$platformTopology.Components.Designer.Nodes.Keys -contains $_.Node}
    if ($designerProcess) {
        $designerProcessStatus = @{}
        $designerProcessStatus += @{ Status = ([array]($designerProcess.Status | Sort-Object -Unique))[0] }
        $designerProcessStatus += @{ IsOK = ([array]($designerProcess.IsOK | Sort-Object -Unique -Descending))[0] }
        $designerProcessNodes = @{}
        foreach ($process in $designerProcess) {
            if (!$designerProcessNodes.$($process.Node)) {
                $designerProcessNodes += @{$($process.Node) = $process.Status }
            }
            if (!$processNodes.$($process.Node)) {
                $processNodes += @{
                    $($process.Node) = @{
                        IsOK = $process.IsOK
                        Status = $process.Status
                    }
                }
            }
        }
        $designerProcessStatus += @{Nodes = $designerProcessNodes}
    }
    else {
        $designerProcessStatus = @{}
        $designerProcessStatus += @{ Status = "Inactive" }
        $designerProcessStatus += @{ IsOK = $true }
        $designerProcessStatus += @{ Nodes = $ComputerName }     
        if (!$processNodes.$ComputerName) {
            $processNodes += @{ 
                $($ComputerName) = @{
                    IsOK = $true
                    Status = "Inactive" 
                }
            }
        } 
    }

    $processStatus += $designerProcessStatus.Status
    if ($processStatus.Count -gt 1) {
        $processStatus = ([array]($processStatus | Sort-Object -Unique -Descending))[0]
    }
    $processIsOK = $processIsOK -and $designerProcessStatus.IsOK

    $AlteryxDesignerStatus = @{
        IsOK = $processIsOK
        Status = $processStatus
        Nodes = $processNodes
    }

    if (![string]::IsNullOrEmpty($Component)) {$AlteryxDesignerStatus += @{Component = $Component}}

    if ($designerProcess) {$AlteryxDesignerStatus += @{Designer = $designerProcessStatus}}

    return $AlteryxDesignerStatus
}

function global:Get-PlatformStatusRollup {
    
    [CmdletBinding()]
    param (
        [switch]$ResetCache,
        [switch]$Quiet
    )

    $AlteryxDesignerStatus = Get-AlteryxDesignerStatus
    
    $platformCimInstance = Get-PlatformCimInstance
    $issues = $platformCimInstance | Where-Object {$_.Required -and $_.Class -in ("Service","Process") -and !$_.IsOK} | 
        Select-Object -Property Node, Class, Name, Status, @{Name="Component";Expression={$_.Component -join ", "}}, ParentName
    
    return $AlteryxDesignerStatus.IsOK, $AlteryxDesignerStatus.Status, $issues

}

function global:Build-StatusFacts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$true)][string]$Node,
        [switch]$ShowAll
    )

    $platformTopology = Get-PlatformTopology

    $facts = @(
        $platformStatus.ByCimInstance | Where-Object {$_.Node -eq $Node -and $_.Class -in 'Service'} | ForEach-Object {
            if (!$_.IsOK -or $ShowAll) {
                foreach ($component in $platformTopology.Nodes.$node.Components.Keys) {
                    @{
                        name = $component
                        value = "**$($_.Status.ToUpper())**"
                    }
                }
            }
        }  
        $platformStatus.ByCimInstance | Where-Object {$_.Node -eq $Node -and $_.Class -in 'Process'} | ForEach-Object {
            if (!$_.IsOK -or $ShowAll) {
                @{
                    name  = "$($_.DisplayName)"
                    value = $_.IsOK ?  "$($_.Status)" : "**$($_.Status.ToUpper())**"
                }
            }
        }  
    ) 

    return $facts
}    

#endregion STATUS
#region RUNTIMESETTINGS

function global:Get-RuntimeSettings {

    [CmdletBinding()] 
    param(
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Path = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
    )

    $runtimeSettingsFile = ([FileObject]::new($Path, $ComputerName))
    if ($runtimeSettingsFile.Exists) {
        return [xml]$(Get-Content -Path $runtimeSettingsFile.Path)
    }

}

#endregion RUNTIMESETTINGS
#region ALTERYXSERVICE

    function global:Invoke-AlteryxService {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$p0,
            [Parameter(Mandatory=$false,Position=1)][string]$p1,
            [Parameter(Mandatory=$false,Position=2)][string]$p2,
            [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
            [switch]$Log
        )

        #$hasValue = $false
        if ($p0 -match "=") {
            #$hasValue = $true
            $kv = $p0 -split "="
            $p0 = $kv[0]
            $p1 = "="
            $p2 = $kv[1]
        }
        
        $hasResult = switch ($p0) {
            "getversion" {$true}
            "verifysettingfile" {$true}
            default {$false}
        }

        $p2IsFile = switch ($p0) {
            "emongodump" {$true}
            "verifysettingfile" {$true}
            default {$false}
        }

        $status = "Success"
        $entryType = "Information"
        $_exception = $null

        foreach ($node in $ComputerName) {
            Write-Host+ -IfVerbose "$($node.ToUpper()): alteryxservice $($p0) $($p1) $($p2)" -ForegroundColor DarkYellow
        }

        try {
            # note:  $p0$p1$p2 is correct!  no spaces
            $psSession = Use-PSSession+ -ComputerName $ComputerName
            if ($hasResult) {
                $result = Invoke-Command -Session $psSession {& alteryxservice $using:p0$using:p1$using:p2}
                $result = switch ($p0) {
                    "getversion" {[regex]::Match($result,$global:RegexPattern.Software.Version).Groups[1].Value}
                    "verifysettingfile" {$($result -split "`r")[1] -match "success" ? "Success" : "Failure"}
                    default {$null}
                }
            }
            else {
                Invoke-Command -Session $psSession {& alteryxservice $using:p0$using:p1$using:p2}  | Out-Null
            }
        }
        catch {
            $entryType = "Error"
            $_exception = $_.Exception
            $status = "Error"
            $Log = $true
        }
        # finally {
        #     Remove-PSSession $psSession
        # }

        if ($hasResult) {Write-Host+ -IfVerbose "Result = $($result)" -ForegroundColor DarkYellow}

        $HashArguments = @{
            Action = $p2Isfile ? $("alteryxservice $($p0)".Trim()) : $("alteryxservice $($p0) $($p1)".Trim())
            EntryType = $entryType
            Exception = $_exception
            Status = $status
            Target = $p2Isfile ? $p2 : $null
        }

        if ($Log) {Write-Log @HashArguments}

        return $hasResult ? $result : $null

    }  

#endregion ALTERYXSERVICE
#region ALTERYXENGINECMD

function global:Invoke-AlteryxEngineCmd {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,ParameterSetName="Workflow")][string]$Workflow,
        [Parameter(Mandatory=$false,ParameterSetName="AnalyticApp")][string]$AnalyticApp,
        [Parameter(Mandatory=$true,ParameterSetName="AnalyticApp")][string]$AnalyticAppValues
    )

    $alteryxenginecmd = Invoke-Command $global:Catalog.Platform.$($global:Platform.Id).Installation.AlteryxEngineCmd

    if ($Workflow) {
        $result = Invoke-Command {& $alteryxenginecmd $Workflow}
    }
    elseif ($AnalyticAppValues) {
        if ($AnalyticApp) {
            $result = Invoke-Command {& $alteryxenginecmd $AnalyticApp $AnalyticAppValues}
        }
        else {
            $result = Invoke-Command {& $alteryxenginecmd $AnalyticAppValues}
        }
    }

    return $result

}  

#endregion ALTERYXENGINECMD
#region PLATFORM JOBS

    function global:Get-PlatformJob {

        [CmdletBinding(DefaultParameterSetName="ByComputerName")]
        param (
            [Parameter(Mandatory=$false,ParameterSetName="ByComputerName")]
            [string[]]$ComputerName,

            [Parameter(Mandatory=$true,ParameterSetName="ById")]
            [string[]]$Id, # format: <ComputerName>:<Id>
            
            [Parameter(Mandatory=$false,ParameterSetName="ByComputerName")]
            [Parameter(Mandatory=$false,ParameterSetName="ById")]
            [switch]$Orphaned
        ) 

        if (!$ComputerName -and !$Id) { 
            $ComputerName = Get-PlatformTopology components.designer.nodes -Online -Keys
        }

        $jobs = Get-PlatformProcess -ComputerName $ComputerName | 
            Where-Object {$_.DisplayName -eq $PlatformDictionary.AlteryxEngineCmd -and $_.Status -eq "Active"}        
                
        if (!$ComputerName -and $Id) {
            $_jobs = @()
            foreach ($job in $jobs) {
                if ("$($job.Node):$($job.Id)" -in $Id) {
                    $_jobs += $job
                }
            }
            $jobs = $_jobs
        }

        if ($Orphaned) {
            $jobs = $jobs | Where-Object {$_.status -eq "Orphaned"}
        }

        return $jobs

    }
    Set-Alias -Name jobsGet -Value Get-PlatformJob -Scope Global

    function global:Watch-PlatformJob {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName = (Get-PlatformTopology components.designer.nodes -Online -Keys),
            [Parameter(Mandatory=$false)][int32]$Seconds = 15
        ) 

        # $platformTopology = Get-PlatformTopology -Online
        # if ([string]::IsNullOrEmpty($ComputerName)) {
        #     $ComputerName = $platformTopology.nodes.Keys
        # }

        $timer = [Diagnostics.Stopwatch]::StartNew()

        $jobs = Get-PlatformJob -ComputerName $ComputerName  
        
        do {

            if ($jobs) {
                foreach ($job in $jobs) {
                    Write-Host+ -NoTrace  "Jobs are running on $($job.Node)"
                }
            }
            else {
                Write-Host+ -NoTrace  "*NO* jobs are running"
            }

            Start-Sleep -seconds $Seconds

            $jobs = Get-PlatformJob -ComputerName $ComputerName  

        } until (($jobs.Count -eq 0) -or ([math]::Round($timer.Elapsed.TotalSeconds,0) -gt $PlatformComponentTimeout))

        $timer.Stop()

        if ($jobs) {
            Write-Host+ -NoTrace "Timeout"
        }
        else {
            Write-Host+ -NoTrace "*NO* jobs are running"
        }

        return 

    }
    Set-Alias -Name jobsWatch -Value Watch-PlatformJob -Scope Global

    function global:Stop-PlatformJob {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string[]]$ComputerName,
            [Parameter(Mandatory=$false)][string[]]$Id # format: <ComputerName>:<Id>
        ) 

        function Stop-ProcessTree {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true)][string]$ComputerName,
                [Parameter(Mandatory=$true)][int]$ProcessId
            )
            
            Get-CimInstance -ClassName Win32_Process -Computername $ComputerName | 
                Where-Object { $_.ParentProcessId -eq $ProcessId } | 
                    ForEach-Object { 
                        Stop-ProcessTree -Computername $ComputerName -ProcessId $_.ProcessId
                    }

            $psSession = Use-PSSession+ -ComputerName $ComputerName
            Invoke-Command -Session $psSession {Stop-Process -Id $using:ProcessId -Force | Wait-Process -Timeout 30} 
            # Remove-PSSession $psSession
        }

        if (!$ComputerName -and !$Id) { $ComputerName = Get-PlatformTopology components.designer.nodes -Online -Keys }

        if ($ComputerName -and !$Id) { $jobs = Get-PlatformJob -ComputerName $ComputerName }
        if (!$ComputerName -and $Id) { $jobs = Get-PlatformJob -Id $Id }
        foreach ($job in $jobs) {
            Stop-ProcessTree -ComputerName $job.Node -ProcessId $job.Instance.Id
            $message = "$($PlatformDictionary.AlteryxEngineCmd) ($($job.Id)) was terminated with force on node '$($job.Node)'"
            Write-Host+ -NoTrace  $message -ForegroundColor DarkGray
            Write-Log -Action $Command -Status $services.Status -EntryType Error -Message $message
        } 

        if ($ComputerName -and !$Id) { $jobs = Get-PlatformJob -ComputerName $ComputerName }
        if (!$ComputerName -and $Id) { $jobs = Get-PlatformJob -Id $Id }
        foreach ($job in $jobs) {
            $message = "$($PlatformDictionary.AlteryxEngineCmd) ($($job.Id)) is still running on node '$($job.Node)'"
            Write-Host+ -NoTrace  $message -ForegroundColor DarkRed
            Write-Log -Action $Command -Status $services.Status -EntryType Error -Message $message
        } 
        if ($jobs.Count -gt 0) {
            Write-Host+ -NoTrace "Unable to stop $($jobs.Count) job$($jobs.Count -le 1 ? '' : 's')" -ForegroundColor DarkRed
        }

        return 

    }

    function global:Update-PlatformJob {

        [CmdletBinding()]
        param()

        # find/kill orphaned AlteryxEngine processes
        $orphanedJobs = Get-PlatformJob -Orphaned
        foreach ($orphanedJob in $orphanedJobs) {
            Stop-PlatformJob -Id "$($orphanedJob.Node):$($orphanedJob.Id)"
        }

        return

    }

#endregion PLATFORM JOBS
#region START/STOP

function global:Start-Platform {

    [CmdletBinding()] param (
        [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id ?? "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start platform"
    )

}
function global:Stop-Platform {

    [CmdletBinding()] param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop platform"
    )
    
}

function global:Restart-Platform {

    [CmdletBinding()] param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Restart platform"
    )

}

#endregion START/STOP
#region BACKUP

    function global:Backup-Platform {

        [CmdletBinding()] param()

    }
    Set-Alias -Name backup -Value Backup-Platform -Scope Global

#endregion BACKUP
#region CLEANUP

    function global:Cleanup-Platform {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

        [CmdletBinding()] param(
            # [Parameter(Mandatory=$false)][Alias("a")][switch]$All = $global:Cleanup.All,
            # [Parameter(Mandatory=$false)][Alias("b")][switch]$BackupFiles = $global:Cleanup.BackupFiles,
            # [Parameter(Mandatory=$false)][Alias("backup-files-retention")][int]$BackupFilesRetention = $global:Cleanup.BackupFilesRetention,
            [Parameter(Mandatory=$false)][Alias("l")][switch]$LogFiles = $global:Cleanup.LogFiles,
            [Parameter(Mandatory=$false)][Alias("log-files-retention")][int]$LogFilesRetention = $global:Cleanup.LogFilesRetention
        )

        function Get-RetentionPeriod {

            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Retention
            )

            $regexMatches = [regex]::Match($Retention,$global:RegexPattern.Cleanup.Retention,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            $_retentionParams = @{
                Keep = $regexMatches.Groups["count"].Value
            }
            if (![string]::IsNullOrEmpty($regexMatches.Groups["unit"].Value)) {
                switch ($regexMatches.Groups["unit"].Value) {
                    "D" { $_retentionParams += @{ Days = $true }}
                    "H" { $_retentionParams += @{ Hours = $true }}
                }
            }

            return $_retentionParams
        
        }

        Write-Host+
        $message = "<Cleanup <.>60> PENDING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        # Write-Host+

        Write-Log -Context "Product.Cleanup" -Action "Cleanup" -Status "Running" -Force
        $result = Send-TaskMessage -Id "Cleanup" -Status "Running"
        $result | Out-Null

        $platformTopology = Get-PlatformTopology
        # $ComputerName = $Force ? $ComputerName : $ComputerName | Where-Object {!$platformTopology[$ComputerName].Offline}

        # $cleanupSuccess = $true

        # try{

            foreach ($node in ($platformTopology.Nodes.Keys)) {

                Write-Host+
                $message = "  $node"
                Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkBlue
                $message = "  $($emptyString.PadLeft($node.Length,"-"))"
                Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkBlue

                [xml]$runtimeSettings = Get-RunTimeSettings -ComputerName $node

                # $controllerLogFilePath = Split-Path $runtimeSettings.SystemSettings.Controller.LoggingPath -Parent
                $engineDefaultTempFilePath = $runtimeSettings.SystemSettings.Engine.DefaultTempFilePath
                $enginePackageStagingPath = $runtimeSettings.SystemSettings.Engine.PackageStagingPath
                $engineLogFilePath = $runtimeSettings.SystemSettings.Engine.LogFilePath

                # # AlteryxService: Log Files
                # if ($global:Cleanup.AlteryxService.LogFiles -and $controllerLogFilePath -and (Test-Path+ -Path $controllerLogFilePath -ComputerName $node)) {

                #     $message = "<    AlteryxService Log Files <.>48> PENDING"
                #     Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                #     $controllerLogFileName = Split-Path $runtimeSettings.SystemSettings.Controller.LoggingPath -LeafBase
                #     $controllerLogFileExtension= Split-Path $runtimeSettings.SystemSettings.Controller.LoggingPath -Extension

                #     $params = @{}
                #     $params += @{
                #         ComputerName = $node
                #         Path = $controllerLogFilePath
                #         Filter = "$($controllerLogFileName)*$($controllerLogFileExtension)"
                #     }
                #     $params += Get-RetentionPeriod ($global:Cleanup.AlteryxService.LogFiles.Retention ?? $global:Cleanup.Default.Retention)
                #     Remove-Files @params

                #     Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

                # }

                # Engine: Default Temporary Directory
                if ($global:Cleanup.Engine.TempFiles -and $engineDefaultTempFilePath -and (Test-Path+ -Path $engineDefaultTempFilePath -ComputerName $node)) {

                    $message = "<    Engine Temp Directories <.>48> PENDING"
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                    foreach ($engineDefaultTempFilePathFilter in $global:Cleanup.Engine.TempFiles.Filter) {

                        $params = @{}
                        $params += @{
                            ComputerName = $node
                            Path = $engineDefaultTempFilePath
                            Filter = $engineDefaultTempFilePathFilter
                        }
                        $params += Get-RetentionPeriod ($global:Cleanup.Engine.TempFiles.Retention ?? $global:Cleanup.Default.Retention)
                        Remove-Files @params

                    }

                    Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen
                    
                }

                # Engine: Log Files
                if ($global:Cleanup.Engine.LogFiles -and $engineLogFilePath -and (Test-Path+ -Path $engineLogFilePath -ComputerName $node)) {

                    $message = "<    Engine Log Files <.>48> PENDING"
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                    foreach ($engineLogFilePathFilter in $global:Cleanup.Engine.LogFiles.Filter) {

                        $params = @{}
                        $params += @{
                            ComputerName = $node
                            Path = $engineLogFilePath
                            Filter = $engineLogFilePathFilter
                        }
                        $params += Get-RetentionPeriod ($global:Cleanup.Engine.LogFiles.Retention ?? $global:Cleanup.Default.Retention)
                        Remove-Files @params
                    }

                    Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen
                    
                }

                # Engine: Staging Files
                if ($global:Cleanup.Engine.StagingFiles -and $enginePackageStagingPath -and (Test-Path+ -Path $enginePackageStagingPath -ComputerName $node)) {

                    $message = "<    Engine Staging Files <.>48> PENDING"
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                    foreach ($enginePackageStagingPathFilter in $global:Cleanup.Engine.StagingFiles.Filter) {

                        $params = @{}
                        $params += @{
                            ComputerName = $node
                            Path = $enginePackageStagingPath
                            Filter = $enginePackageStagingPathFilter
                        }
                        $params += Get-RetentionPeriod ($global:Cleanup.Engine.StagingFiles.Retention ?? $global:Cleanup.Default.Retention)
                        Remove-Files @params

                    }

                    Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen
                    
                }        

            }
    
        Write-Host+
        $message = "<Cleanup <.>60> SUCCESS"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        Write-Host+
    
        # Write-Log -Context "Product.Cleanup" -Action "Cleanup" -Status $status -EntryType $entryType -Force
        $result = Send-TaskMessage -Id "Cleanup" -Status "Completed" -Message $($status -eq "SUCCESS" ? "" : "See log files for details.")
        $result | Out-Null
    
        return
    
    }

#endregion CLEANUP
#region TOPOLOGY

function global:Initialize-PlatformTopology {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$Nodes,
        [switch]$ResetCache,
        [switch]$NoCache
    )

    if ($Nodes) {$ResetCache = $true}
    if (!$ResetCache -and !$NoCache) {
        if ($(Get-Cache platformtopology).Exists) {
            return Read-Cache platformtopology
        }
    }

    $Nodes ??= $global:PlatformTopologyBase.Nodes
    $Components = $global:PlatformTopologyBase.Components

    $platformTopology = @{
        Nodes = @{}
        Components = @{}
        Alias = @{}
    }

    # initialize nodes
    foreach ($node in $Nodes) {
        $platformTopology.Nodes.$node = @{
            Components = @{}
        }
        $ptAlias = ptBuildAlias $node
        if ($ptAlias) {
            $platformTopology.Alias.$ptAlias = $node
        }
        $platformTopology.Alias.$node = $node
    }

    # initialize components
    foreach ($component in $Components) {
        $platformTopology.Components.$component = @{
            Name = $component
            Nodes = @{}
        }
    }

    foreach ($node in $Nodes) {

        # designer
        $platformTopology.Components.Designer.Nodes += @{$node = @{}}
        $platformTopology.Nodes.$node.Components += @{
            Designer = @{
                Instances = @{}
            }
        } 

    }

    if (!$NoCache -and $platformTopology.Nodes) {
        $platformTopology | Write-Cache platformtopology
    }

    return $platformTopology

}
Set-Alias -Name ptInit -Value Initialize-PlatformTopology -Scope Global

#endregion TOPOLOGY