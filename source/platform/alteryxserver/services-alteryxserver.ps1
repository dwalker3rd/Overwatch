#region PLATFORMINFO

function global:Get-PlatformInfo {

    [CmdletBinding()]
    param (
        [switch][Alias("Update")]$ResetCache
    )

    if ($(Get-Cache platforminfo).Exists -and !$ResetCache) {
        Write-Host+ -IfDebug "Read-Cache platforminfo" -ForegroundColor DarkYellow
        $platformInfo = Read-Cache platforminfo # -MaxAge $(New-TimeSpan -Minutes 1)
        if ($platformInfo) {
            $global:Platform.Version = $platformInfo.Version
            $global:Platform.Build = $platformInfo.Build
            return
        }
    }
    
    try {
        Write-Host+ -IfDebug "Get platform info via REST API" -ForegroundColor DarkYellow
        $global:Platform.Build = [regex]::Match($(Invoke-AlteryxService getversion),$global:RegexPattern.Software.Version).Groups[1].Value
        $global:Platform.Version = [regex]::Match($($global:Platform.Build),$global:RegexPattern.Software.Build).Groups[1].Value  
    }
    catch {

        Write-Host+ $_.Exception.Message -ForegroundColor DarkRed
        Write-Log -Action "Invoke-AlteryxService" -Target "getversion" -Exception $_.Exception
    
        $global:Platform.Version = $null
        $global:Platform.Build = $null
    }
    
    Write-Host+ -IfDebug "Write-Cache platforminfo" -ForegroundColor DarkYellow
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

    if (!$ResetCache) {
        if ((Get-Cache platformprocesses).Exists) {
            Write-Host+ -IfDebug "Read-Cache platformprocesses" -ForegroundColor DarkYellow
            $platformProcesses = Read-Cache platformprocesses -MaxAge (New-TimeSpan -Seconds 10)
            if ($platformProcesses) {
                return $platformProcesses | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)
            }
        }
    }

    $platformTopology = Get-PlatformTopology -Online

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

    $platformProcesses | Write-Cache platformprocesses

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

    if (!$Summary -and !$All) { $All = $true }

    $platformStatus = Get-PlatformStatus -Quiet
    $_platformStatusRollupStatus = $platformStatus.RollupStatus
    if ((![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $_platformStatusRollupStatus = switch ($platformStatus.Event) {
            "Start" { "Starting" }
            "Stop"  { "Stopping" }
        }
    }

    Write-Host+
    $message = "<$($global:Platform.Instance) Status <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    #region STATUS    
    
        Write-Host+

        # check platform status and for any active events
        $platformStatus = Get-PlatformStatus -ResetCache -Quiet

        $nodeStatusHashTable = (Get-AlteryxServerStatus).Nodes

        $nodeStatus = @()
        foreach ($node in (Get-PlatformTopology nodes -offline -keys)) {
            $ptNode = pt nodes.$node
            $nodeStatus += [PsCustomObject]@{
                Role = pt nodes.$node.components -k
                Alias = ptBuildAlias $node
                Node = $node
                Status = !$ptNode.Shutdown ? "Offline" : "Shutdown"
            }
        }
        foreach ($node in (Get-PlatformTopology nodes -online -keys)) {
            $nodeStatus += [PsCustomObject]@{
                Role = pt nodes.$node.components -k
                Alias = ptBuildAlias $node
                Node = $node
                Status = $nodeStatusHashTable[$node]
            }
        }

        $nodeStatus = $nodeStatus | Sort-Object -Property Role, Node
        
        foreach ($_nodeStatus in $nodeStatus) {
            $message = "<  $($_nodeStatus.Role) ($($_nodeStatus.Node))$($_nodeStatus.node -eq (pt components.Controller.nodes -k) ? "*" : $null) <.>38> $($_nodeStatus.Status)"
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
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)    

}
Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global

function global:Get-AlteryxServerStatus {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][ValidateSet("Controller","Database","Gallery","Worker")][string]$Component
    )

    if ([string]::IsNullOrEmpty($ComputerName)) {
        $ComputerName = Get-PlatformTopology nodes -Keys -Online
    }

    $platformTopology = Get-PlatformTopology

    if (![string]::IsNullOrEmpty($Component)) {
        $Component = (Get-Culture).TextInfo.ToTitleCase($Component)
        $ComputerName = $platformTopology.Components.$component.Nodes
    }
    if ($Component -eq $platformTopology.Components.Database.Name -and $platformTopology.Components.Controller.EmbeddedMongoDBEnabled) {
        throw "Unsupported"
    }  

    $serviceIsOK = $true
    $serviceStatus = @()
    $serviceNodes = $null

    $platformCimInstance = Get-PlatformServices -ComputerName $ComputerName

    $controllerService = $platformCimInstance | Where-Object {$platformTopology.Components.Controller.Active.Nodes.Keys -contains $_.Node}
    if ($controllerService) {
        $controllerServiceStatus = @{Status = ($controllerService.Status | Sort-Object -Unique).Count -eq 1 ? ($controllerService.Status | Sort-Object -Unique) : "Degraded"}
        $controllerServiceStatus += @{IsOK = $controllerService ? $ServiceUpState -in $controllerServiceStatus.Status : $true}
        $controllerServiceNodes = $null
        foreach ($service in $controllerService) {
            Write-Host+ -IfVerbose  "Controller on $($service.Node) is $($service.Status)" -ForegroundColor DarkYellow
            $controllerServiceNodes += @{$($service.Node) = $($service.Status)}
            $serviceNodes += @{$($service.Node) = $($service.Status)}
        }
        $controllerServiceStatus += @{Nodes = $controllerServiceNodes}
        
        $serviceStatus += $controllerServiceStatus.Status
        $serviceIsOK = $serviceIsOK -and $controllerServiceStatus.IsOK
    }

    if (!$platformTopology.Components.Controller.EmbeddedMongoDBEnabled) {
        $databaseService = $platformCimInstance | Where-Object {$platformTopology.Components.Database.Nodes.Keys -contains $_.Node}
        if ($databaseService) {
            $databaseServiceStatus = @{Status = ($databaseService.Status | Sort-Object -Unique).Count -eq 1 ? ($databaseService.Status | Sort-Object -Unique) : "Degraded"}
            $databaseServiceStatus += @{IsOK = $databaseService ? $ServiceUpState -in $databaseServiceStatus.Status : $true}
            $databaseServiceNodes = $null
            foreach ($service in $databaseService) {
                Write-Host+ -IfVerbose  "Database on $($service.Node) is $($service.Status)" -ForegroundColor DarkYellow
                $databaseServiceNodes += @{$($service.Node) = $($service.Status)}
                $serviceNodes += @{$($service.Node) = $($service.Status)}
            }
            $databaseServiceStatus += @{Nodes = $databaseServiceNodes}

            $serviceStatus += $databaseServiceStatus.Status
            $serviceIsOK = $serviceIsOK -and $databaseServiceStatus.IsOK
        }
    }

    $galleryService = $platformCimInstance | Where-Object {$platformTopology.Components.Gallery.Nodes.Keys -contains $_.Node}
    if ($galleryService) {
        $galleryServiceStatus = @{Status = ($galleryService.Status | Sort-Object -Unique).Count -eq 1 ? ($galleryService.Status | Sort-Object -Unique) : "Degraded"}
        $galleryServiceStatus += @{IsOK = $galleryService ? $ServiceUpState -in $galleryServiceStatus.Status : $true}
        $galleryServiceNodes = $null
        foreach ($service in $galleryService) {
            Write-Host+ -IfVerbose  "Gallery on $($service.Node) is $($service.Status)" -ForegroundColor DarkYellow
            $galleryServiceNodes += @{$($service.Node) = $($service.Status)}
            $serviceNodes += @{$($service.Node) = $($service.Status)}
        }
        $galleryServiceStatus += @{Nodes = $galleryServiceNodes}

        $serviceStatus += $galleryServiceStatus.Status
        $serviceIsOK = $serviceIsOK -and $galleryServiceStatus.IsOK
    }

    $workerService = $platformCimInstance | Where-Object {$platformTopology.Components.Worker.Nodes.Keys -contains $_.Node}
    if ($workerService) {
        $workerServiceStatus = @{Status = ($workerService.Status | Sort-Object -Unique).Count -eq 1 ? ($workerService.Status | Sort-Object -Unique) : "Degraded"}
        $workerServiceStatus += @{IsOK = $workerService ? $ServiceUpState -in $workerServiceStatus.Status : $true}
        $workerServiceNodes = $null
        foreach ($service in $workerService) {
            Write-Host+ -IfVerbose  "Worker on $($service.Node) is $($service.Status)" -ForegroundColor DarkYellow
            $workerServiceNodes += @{$($service.Node) = $($service.Status)}
            $serviceNodes += @{$($service.Node) = $($service.Status)}
        }
        $workerServiceStatus += @{Nodes = $workerServiceNodes}

        $serviceStatus += $workerServiceStatus.Status
        $serviceIsOK = $serviceIsOK -and $workerServiceStatus.IsOK
    }

    $serviceStatus = ($serviceStatus | Sort-Object -Unique).Count -eq 1 ? ($serviceStatus | Sort-Object -Unique) : "Degraded"

    Write-Host+ -IfVerbose  "IsOK = $($serviceIsOK)" -ForegroundColor DarkYellow
    Write-Host+ -IfVerbose  "Status = $($serviceStatus)" -ForegroundColor DarkYellow

    $alteryxServerStatus = @{
        IsOK = $serviceIsOK
        Status = $serviceStatus
        Nodes = $serviceNodes
    }
    if (![string]::IsNullOrEmpty($Component)) {$alteryxServerStatus += @{Component = $Component}}

    if ($controllerService) {$alteryxServerStatus += @{Controller = $controllerServiceStatus}}
    if ($databaseService) {$alteryxServerStatus += @{Database = $databaseServiceStatus}}
    if ($galleryService) {$alteryxServerStatus += @{Gallery = $galleryServiceStatus}}
    if ($workerService) {$alteryxServerStatus += @{Worker = $workerServiceStatus}}

    if ($controllerService -and $platformTopology.Components.Controller.EmbeddedMongoDBEnabled) {$alteryxServerStatus += @{EmbeddedMongoDBEnabled = $true}}

    return $alteryxServerStatus
}

function global:Get-PlatformStatusRollup {
    
    [CmdletBinding()]
    param (
        [switch]$ResetCache,
        [switch]$Quiet
    )

    $alteryxServerStatus = Get-AlteryxServerStatus
    
    $platformCimInstance = Get-PlatformCimInstance
    $issues = $platformCimInstance | Where-Object {$_.Required -and $_.Class -in ("Service","Process") -and !$_.IsOK} | 
        Select-Object -Property Node, Class, Name, Status, @{Name="Component";Expression={$_.Component -join ", "}}, ParentName
    
    return $alteryxServerStatus.IsOK, $alteryxServerStatus.Status, $issues

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
            $ComputerName = Get-PlatformTopology components.worker.nodes -Online -Keys
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
            [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName = (Get-PlatformTopology components.worker.nodes -Online -Keys),
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

        if (!$ComputerName -and !$Id) { $ComputerName = Get-PlatformTopology components.worker.nodes -Online -Keys }

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
#region PLATFORM/COMPONENT START/STOP

function global:Request-PlatformComponent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateSet("Stop","Start","Enable","Disable")][string]$Command,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateSet("Controller","Gallery","Database","Worker")][string]$Component,

        [Parameter(Mandatory=$false,Position=2)]
        [string[]]$ComputerName,

        [Parameter(Mandatory=$false)]
        [timespan]$Timeout = $global:PlatformComponentTimeout,

        [Parameter(Mandatory=$false)][switch]$Active,
        [Parameter(Mandatory=$false)][switch]$Passive,

        [Parameter(Mandatory=$false)][switch]$Drain,
        [Parameter(Mandatory=$false)][switch]$Kill
    )

    # # REQUIRED!
    # # use a reinitialized **COPY** of the topology (in-memory and cached topologies are not affected)
    # # this ensures that nodes that were removed/offlines are processed by this function
    # $_platformTopology = Initialize-PlatformTopology -NoCache

    $_platformTopology = Initialize-PlatformTopology

    if ($Active -or $Passive) {
        if ($Component -ne $_platformTopology.Components.Controller.Name) {throw "The Active and Passive switches are only valid with a Controller."}
        if ($Active -and $Passive) {throw "The Active and Passive switches cannot be combined."}
    }

    $componentType = switch ($Component) {
        $_platformTopology.Components.Controller.Name {$Active ? "Active" : "Passive"}
        default {$null}
    }
    if ($componentType) {$componentType = "$($componentType.Trim()) "}

    $Command = (Get-Culture).TextInfo.ToTitleCase($Command)
    $Component = (Get-Culture).TextInfo.ToTitleCase($Component)

    Write-Host+ -NoTrace "$($Command)","$($componentType)$($Component)" # -ForegroundColor ($Command -eq "Start" ? "Green" : "Red"),Gray
    Write-Log -Action $Command -Message "$($Command) $($componentType)$($Component)"        

    $ComputerName = $ComputerName ? $ComputerName : $_platformTopology.Components.$component.Nodes.Keys

    # STOP: [attempt to] stop all nodes even if they are offline.
    # START: ignore/skip offline nodes
    if ($Command -eq "Start") {

        $onlineNodes = @()
        foreach ($node in $ComputerName) {
            if ($_platformTopology.Nodes.$node.Offline) {
                Write-Host+ -NoTrace "$Component on $node is", "Offline" -ForegroundColor Gray, DarkYellow
            }
            else {
                $onlineNodes += $node
            }
        }

        # if there are no online nodes in $ComputerName then indicate that all are offline
        # however, if there's only one node, then it's a redundant message, so skip it
        if (!$onlineNodes -and $ComputerName.Count -gt 1) {
            Write-Host+ -NoTrace "$Component nodes are", "Offline" -ForegroundColor Gray, DarkYellow
            return
        }

        $ComputerName = $onlineNodes
        
    }

    $ComputerName = $ComputerName | ForEach-Object { Get-PlatformTopologyAlias $_}

    switch ($Component) {
        $_platformTopology.Components.Database.Name {
            if ($_platformTopology.Components.Controller.EmbeddedMongoDBEnabled) {
                Write-Host+ -NoTrace  "No external database" -ForegroundColor Yellow
                return
            }
            # TODO: add support for managing an external db
        }
        $_platformTopology.Components.Controller.Name {
            if ($Passive -and !$_platformTopology.Components.Controller.Passive) {
                Write-Host+ -NoTrace  "No passive controller" -ForegroundColor Yellow
                return
            }
            # TODO: add support for managing a passive controller
        }
        $_platformTopology.Components.Worker.Name {
            if (!$Kill) { $Drain = $true }
        }
    }

    $serviceStatus = Get-AlteryxServerStatus -ComputerName $ComputerName
    $serviceNodes = $serviceStatus.$($Component).Nodes
    foreach ($node in $serviceNodes.Keys) {
        Write-Log -Action $Command -Status $serviceNodes[$node] -Message "$($componentType)$($Component) on $($node) is $($serviceNodes[$node])"
        Write-Host+ -NoTrace  "$($componentType)$($Component) on $($node) is","$($serviceNodes[$node])" -ForegroundColor Gray,($serviceNodes[$node] -eq $PlatformDictionary.Start ? "Green" : "Red")
    }

    $targetState = $PlatformDictionary.$($Command)
    if ($serviceStatus.Status -ne $targetState) {   

        Invoke-AlteryxService $Command.ToLower() -ComputerName $ComputerName -Log     
        
        if ($Command -eq "Stop" -and $Component -eq $_platformTopology.Components.Worker.Name -and $Kill) {
            # kill all running jobs immediately
            Stop-PlatformJob $ComputerName
        }

        $timer = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -seconds 5
            $serviceStatus = Get-AlteryxServerStatus -ComputerName $ComputerName                
        } 
        until (($serviceStatus.Status -eq $targetState) -or ([math]::Round($timer.Elapsed.TotalSeconds,0) -gt $Timeout))
        $timer.Stop()        
        
        if ($serviceStatus.Status -ne $targetState -and $Command -eq "Stop" -and $Component -eq $_platformTopology.Components.Worker.Name) {
            # timeout exceeded: kill all running jobs immediately
            Stop-PlatformJob $ComputerName
        }

        $serviceNodes = $serviceStatus.$($Component).Nodes
        foreach ($node in $serviceNodes.Keys) {
            Write-Log -Action $Command -Status $serviceNodes[$node] -EntryType $($serviceNodes[$node] -eq $targetState ? "Information" : "Error") -Message "$($componentType)$($Component) on $($node) is $($serviceNodes[$node])"
            Write-Host+ -NoTrace  "$($componentType)$($Component) on $($node) is","$($serviceNodes[$node])" -ForegroundColor Gray,($serviceNodes[$node] -eq $PlatformDictionary.Start ? "Green" : "Red")
        }
        
        if ($serviceStatus.Status -ne $targetState) {
            Write-Host+ -NoTrace "Failed to $($Command) $($componentType)$($Component)" -ForegroundColor Red
        }
    }

    # set AlteryxService to Manual if STOP command
    # set AlteryxService to AutomaticDelayedStart if START command
    # TODO: the StartupType for the START command could be configurable
    switch ($Component) {
        # ignore external database
        $_platformTopology.Components.Database.Name {}
        default {
            $startupType = switch ($Command) {
                "Stop" { "Manual" }
                "Start" { "AutomaticDelayedStart" }
            }
            Set-PlatformService -Name "AlteryxService" -StartupType $startupType -ComputerName $ComputerName
            foreach ($node in $ComputerName) {
                Write-Host+ -NoTrace  "$($componentType)$($Component) on $($node) startup is",$startupType -ForegroundColor Gray,($Command -eq "Start" ? "Green" : "Red")
            }
        }
    }

    return
}

function global:Request-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Stop","Start")][string]$Command,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason
    )

    Write-Host+ -NoTrace "$($Command)","$($global:Platform.Name)" # -ForegroundColor ($Command -eq "Start" ? "Green" : "Red"),Gray
    Write-Log -Action $Command -Message "$($Command) $($global:Platform.Name)"

    $targetState = $PlatformDictionary.$($command)

    $serviceStatus = Get-AlteryxServerStatus
    Write-Host+ -NoTrace  "$($global:Platform.Name) is","$($serviceStatus.Status)" -ForegroundColor Gray,($serviceStatus.Status -eq $PlatformDictionary.Start ? "Green" : "Red")
    Write-Log -Action $Command -Status $serviceStatus.Status -Message "$($global:Platform.Name) is $($serviceStatus.Status)"

    if ($serviceStatus.Status -ne $targetState) {   
        
        $commandStatus = $PlatformEventStatus.InProgress
        Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus

        try {

            switch ($Command) {
                "Stop" {

                    <# 
                        Alteryx Server Stop Order
                        -------------------------
                        1. Stop workers
                        2. Stop galleries
                        3. Disable passive controller
                        4. Stop active controller
                        5. Stop external database
                    #>

                    Stop-Worker
                    Stop-Gallery
                    Disable-PassiveController
                    Stop-Controller
                    Stop-Database

                }

                "Start" {

                    <# 
                        Alteryx Server Start Order
                        --------------------------
                        0. Preflight checks
                        1. Start external database
                        2. Start active controller
                        3. Enable passive controller
                        4. Start galleries
                        5. Start workers
                    #>      

                    Update-Preflight -Force
                    Start-Database
                    Start-Controller
                    Enable-PassiveController
                    Start-Gallery
                    Start-Worker
                    Confirm-Postflight -Force

                }

            }      
                            
            $commandStatus = $PlatformEventStatus.Completed

        }
        catch {

            $commandStatus = $PlatformEventStatus.Failed

        }

        Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus
        
        Write-Log -Action $Command -Status $commandStatus -Message "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"
        Write-Host+ -NoTrace  "$($global:Platform.Name)","$($Command.ToUpper())","$($commandStatus)" -ForegroundColor Gray,($commandStatus -eq $PlatformEventStatus.Completed ? "Green" : "Red")
        # Write-Host+ -NoTrace  "$($global:Platform.Name)","$($Command.ToUpper())","$($commandStatus)" -ForegroundColor Gray,($Command -eq $PlatformDictionary.Start ? "Green" : "Red"),($commandStatus -eq $PlatformEventStatus.Completed ? "Green" : "Red")
        
        if ($commandStatus -eq $PlatformEventStatus.Failed) {throw "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"}

    }

    return
}

function global:Start-Platform {

    [CmdletBinding()] param (
        [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id ?? "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start platform"
    )

    Request-Platform -Command Start -Context $Context -Reason $Reason
}
function global:Stop-Platform {

    [CmdletBinding()] param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop platform"
    )
    
    Request-Platform -Command Stop -Context $Context -Reason $Reason
}

function global:Restart-Platform {

    [CmdletBinding()] param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Restart platform"
    )

    Stop-Platform -Context $Context -Reason $Reason
    Start-Platform -Context $Context -Reason $Reason
}

function global:Start-Database {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.database.nodes -Keys))
    Request-PlatformComponent Start Database -ComputerName $ComputerName
}
function global:Stop-Database {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.database.nodes -Keys))
    Request-PlatformComponent Stop Database -ComputerName $ComputerName
}
function global:Start-Controller {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.controller.nodes -Keys))
    Request-PlatformComponent Start Controller -Active -ComputerName $ComputerName
}
function global:Stop-Controller {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.controller.nodes -Keys))
    Request-PlatformComponent Stop Controller -Active -ComputerName $ComputerName
}
function global:Enable-PassiveController {
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.controller.nodes -Keys))
    Request-PlatformComponent Enable Controller -Passive -ComputerName $ComputerName
}
function global:Disable-PassiveController {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.controller.nodes -Keys))
    Request-PlatformComponent Disable Controller -Passive -ComputerName $ComputerName
}
function global:Start-Gallery {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.gallery.nodes -Keys))
    Request-PlatformComponent Start Gallery -ComputerName $ComputerName
}
function global:Stop-Gallery {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.gallery.nodes -Keys))
    Request-PlatformComponent Stop Gallery -ComputerName $ComputerName
}
function global:Restart-Gallery {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.gallery.nodes -Keys))
    Request-PlatformComponent Stop Gallery -ComputerName $ComputerName
    Request-PlatformComponent Start Gallery -ComputerName $ComputerName
}
function global:Start-Worker {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.worker.nodes -Keys))
    Request-PlatformComponent Start Worker -ComputerName $ComputerName
}
function global:Stop-Worker {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.worker.nodes -Keys))
    Request-PlatformComponent Stop Worker -ComputerName $ComputerName
}
function global:Restart-Worker {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.worker.nodes -Keys))
    Request-PlatformComponent Stop Worker -ComputerName $ComputerName
    Request-PlatformComponent Start Worker -ComputerName $ComputerName
}

#endregion PLATFORM/COMPONENT START/STOP
#region BACKUP

function global:Backup-Platform {

    [CmdletBinding()] param()
    
    Write-Host+ -NoTrace "Backup Running ..."
    Write-Log -Context "Product.Backup" -Action "Backup" -Target "Platform" -Status "Running" -Message "Running" -Force
    Send-TaskMessage -Id "Backup" -Status "Running" | Out-Null

    # flag indicating that an error/exception has occurred
    $fail = $false
    $step = ""

    # stop and disable Monitor
    Disable-PlatformTask -Id "Monitor" -OutputType null

    $platformStatusBeforeBackup = Get-PlatformStatus -ResetCache

    if ($platformStatusBeforeBackup.RollupStatus -eq "Running") {
        try {
            $step = "Platform STOP"
            Stop-Platform -Context "Backup"
        }
        catch {
            $fail = $true
            Write-Host+ "$step Failed" -ForegroundColor DarkRed
            Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -EntryType "Error" -Status "Failure" -Force
        }
    }

    $backupFolder = "$($global:Backup.Path)\$($global:Backup.Name).$($global:Backup.Extension)"

    if (!$fail) {

        $step = "MongoDB Backup"

        Write-Host+ -IfVerbose "$step PENDING" -ForegroundColor DarkYellow
        Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Status "Pending" -Force

        try {
            Invoke-AlteryxService "emongodump=$backupFolder"
            Write-Host+ -IfVerbose "$step COMPLETED" -ForegroundColor DarkYellow
            Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Status "Success" -Force
        }
        catch {
            $fail = $true
            Write-Host+ $_.Exception.Message -ForegroundColor DarkRed
            Write-Host+ "$step FAILED" -ForegroundColor DarkRed
            Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Exception $_.Exception
        } 

        if (!$fail) {

            $step = "RuntimeSettings.xml Backup"

            Write-Host+ -IfVerbose "$step PENDING" -ForegroundColor DarkYellow
            Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Status "Pending" -Force

            try {
                Copy-File $global:Location.RuntimeSettings -Destination $backupFolder -Verbose
                Write-Host+ -IfVerbose "$step COMPLETED" -ForegroundColor DarkYellow
                Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Status "Success" -Force
            }
            catch {
                $fail = $true
                Write-Host+ $_.Exception.Message -ForegroundColor DarkRed
                Write-Host+ "$step FAILED" -ForegroundColor DarkRed
                Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Exception $_.Exception
            } 

        }

    }

    if ($platformStatusBeforeBackup.RollupStatus -eq "Running") {
        try {
            $step = "Platform START"
            Start-Platform -Context "Backup"
        }
        catch {
            $fail = $true
            Write-Host+ "$step failed" -ForegroundColor DarkRed
            Write-Log -Context "Product.Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -EntryType "Error" -Status "Failure" -Force
        }
    }

    # enable Monitor
    Enable-PlatformTask -Id "Monitor" -OutputType null

    if ($fail) {
        $message = "Backup failed at $step"
        Write-Host+ $message -ForegroundColor DarkRed
        Write-Log -Context "Product.Backup" -Action "Backup" -Target "Platform" -EntryType "Error" -Status "Failure" -Message $message -Force
        Send-TaskMessage -Id "Backup" -Status "Failure" -MessageType $PlatformMessageType.Alert | Out-Null

    } 
    else {       

        Write-Host+ -NoTrace "Backup Completed"
        Write-Log -Context "Product.Backup" -Action "Backup" -Target "Platform" -Status "Success" -Message "Completed" -Force
        Send-TaskMessage -Id "Backup" -Status "Completed" | Out-Null
        
    }        

    return

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

                # Backup Files
                if ($node -eq (Get-OverwatchController $node)) {
                    $backupCatalogObject = Get-Catalog -Uid Product.Backup -ComputerName $node
                    if ($backupCatalogObject.IsInstalled()) {
                        
                        $message = "<    Backup Files <.>48> PENDING"
                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                        $params = @{}
                        $params += @{
                            ComputerName = $node
                            Path = $global:Backup.Path
                            Filter = "*.$($global:Backup.Extension)"
                        }
                        $params += Get-RetentionPeriod ($global:Backup.Retention ?? $global:Cleanup.Default.Retention)
                        Remove-Files @params

                        Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen
                    }
                }

                [xml]$runtimeSettings = Get-RunTimeSettings -ComputerName $node

                $controllerLogFilePath = Split-Path $runtimeSettings.SystemSettings.Controller.LoggingPath -Parent
                $engineDefaultTempFilePath = $runtimeSettings.SystemSettings.Engine.DefaultTempFilePath
                $enginePackageStagingPath = $runtimeSettings.SystemSettings.Engine.PackageStagingPath
                $engineLogFilePath = $runtimeSettings.SystemSettings.Engine.LogFilePath
                $galleryLogFilePath = $runtimeSettings.SystemSettings.Gallery.LoggingPath
                $workerStagingPath = $runtimeSettings.SystemSettings.Worker.StagingPath

                # AlteryxService: Log Files
                if ($global:Cleanup.AlteryxService.LogFiles -and $controllerLogFilePath -and (Test-Path+ -Path $controllerLogFilePath -ComputerName $node)) {

                    $message = "<    AlteryxService Log Files <.>48> PENDING"
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                    $controllerLogFileName = Split-Path $runtimeSettings.SystemSettings.Controller.LoggingPath -LeafBase
                    $controllerLogFileExtension= Split-Path $runtimeSettings.SystemSettings.Controller.LoggingPath -Extension

                    $params = @{}
                    $params += @{
                        ComputerName = $node
                        Path = $controllerLogFilePath
                        Filter = "$($controllerLogFileName)*$($controllerLogFileExtension)"
                    }
                    $params += Get-RetentionPeriod ($global:Cleanup.AlteryxService.LogFiles.Retention ?? $global:Cleanup.Default.Retention)
                    Remove-Files @params

                    Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

                }

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

                # Gallery: Log Files
                if ($global:Cleanup.Gallery.LogFiles -and $galleryLogFilePath -and (Test-Path+ -Path $galleryLogFilePath -ComputerName $node)) {

                    $message = "<    Gallery Log Files <.>48> PENDING"
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                    foreach ($galleryLogFilePathFilter in $global:Cleanup.Engine.StagingFiles.Filter) {

                        $params = @{}
                        $params += @{
                            ComputerName = $node
                            Path = $galleryLogFilePath
                            Filter = $galleryLogFilePathFilter
                        }
                        $params += Get-RetentionPeriod ($global:Cleanup.Engine.StagingFiles.Retention ?? $global:Cleanup.Default.Retention)
                        Remove-Files @params

                    }

                    Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

                }

                 # Worker: Staging Files
                if ($global:Cleanup.Worker.StagingFiles -and $workerStagingPath -and (Test-Path+ -Path $workerStagingPath -ComputerName $node)) {

                    $message = "<    Worker Staging Files <.>48> PENDING"
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray

                    foreach ($workerStagingPathFilter in $global:Cleanup.Worker.StagingFiles.Filter) {

                        $params = @{}
                        $params += @{
                            ComputerName = $node
                            Path = $workerStagingPath
                            Filter = $workerStagingPathFilter
                        }
                        $params += Get-RetentionPeriod ($global:Cleanup.Worker.StagingFiles.Retention ?? $global:Cleanup.Default.Retention)
                        Remove-Files @params

                    }

                    Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen
                    
                }              

                # Write-Host+
                # $message = "<  $node <.>48> SUCCESS"
                # Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
                # Write-Host+

            }
            

        # }
        # catch {

        #     $cleanupSuccess = $false

        #     Write-Host+
        #     Write-Host+ -NoTrace  "$($_.Exception.Message)" -ForegroundColor Red
        #     Write-Host+

        # }   

        # $status = "SUCCESS"
        # if (!$cleanupSuccess) { $status = "FAILURE"}
    
        # $color = switch ($status) {
        #     "SUCCESS" { "DarkGreen" }
        #     "WARNING" { "DarkYellow" }
        #     "FAILURE" { "Red"}
        # }
    
        # $entryType = switch ($status) {
        #     "SUCCESS" { "Information" }
        #     "WARNING" { "Warning" }
        #     "FAILURE" { "Error"}
        # }
    
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

    $platformTopologyCache = Read-Cache platformtopology

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
        switch ($component) {
            $platformTopology.Components.Controller.Name {
                $platformTopology.Components.$component.Active = @{Nodes = @{}}
            }
        }
    }

    # define passive controllers here
    # this would be based on Windows Failover Clustering

    foreach ($node in $Nodes) {

        # get runtimesettings.xml config file from node
        $runtimeSettings = Get-RuntimeSettings -ComputerName $node
        if ($runtimeSettings) {
            # node is up and running; remove the shutdown property, if present
            $platformTopology.Nodes.$node.Remove("Shutdown")
        }
        else {
            # node is down and not running
            # set shutdown and offline; set component using default component map
            $platformTopology.Nodes.$node.Components = @{ $global:PlatformTopologyDefaultComponentMap.$node = @{} }
            $platformTopology.nodes.$node.Offline = $true
            if (!(Test-NetConnection -ComputerName $node -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)) {
                $platformTopology.nodes.$node.Shutdown = $true
            }
            continue
        }

        # check controller settings
        if ($null -eq $runtimeSettings.SystemSettings.controller.ControllerEnabled -or $runtimeSettings.SystemSettings.controller.ControllerEnabled -eq "True") {
            
            $platformTopology.Components.Controller.Nodes += @{$node = @{}}

            if ("Controller" -notin $platformTopology.Nodes.$node.Components.Keys) {
                $platformTopology.Nodes.$node.Components += @{Controller = @{}}
                $platformTopology.Nodes.$node += @{ReadOnly = $true}
            }

            # TODO: bad assumption! figure out how to determine whether a controller is active or passive
            $platformTopology.Components.Controller.Active.Nodes += @{$node = @{}}

            # embedded MongoDB
            if ($runtimeSettings.SystemSettings.Controller.EmbeddedMongoDBEnabled -eq "True") {
                $platformTopology.Components.Controller.EmbeddedMongoDBEnabled = $true
                $platformTopology.Nodes.$node.Components.Controller += @{EmbeddedMongoDBEnabled = $true}
            }

        }

        # gallery
        if ($runtimeSettings.SystemSettings.Gallery.BaseAddress) {
            $baseAddress = $runtimeSettings.SystemSettings.Gallery.BaseAddress
            if ($baseAddress[$baseAddress.Length-1] -eq "/") {$baseAddress = $baseAddress.subString(0,$baseAddress.Length-1)}
            if ($baseAddress -eq $global:Platform.Uri) {
                $platformTopology.Components.Gallery.Nodes += @{$node = @{}}
                if ("Gallery" -notin $platformTopology.Nodes.$node.Components.Keys) {
                    $platformTopology.Nodes.$node.Components += @{
                        Gallery = @{
                            Instances = @{}
                        }
                    }
                }
            }
        }

        # worker
        if ($null -eq $runtimeSettings.SystemSettings.Environment.workerEnabled) {
            $platformTopology.Components.Worker.Nodes += @{$node = @{}}
            if ("Worker" -notin $platformTopology.Nodes.$node.Components.Keys) {
                $platformTopology.Nodes.$node.Components += @{
                    Worker = @{
                        Instances = @{}
                    }
                }
            } 
        }

        # if node was offline prior to calling Initialize-platformTopology ($platformTopologyCache), 
        # then set it to offline in $platformTopology
        if ($platformTopologyCache.nodes.$node.Offline) {
            $platformTopology.nodes.$node.Offline = $platformTopologyCache.nodes.$node.Offline
        }

        # if node was set to go offline automatically prior to calling Initialize-platformTopology ($platformTopologyCache), 
        # then set it to go offline automatically in $platformTopology
        if ($platformTopologyCache.nodes.$node.Until) {
            $platformTopology.nodes.$node.Until = $platformTopologyCache.nodes.$node.Until
        }

    }

    foreach ($component in $Components) {
        if (!$platformTopology.Components.$component.Nodes) {
            if ($component -eq "Database" -and !$platformTopology.Components.Controller.EmbeddedMongoDBEnabled) {
                throw "Database undefined"
            }
        }
    }

    if ($platformTopology.Components.Controller.Active.Nodes.Count -gt 1) {
        throw "Found multiple active controllers"
    }

    if (!$NoCache -and $platformTopology.Nodes) {
        $platformTopology | Write-Cache platformtopology
    }


    return $platformTopology

}
Set-Alias -Name ptInit -Value Initialize-PlatformTopology -Scope Global

function global:Set-PlatformTopology {
    
    param (
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Online","Offline")][string]$Command,
        [Parameter(Mandatory=$true,Position=1)][string]$ComputerName,
        [Parameter(Mandatory=$false)][timespan]$Duration,
        [switch]$Shutdown,
        [switch]$Force
    )

    # $boundParameters = Get-PSBoundParameters

    # Online > bring node back online:  clear offline flag 
    # Offline > take node offline: set offline flag (node remains in topology)

    # ATTENTION: CONTROLLERS / READONLY
    # Controllers cannot be offlined/onlined
    # Nodes marked as READONLY cannot be offlined/onlined

    $platformTopology = Get-PlatformTopology
    $ComputerName = $platformTopology.Nodes.$ComputerName ? $ComputerName : ($platformTopology.Alias.$ComputerName ?? $ComputerName)
    if ($Command.ToLower() -eq "add" -and $global:PlatformTopologyBase.Nodes -notcontains $ComputerName) {
        throw "Invalid node $($ComputerName): Not defined in `$global:PlatformTopologyBase."
    }

    if ($platformTopology.Nodes.$ComputerName.ReadOnly -or $platformTopology.Nodes.$ComputerName.Components.Controller) {
        throw "Invalid node $($ComputerName): Controller nodes may not be modified."
    }

    switch ($Command.ToLower()) {
        "online" {
            
            if (!$platformTopology.Nodes.$ComputerName) {throw "Node $($ComputerName) is *NOT* in the platform topology"}
            if (!$platformTopology.Nodes.$ComputerName.Offline -and !$Force) {
                Write-Host+ -NoTrace "Node $($ComputerName) is already online" -ForegroundColor DarkGray
                return 
            }

            $ptNodeComponents = pt nodes.$ComputerName.components -k

            try {

                # invoke preflight checks for this node 
                # if these fail, do not continue
                try {
                    Invoke-Preflight -Action Check -Target PlatformInstance -ComputerName $ComputerName -Throw
                    $platformTopology.Nodes.$ComputerName.Remove("Shutdown")
                }
                catch {
                    $platformTopology.Nodes.$ComputerName.Shutdown = $true
                    Write-Host+ -NoTrace "Node","$($ComputerName)","is","Shutdown" -ForegroundColor Gray,Blue,Gray,DarkRed
                    # return
                }

                if ($platformTopology.Nodes.$ComputerName.Shutdown) {

                    $result = Start-Computer -ComputerName $ComputerName
                    if ($result.IsSuccessStatusCode) {
                        $platformTopology.Nodes.$ComputerName.Remove("Shutdown")
                    }

                    # # invoke preflight checks for this node (again)
                    # # if these fail, do not continue
                    # try {
                    #     Invoke-Preflight -Action Check -Target PlatformInstance -ComputerName $ComputerName -Throw -Quiet
                    #     $platformTopology.Nodes.$ComputerName.Remove("Shutdown")
                    # }
                    # catch {
                    #     $platformTopology.Nodes.$ComputerName.Shutdown = $true
                    #     Write-Host+ -NoTrace "Node","$($ComputerName)","is","Shutdown" -ForegroundColor Gray,Blue,Gray,DarkRed
                    #     return
                    # }

                }

                # invoke preflight updates for this node 
                # if these fail, do not continue
                try {
                    Invoke-Preflight -Action Update -Target PlatformInstance -ComputerName $ComputerName -Throw
                }
                catch {
                    throw "Node $($ComputerName) failed preflight updates"
                }
                
                Write-Host+

                # AlteryxService StartupType is Disabled if previously set offline
                # AlteryxService must be un-Disabled (enabled or set to manual) to be started.
                Set-PlatformService -Name "AlteryxService" -StartupType Manual -Computername $ComputerName
                Write-Host+ -NoTrace "Node","$($ComputerName)","startup is","Manual" -ForegroundColor Gray,Blue,Gray,Red
    
                # remove Offline before calling start (start ignores offline nodes)
                $platformTopology.Nodes.$ComputerName.Remove("Offline")
                if ($Duration -ne [timespan]::MaxValue) {
                    $platformTopology.Nodes.$ComputerName.Until = @{
                        Expiry = [datetime]::Now + $Duration
                    } 
                    if ($Shutdown) {
                        $platformTopology.Nodes.$ComputerName.Until.PostAction = "Shutdown"
                    }
                }
                foreach ($ptNodeComponent in $ptNodeComponents) {
                    if (!$platformTopology.Components.$ptNodeComponent.Nodes.Contains($ComputerName)) {
                        $platformTopology.Components.$ptNodeComponent.Nodes += @{$ComputerName = @{}}
                    }
                }
                $platformTopology | Write-Cache platformtopology
                
                foreach ($ptNodeComponent in $ptNodeComponents) {
                    Invoke-Expression "Start-$ptNodeComponent $ComputerName"
                }

                Write-Log -Action ptOnline -Target $ComputerName -Status Online -EntryType Warning -Data $platformTopology.Nodes.$ComputerName.Until -Force
                Write-Host+ -NoTrace -NoNewLine "Node","$($ComputerName)","is","Online" -ForegroundColor Gray, Blue, Gray, DarkGreen
                Write-Host+ -Iff $($null -ne $platformTopology.Nodes.$ComputerName.Until) -NoTrace -NoTimestamp -NoNewLine " until $($platformTopology.Nodes.$ComputerName.Until.Expiry)" -ForegroundColor DarkGray
                Write-Host+ # closes the -NoNewLine sequence
                Write-Host+ -Iff $($null -ne $platformTopology.Nodes.$ComputerName.Until) -NoTrace "Node","$($ComputerName)","will be","Shutdown","at $($platformTopology.Nodes.$ComputerName.Until.Expiry)" -ForegroundColor Gray, Blue, Gray, DarkRed, DarkGray
                Write-Host+

            }
            catch {

                Write-Log -Action ptOnline -Target $ComputerName -Exception $_.Exception
                Write-Host+ $_ -ForegroundColor DarkRed
                Write-Host+ -NoTrace "Unable to online node $($ComputerName)" -ForegroundColor DarkRed
                Write-Host+

            }

        }
        "offline" {

            if (!$platformTopology.Nodes.$ComputerName) {throw "Node $($ComputerName) is *NOT* in the platform topology."}
            if ($platformTopology.Nodes.$ComputerName.Offline -and !$Force) {
                Write-Host+ -NoTrace "Node $($ComputerName) is already offline" -ForegroundColor DarkGray
                return 
            }

            $ptNodeComponents = pt nodes.$ComputerName.components -k

            try {

                # invoke preflight checks for this node 
                # if these fail, do not continue
                try {
                    Invoke-Preflight -Action Check -Target PlatformInstance -ComputerName $ComputerName -Throw
                    $platformTopology.Nodes.$ComputerName.Shutdown = $false
                }
                catch {
                    $platformTopology.Nodes.$ComputerName.Shutdown = $true
                    # Write-Host+ -NoTrace "Node","$($ComputerName)","is","Shutdown" -ForegroundColor Gray,Blue,Gray,DarkRed
                }
                $platformTopology | Write-Cache platformtopology

                if (!$platformTopology.Nodes.$ComputerName.Shutdown) {

                    foreach ($ptNodeComponent in $ptNodeComponents) {
                        Invoke-Expression "Stop-$ptNodeComponent $ComputerName"
                    }

                    # AlteryxService StartupType is set to Manual by Stop-$Component (Request-PlatformComponent)
                    # Set AlteryxService StartupType to Disabled to prevent it from starting unintentionally
                    Set-PlatformService -Name "AlteryxService" -StartupType Disabled -Computername $ComputerName
                    Write-Host+ -NoTrace "Node","$($ComputerName)","startup is","Disabled" -ForegroundColor Gray,Blue,Gray,Red

                }

                $platformTopology.Nodes.$ComputerName.Offline = $true
                $platformTopology.Nodes.$ComputerName.Remove("Until")
                foreach ($ptNodeComponent in $ptNodeComponents) {
                    $platformTopology.Components.$ptNodeComponent.Remove($ComputerName)
                }
                $platformTopology | Write-Cache platformtopology

                Write-Log -Action ptOffline -Target $ComputerName -Status Offline -EntryType Warning -Force
                Write-Host+ -NoTrace "Node","$($ComputerName)","is","Offline" -ForegroundColor Gray, Blue, Gray, DarkRed

                if (!$platformTopology.Nodes.$ComputerName.Shutdown -and $Shutdown) {
                    $result = Stop-Computer -ComputerName $ComputerName -NoWait
                    $platformTopology.Nodes.$ComputerName.Shutdown = $result.IsSuccessStatusCode
                }
                $platformTopology | Write-Cache platformtopology

                if ($platformTopology.Nodes.$ComputerName.Shutdown) {
                    Write-Host+ -NoTrace "Node","$($ComputerName)","is","Shutdown" -ForegroundColor Gray, Blue, Gray, DarkRed
                }

                Write-Host+

            }
            catch {

                Write-Log -Action ptOffline -Target $ComputerName -Exception $_.Exception
                Write-Host+ $_ -ForegroundColor DarkRed
                Write-Host+ -NoTrace "Unable to offline node $($ComputerName)" -ForegroundColor DarkRed
                Write-Host+

            }

        }
    }
    
    return # $result

}
Set-Alias -Name ptSet -Value Set-PlatformTopology -Scope Global

function global:Enable-PlatformTopology {
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [Parameter(Mandatory=$false)][timespan]$Duration = [timespan]::MaxValue,
        [switch]$Shutdown,
        [switch]$Force
    )
    return Set-PlatformTopology Online $ComputerName -Duration $Duration -Shutdown:$Shutdown.IsPresent -Force:$Force.IsPresent
}
Set-Alias -Name ptOnline -Value Enable-PlatformTopology -Scope Global

function global:Disable-PlatformTopology {
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$Shutdown,
        [switch]$Force
    )
    return Set-PlatformTopology Offline $ComputerName -Shutdown:$Shutdown.IsPresent -Force:$Force.IsPresent
}
Set-Alias -Name ptOffline -Value Disable-PlatformTopology -Scope Global

#endregion TOPOLOGY