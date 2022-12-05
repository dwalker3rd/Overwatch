#region PLATFORMINFO

function global:Get-PlatformInfo {

    [CmdletBinding()]
    param (
        [switch][Alias("Update")]$ResetCache
    )

    if ($(get-cache platforminfo).Exists() -and !$ResetCache) {
        Write-Debug "Read-Cache platforminfo"
        $platformInfo = Read-Cache platforminfo # -MaxAge $(New-TimeSpan -Minutes 1)
        if ($platformInfo) {
            $global:Platform.Version = $platformInfo.Version
            $global:Platform.Build = $platformInfo.Build
            return
        }
    }
    
    try {
        Write-Debug "Get platform info via REST API"
        $global:Platform.Build = [regex]::Match($(Invoke-AlteryxService getversion),$global:RegexPattern.Software.Version).Groups[1].Value
        $global:Platform.Version = [regex]::Match($($global:Platform.Build),$global:RegexPattern.Software.Build).Groups[1].Value  
    }
    catch {

        Write-Error -Message $_.Exception.Message
        Write-Log -Message $_.Exception.Message -EntryType "Error" -Action Invoke-RestMethod -File $serverInfoUri -Status Failure
    
        $global:Platform.Version = $null
        $global:Platform.Build = $null
    }
    
    Write-Debug "Write-Cache platforminfo"
    Write-Cache platforminfo -InputObject @{Version=$global:Platform.Version;Build=$global:Platform.Build}

    return

}

#endregion PLATFORMINFO
#region PROCESS

function global:Get-PlatformProcess {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Online -Keys),
        [Parameter(Mandatory=$false)][string]$View,
        [switch]$ResetCache
    )

    if (!$ResetCache) {
        if ($(get-cache platformprocesses ).Exists()) {
            Write-Debug "Read-Cache platformprocesses"
            $platformProcesses = Read-Cache platformprocesses -MaxAge (New-TimeSpan -Seconds 10)
            if ($platformProcesses) {
                return $platformProcesses | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)
            }
        }
    }

    $platformTopology = Get-PlatformTopology -Online

    Write-Verbose "Get processes from node[s]: RUNNING ..." 
    $cimSession = New-CimSession -ComputerName $ComputerName
    $processes = Get-CimInstance -ClassName Win32_Process -CimSession $cimSession -Property * |
        Where-Object {$_.Name.Replace(".exe","") -in $PlatformProcessConfig.Name} 
    Remove-CimSession $cimSession
    
    Write-Verbose "Get processes from node[s]: COMPLETED"
    
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

function global:Get-PlatformService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Online -Keys),
        [Parameter(Mandatory=$false)][string]$View
    )

    $platformTopology = Get-PlatformTopology -Online

    Write-Verbose "Get services from node[s]: RUNNING ..."
    # $psSession = Get-PSSession+ -ComputerName $ComputerName
    # $services = Invoke-Command -Session $psSession {&{
    #     Get-Service -Name "AlteryxService" -InformationAction SilentlyContinue
    # }}
    $cimSession = New-CimSession -ComputerName $ComputerName -Credential (Get-Credentials "localadmin-$($Platform.Instance)" -Credssp) -Authentication CredSsp
    $services = Get-CimInstance -ClassName Win32_Service -CimSession $cimSession -Property * |
        Where-Object {$_.Name -eq $PlatformServiceConfig.Name} 
    Remove-CimSession $cimSession
    Write-Verbose "Get services from node[s]: COMPLETED"

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

    [CmdletBinding()]
    param()
    $Nodes = $true
    $Components = $true

    if ($Nodes) {

        $nodeStatusHashTable = (Get-AlteryxServerStatus).Nodes

        $nodeStatus = @()
        foreach ($node in (Get-PlatformTopology nodes -online -keys)) {
            $nodeStatus +=  [PsCustomObject]@{
                NodeId = ptGetAlias $node
                Node = $node
                Status = $nodeStatusHashTable[$node]
            }
        }

        $nodeStatus | Sort-Object -Property Node | Format-Table -Property Node, Status

    }

    if ($Components) {
        if ($Components) {

            Get-PlatformService | Where-Object -Property Required -EQ "True" | Sort-Object -Property Node, Name | Format-Table -Property Node, @{Name="Service";Expression={$_.Name}}, Status, Required, Transient, IsOK
            Get-PlatformProcess | Where-Object -Property Required -EQ "True" | Sort-Object -Property Node, Name | Format-Table -Property Node, @{Name="Process";Expression={$_.Name}}, Status, Required, Transient, IsOK

        }
    }

}
Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global

function global:Get-AlteryxServerStatus {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Online -Keys),
        [Parameter(Mandatory=$false)][ValidateSet("Controller","Database","Gallery","Worker")][string]$Component
    )

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

    $platformCimInstance = Get-PlatformService -ComputerName $ComputerName

    $controllerService = $platformCimInstance | Where-Object {$platformTopology.Components.Controller.Active.Nodes.Keys -contains $_.Node}
    if ($controllerService) {
        $controllerServiceStatus = @{Status = ($controllerService.Status | Sort-Object -Unique).Count -eq 1 ? ($controllerService.Status | Sort-Object -Unique) : "Degraded"}
        $controllerServiceStatus += @{IsOK = $controllerService ? $ServiceUpState -in $controllerServiceStatus.Status : $true}
        $controllerServiceNodes = $null
        foreach ($service in $controllerService) {
            Write-Verbose  "Controller on $($service.Node) is $($service.Status)"
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
                Write-Verbose  "Database on $($service.Node) is $($service.Status)"
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
            Write-Verbose  "Gallery on $($service.Node) is $($service.Status)"
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
            Write-Verbose  "Worker on $($service.Node) is $($service.Status)"
            $workerServiceNodes += @{$($service.Node) = $($service.Status)}
            $serviceNodes += @{$($service.Node) = $($service.Status)}
        }
        $workerServiceStatus += @{Nodes = $workerServiceNodes}

        $serviceStatus += $workerServiceStatus.Status
        $serviceIsOK = $serviceIsOK -and $workerServiceStatus.IsOK
    }

    $serviceStatus = ($serviceStatus | Sort-Object -Unique).Count -eq 1 ? ($serviceStatus | Sort-Object -Unique) : "Degraded"

    Write-Verbose  "IsOK = $($serviceIsOK)"
    Write-Verbose  "Status = $($serviceStatus)"

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
        [switch]$ResetCache
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
        [Parameter(Mandatory=$false)][string]$Path = "c$\programdata\alteryx\runtimesettings.xml"
    )

    $Path =  "\\$($ComputerName)\$($Path)"
    Write-Debug "$($Path)"

    return [xml]$(Get-Content -Path $Path)

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
    $exceptionMessage = $null

    foreach ($node in $ComputerName) {
        Write-Verbose "$($node.ToUpper()): alteryxservice $($p0) $($p1) $($p2)"
    }

    try {
        # note:  $p0$p1$p2 is correct!  no spaces
        $psSession = Get-PSSession+ -ComputerName $ComputerName
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
        $exceptionMessage = $_.Exception.Message
        $status = "Failure"
        $Log = $true
    }
    finally {
        Remove-PSSession $psSession
    }

    if ($hasResult) {Write-Verbose "Result = $($result)"}

    $HashArguments = @{
        Action = $p2Isfile ? $("alteryxservice $($p0)".Trim()) : $("alteryxservice $($p0) $($p1)".Trim())
        EntryType = $entryType
        Message = $exceptionMessage
        Status = $status
        Target = $p2Isfile ? $p2 : $null
    }

    if ($Log) {Write-Log @HashArguments}

    return $hasResult ? $result : $null

}  

#endregion ALTERYXSERVICE
#region START-STOP

function global:Get-PlatformJob {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName= (Get-PlatformTopology components.worker.nodes -Online -Keys)
    ) 
                
    $jobs = Get-PlatformProcess -ComputerName $ComputerName | 
        Where-Object {$_.DisplayName -eq $PlatformDictionary.AlteryxEngineCmd -and $_.Status -eq "Active"}

    return $jobs

}
Set-Alias -Name jobsGet -Value Get-PlatformJob -Scope Global

function global:Watch-PlatformJob {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName = (Get-PlatformTopology components.worker.nodes -Online -Keys),
        [Parameter(Mandatory=$false)][int32]$Seconds = 15
    ) 

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
        [Parameter(Mandatory=$true,Position=0)][string[]]$ComputerName
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

        $psSession = Get-PSSession+ -ComputerName $ComputerName
        Invoke-Command -Session $psSession {Stop-Process -Id $using:ProcessId -Force | Wait-Process -Timeout 30} 
        Remove-PSSession $psSession
    }
                
    $jobs = Get-PlatformJob -ComputerName $ComputerName 

    foreach ($job in $jobs) {
        Write-Host+ -NoTrace "Jobs are running on $($job.Node)"
        Write-Host+ -NoTrace "Terminating $($PlatformDictionary.AlteryxEngineCmd) on $($job.Node)"
        Write-Log -Action $Command -Status $services.Status -Message "Terminating $($PlatformDictionary.AlteryxEngineCmd) on $($job.Node)" -EntryType "Warning"

        Stop-ProcessTree -ComputerName $job.Node -ProcessId $job.Instance.Id

        # $psSession = Get-PSSession+ -ComputerName $job.Node
        # Invoke-Command -Session $psSession {Stop-Process -Name $using:job.Name -Force | Wait-Process -Timeout 15} 
    }

    $timer = [Diagnostics.Stopwatch]::StartNew()
    
    do {

        Start-Sleep -seconds 5

        $jobs = Get-PlatformJob -ComputerName $ComputerName  
            
        foreach ($job in $jobs) {
            Write-Host+ -NoTrace  "Jobs are running on $($job.Node)"
            Write-Host+ -NoTrace  "Terminating $($PlatformDictionary.AlteryxEngineCmd) on $($job.Node)"
            Write-Log -Action $Command -Status $services.Status -Message "Terminating $($PlatformDictionary.AlteryxEngineCmd) on $($job.Node)" -EntryType "Warning"

            Stop-ProcessTree -ComputerName $job.Node -ProcessId $job.Instance.Id
            
            # $psSession = Get-PSSession+ -ComputerName $job.Node
            # Invoke-Command -Session $psSession {Stop-Process -Name $using:job.Name -Force | Wait-Process -Timeout 15}
        }                

    } until (($jobs.Count -eq 0) -or ([math]::Round($timer.Elapsed.TotalSeconds,0) -gt $PlatformComponentTimeout))

    $timer.Stop()

    foreach ($job in $jobs) {
        Write-Host+ -NoTrace  "$($PlatformDictionary.AlteryxEngineCmd) is still running on $($job.Node)"
        Write-Log -Action $Command -Status $services.Status -EntryType Error -Message "Unable to stop $($PlatformDictionary.AlteryxEngineCmd) on $($job.Node)" 
    } 

    if ($jobs.Count -gt 0) {throw "Unable to stop $($jobs.Count) job$($jobs.Count -le 1 ? '' : 's')."}

    return 

}

function global:Request-PlatformComponent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Stop","Start","Enable","Disable")][string]$Command,
        [Parameter(Mandatory=$true,Position=1)][ValidateSet("Controller","Gallery","Database","Worker")][string]$Component,
        [Parameter(Mandatory=$false,Position=2)][string[]]$ComputerName,
        [switch]$Active,
        [switch]$Passive
    )

    # REQUIRED!
    # use a reinitialized **COPY** of the topology (in-memory and cached topologies are not affected)
    # this ensures that nodes that were removed/offlines are processed by this function
    $_platformTopology = Initialize-PlatformTopology -NoCache

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
    $ComputerName = $ComputerName ? $ComputerName : $_platformTopology.Components.$component.Nodes

    Write-Host+ -NoTrace "$($Command)","$($componentType)$($Component)" # -ForegroundColor ($Command -eq "Start" ? "Green" : "Red"),Gray
    Write-Log -Action $Command -Message "$($Command) $($componentType)$($Component)"        

    switch ($Component) {
        $_platformTopology.Components.Database.Name {
            if ($_platformTopology.Components.Controller.EmbeddedMongoDBEnabled) {
                Write-Host+ -NoTrace  "No external database." -ForegroundColor Yellow
                return
            }
            # TODO: add support for managing an external db
        }
        $_platformTopology.Components.Controller.Name {
            if ($Passive -and !$_platformTopology.Components.Controller.Passive) {
                Write-Host+ -NoTrace  "No passive controller." -ForegroundColor Yellow
                return
            }
            # TODO: add support for managing a passive controller
        }
        # $_platformTopology.Components.Worker.Name {
        #     # initial attempt before STOP command: all jobs may not stop
        #     Stop-PlatformJob $ComputerName
        # }
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
        
        if ($Command -eq "Stop" -and $Component -eq $_platformTopology.Components.Worker.Name) {
            # stop any new jobs that may have started between initial attempt and completion of STOP command
            Stop-PlatformJob $ComputerName
        }

        $timer = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -seconds 5
            $serviceStatus = Get-AlteryxServerStatus -ComputerName $ComputerName                
        } 
        until (($serviceStatus.Status -eq $targetState) -or ([math]::Round($timer.Elapsed.TotalSeconds,0) -gt $PlatformComponentTimeout))
        $timer.Stop()

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
        
        Write-Log -Context $Context -Action $Command -Status $commandStatus -Message "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"
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
function global:Start-Worker {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.worker.nodes -Keys))
    Request-PlatformComponent Start Worker -ComputerName $ComputerName
}
function global:Stop-Worker {
    param ([Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology components.worker.nodes -Keys))
    Request-PlatformComponent Stop Worker -ComputerName $ComputerName
}

#endregion STOP-START
#region BACKUP

function global:Get-BackupFileName {
    $global:Backup.Name = "$($global:Environ.Instance).$(Get-Date -Format 'yyyyMMddHHmm')"
    $global:Backup.File = "$($global:Backup.Path)\$($global:Backup.Name).$($global:Backup.Extension)"
    return $global:Backup.File
}

function global:Backup-Platform {

    [CmdletBinding()] param()
    
    Write-Host+ -NoTrace "Backup Running ..."
    Write-Log -Context "Backup" -Action "Backup" -Target "Platform" -Status "Running" -Message "Running" -Force
    Send-TaskMessage -Id "Backup" -Status "Running"

    # flag indicating that an error/exception has occurred
    $fail = $false
    $step = ""

    # stop and disable Monitor
    Disable-PlatformTask -Id "Monitor" -OutputType null -Quiet

    try {
        $step = "Platform STOP"
        Stop-Platform -Context "Backup"
    }
    catch {
        $fail = $true
        Write-Error "$step Failed"
        Write-Log -Context "Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -EntryType "Error" -Status "Failure" -Force
    }

    if (!$fail) {

        $step = "MongoDB Backup"

        Write-Verbose "$step PENDING"
        Write-Log -Context "Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Status "Pending" -Force

        try {
            Invoke-AlteryxService "emongodump=$(Get-BackupFileName)"
            Write-Verbose "$step COMPLETED"
            Write-Log -Context "Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -Status "Success" -Force
        }
        catch {
            $fail = $true
            Write-Error "$($_.Exception.Message)"
            Write-Error "$step FAILED"
            Write-Log -Context "Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -EntryType "Error" -Status "Failure" -Message $_.Exception.Message -Force
        } 

    }

    try {
        $step = "Platform START"
        Start-Platform -Context "Backup"
    }
    catch {
        $fail = $true
        Write-Error "$step failed"
        Write-Log -Context "Backup" -Action $step.Split(" ")[1] -Target $step.Split(" ")[0] -EntryType "Error" -Status "Failure" -Force
    }

    # enable Monitor
    Enable-PlatformTask -Id "Monitor" -OutputType null -Quiet

    if ($fail) {
        $message = "Backup failed at $step"
        Write-Error $message
        Write-Log -Context "Backup" -Action "Backup" -Target "Platform" -EntryType "Error" -Status "Failure" -Message $message -Force
        Send-TaskMessage -Id "Backup" -Status "Failure" -MessageType $PlatformMessageType.Alert

    } 
    else {       

        Write-Host+ -NoTrace "Backup Completed"
        Write-Log -Context "Backup" -Action "Backup" -Target "Platform" -Status "Success" -Message "Completed" -Force
        Send-TaskMessage -Id "Backup" -Status "Completed"
        
    }        

    return

}
Set-Alias -Name backup -Value Backup-Platform -Scope Global

#endregion BACKUP
#region CLEANUP

    function global:Cleanup-Platform {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

        [CmdletBinding()] param(
            [Parameter(Mandatory=$false)][Alias("a")][switch]$All = $global:Cleanup.All,
            [Parameter(Mandatory=$false)][Alias("b")][switch]$BackupFiles = $global:Cleanup.BackupFiles,
            [Parameter(Mandatory=$false)][Alias("backup-files-retention")][int]$BackupFilesRetention = $global:Cleanup.BackupFilesRetention,
            [Parameter(Mandatory=$false)][Alias("l")][switch]$LogFiles = $global:Cleanup.LogFiles,
            [Parameter(Mandatory=$false)][Alias("log-files-retention")][int]$LogFilesRetention = $global:Cleanup.LogFilesRetention
        )

        if ($All) {
            $BackupFiles = $true
            $LogFiles = $true
        }

        if (!$BackupFiles -and !$LogFiles) {
            $message = "You must specify at least one of the following switches: -All, -BackupFiles or -LogFiles."
            Write-Host+ $message -ForegroundColor Red
            Write-Log -Context "Cleanup" -Action "NONE" -EntryType "Error" -Status "Failure" -Message $message
            return
        }

        Write-Host+
        $message = "<Cleanup <.>48> PENDING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        # Write-Log -Context "Cleanup" -Action "Cleanup" -Status "Running" -Force
        # $result = Send-TaskMessage -Id "Cleanup" -Status "Running"
        # $result | Out-Null

        $platformTopology = Get-PlatformTopology
        # $ComputerName = $Force ? $ComputerName : $ComputerName | Where-Object {!$platformTopology[$ComputerName].Offline}

        $purgeBackupFilesSuccess = $true

        # purge backup files if the -BackupFiles switch was specified
        # for Overwatch for Alteryx Server, the Backup product must also be installed
        if ((Get-Product "Backup") -and $BackupFiles) {
            
            $message = "  <Backup files <.>48> PENDING"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            try{

                Remove-Files -Path $global:Backup.Path -Keep $BackupFilesRetention -Filter "*.$($global:Backup.Extension)" -Recurse -Force

                Write-Log -Context "Cleanup" -Action "Purge" -Target "Backup Files" -Status "Success" -Force
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

            }
            catch {

                Write-Log -Context "Cleanup" -Action "Purge" -Target "Backup Files" -EntryType "Error" -Status "Error" -Message $_.Exception.Message

                Write-Host+
                Write-Host+ -NoTrace -NoTimestamp "$($_.Exception.Message)" -ForegroundColor Red
                Write-Host+
                $message = "  <Backup files <.>48> FAILURE"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Red

                $purgeBackupFilesSuccess = $false

            }

        }
        else {
            $message = "<  Backup Files <.>48> SKIPPED"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
        }

        # Write-Host+ -MaxBlankLines 1

        $purgeLogFilesSuccess = $true

        # purge log files if the -LogFiles switch was specified
        if ($LogFiles) {

            $message = "<  Log Files <.>48> PENDING"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            try {
                
                # Controller/Service Logs
                $message = "<    Controller Logs <.>48> PENDING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray
                foreach ($controller in ($platformTopology.Components.Controller.Nodes.Keys)) {
                    [xml]$runTimeSettings = Get-RunTimeSettings -ComputerName $controller
                    if ($runTimeSettings.SystemSettings.Controller.LoggingPath) {
                        $controllerLogFilePath = split-path $runTimeSettings.SystemSettings.Controller.LoggingPath -Parent
                        $controllerLogFilePath = $controllerLogFilePath -replace "^([a-zA-Z])\:","\\$($controller)\`$1`$" 
                        if (Test-Path $controllerLogFilePath) {
                            $controllerLogFileName = split-path $runTimeSettings.SystemSettings.Controller.LoggingPath -LeafBase
                            $controllerLogFileExtension= split-path $runTimeSettings.SystemSettings.Controller.LoggingPath -Extension
                            $controllerLogFileFilter = "$($controllerLogFileName)*$($controllerLogFileExtension)"
                            Remove-Files -Path $controllerLogFilePath -Filter $controllerLogFileFilter -Keep $LogFilesRetention -Days
                        }
                    }
                }
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

                # Gallery Logs
                $message = "<    Gallery Logs <.>48> PENDING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray
                foreach ($gallery in ($platformTopology.Components.Gallery.Nodes.Keys)) {
                    [xml]$runTimeSettings = Get-RunTimeSettings -ComputerName $gallery
                    if ($runtimeSettings.SystemSettings.Gallery.LoggingPath) {
                        $galleryLogFilePath = $runtimeSettings.SystemSettings.Gallery.LoggingPath 
                        $galleryLogFilePath = $galleryLogFilePath -replace "^([a-zA-Z])\:","\\$($gallery)\`$1`$" 
                        if (Test-Path $galleryLogFilePath) {
                            Remove-Files -Path $galleryLogFilePath -Keep $LogFilesRetention -Days
                        }
                    }
                }
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

                # Engine Logs
                $message = "<    Worker Logs <.>48> PENDING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Gray
                foreach ($worker in ($platformTopology.Components.Worker.Nodes.Keys)) {
                    [xml]$runTimeSettings = Get-RunTimeSettings -ComputerName $worker
                    if ($runTimeSettings.SystemSettings.Engine.LogFilePath) {
                        $workerLogFilePath = $runtimeSettings.SystemSettings.Engine.LogFilePath 
                        $workerLogFilePath = $workerLogFilePath -replace "^([a-zA-Z])\:","\\$($worker)\`$1`$" 
                        if (Test-Path $workerLogFilePath) {
                            Remove-Files -Path $workerLogFilePath -Keep $LogFilesRetention -Days
                        }
                    }
                }
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen

                $message = "<  Log Files <.>48> SUCCESS"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

            }
            catch {

                Write-Host+
                Write-Host+ -NoTrace  "$($_.Exception.Message)" -ForegroundColor Red
                Write-Host+

                $message = "<  Log Files <.>48> FAILURE"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Red

                $purgeLogFilesSuccess = $false

            }   

        }
        else {
            $message = "<  Log Files <.>48> SKIPPED"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
        }
        
        $status = "SUCCESS"
        if (!$purgeBackupFilesSuccess -and $purgeLogFilesSuccess) { $status = "WARNING"}
        if (!$purgeLogFilesSuccess) { $status = "FAILURE"}
    
        $color = switch ($status) {
            "SUCCESS" { "DarkGreen" }
            "WARNING" { "DarkYellow" }
            "FAILURE" { "Red"}
        }
    
        $entryType = switch ($status) {
            "SUCCESS" { "Information" }
            "WARNING" { "Warning" }
            "FAILURE" { "Error"}
        }
    
        Write-Host+
        $message = "<Cleanup <.>48> $status"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,$color
        Write-Host+
    
        Write-Log -Context "Cleanup" -Action "Cleanup" -Status $status -EntryType $entryType -Force
        $result = Send-TaskMessage -Id "Cleanup" -Status "Completed" -Message $($status -eq "SUCCESS" ? "" : "See log files for details.")
        $result | Out-Null
    
        return
        
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
        if ($(get-cache platformtopology).Exists()) {
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
        if (![string]::IsNullOrEmpty($global:RegexPattern.PlatformTopology.Alias.Match)) {
            if ($node -match $global:RegexPattern.PlatformTopology.Alias.Match) {
                $ptAlias = ""
                foreach ($i in $global:RegexPattern.PlatformTopology.Alias.Groups) {
                    $ptAlias += $Matches[$i]
                }
                $platformTopology.Alias.($ptAlias) = $node
            }
        }
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
        $runTimeSettings = Get-RuntimeSettings -ComputerName $node
        if (!$runTimeSettings) {continue}

        # check controller settings
        if ($null -eq $runTimeSettings.SystemSettings.controller.ControllerEnabled -or $runTimeSettings.SystemSettings.controller.ControllerEnabled -eq "True") {
            
            $platformTopology.Components.Controller.Nodes += @{$node = @{}}

            if ("Controller" -notin $platformTopology.Nodes.$node.Components.Keys) {
                $platformTopology.Nodes.$node.Components += @{Controller = @{}}
                $platformTopology.Nodes.$node += @{ReadOnly = $true}
            }

            # TODO: bad assumption! figure out how to determine whether a controller is active or passive
            $platformTopology.Components.Controller.Active.Nodes += @{$node = @{}}

            # embedded MongoDB
            if ($runTimeSettings.SystemSettings.Controller.EmbeddedMongoDBEnabled -eq "True") {
                $platformTopology.Components.Controller.EmbeddedMongoDBEnabled = $true
                $platformTopology.Nodes.$node.Components.Controller += @{EmbeddedMongoDBEnabled = $true}
            }

        }

        if ($runTimeSettings.SystemSettings.Gallery.BaseAddress) {

            $baseAddress = $runTimeSettings.SystemSettings.Gallery.BaseAddress
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

        if ($null -eq $runTimeSettings.SystemSettings.Environment.workerEnabled) {

            $platformTopology.Components.Worker.Nodes += @{$node = @{}}
            
            if ("Worker" -notin $platformTopology.Nodes.$node.Components.Keys) {
                $platformTopology.Nodes.$node.Components += @{
                    Worker = @{
                        Instances = @{}
                    }
                }
            }
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
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Add","Remove","Online","Offline")][string]$Command,
        [Parameter(Mandatory=$true,Position=1)][string]$ComputerName
    )

    Write-Debug "$($Command) $($ComputerName)"

    # Add > add node to topology
    # Remove > remove node from topology
    # Online > bring node back online:  clear offline flag 
    # Offline > take node offline: set offline flag (node remains in topology)

    # ATTENTION: CONTROLLERS / READONLY
    # Controllers cannot be added/removed or offlined/onlined
    # Nodes marked as READONLY cannot be added/removed or offlined/onlined

    # ATTENTION: REMOVE / OFFLINE
    # During platform stop/start, Overwatch loads a temporary reinitialized copy of the topology (does not affect
    # the in-memory or cached topology).  This prevents controller-orphaned galleries/workers from potentially 
    # corrupting the Alteryx Server db.

    $platformTopology = Get-PlatformTopology

    switch ($Command) {
        "Add" {$ComputerName = $ComputerName}
        default {$ComputerName = $platformTopology.Nodes.$ComputerName ? $ComputerName : $platformTopology.Alias.$ComputerName}
    }

    if ($platformTopology.Nodes.$ComputerName.ReadOnly -or $platformTopology.Nodes.$ComputerName.Components.Controller) {
        throw "Invaid node '$($ComputerName)': Controllers may not be modified."
    }

    switch ($Command) {
        "Remove" {
            if (!$platformTopology.Nodes.$ComputerName) {throw "$($ComputerName) is *NOT* in the platform topology."}
            $platformTopology.Nodes.Remove($ComputerName) | Out-Null
            $result = Initialize-PlatformTopology -Nodes $platformTopology.Nodes.Keys
        }
        "Add" {
            if ($platformTopology.Nodes.$ComputerName) {throw "$($ComputerName) is already in the platform topology."}
            $platformTopology.Nodes.$ComputerName = @{}
            $platformTopology = Initialize-PlatformTopology -Nodes $platformTopology.Nodes.Keys
            $platformTopology.Nodes.$ComputerName.Online = $false
            $platformTopology | Write-Cache platformtopology
            Write-Host+ -NoTrace  "$($ComputerName) must brought online manually." -ForegroundColor Red
            $result = $platformTopology
        }
        "Online" {
            if (!$platformTopology.Nodes.$ComputerName) {throw "$($ComputerName) is *NOT* in the platform topology."}
            if (!$platformTopology.Nodes.$ComputerName.Offline) {throw "$($ComputerName) is already online."}
            $platformTopology.Nodes.$ComputerName.Remove("Offline")
            $platformTopology | Write-Cache platformtopology
            $result = $platformTopology
        }
        "Offline" {
            if (!$platformTopology.Nodes.$ComputerName) {throw "$($ComputerName) is *NOT* in the platform topology."}
            if ($platformTopology.Nodes.$ComputerName.Offline) {throw "$($ComputerName) is already offline."}
            $platformTopology.Nodes.$ComputerName.Offline = $true
            $platformTopology | Write-Cache platformtopology
            $result = $platformTopology
        }
    }
    
    return $result

}
Set-Alias -Name ptSet -Value Set-PlatformTopology -Scope Global

function global:Enable-PlatformTopology {
    param ([Parameter(Mandatory=$false,Position=0)][string]$ComputerName)
    return Set-PlatformTopology Online $ComputerName
}
Set-Alias -Name ptOn -Value Enable-PlatformTopology -Scope Global
Set-Alias -Name ptOnline -Value Enable-PlatformTopology -Scope Global
function global:Disable-PlatformTopology {
    param ([Parameter(Mandatory=$false,Position=0)][string]$ComputerName)
    return Set-PlatformTopology Offline $ComputerName
}
Set-Alias -Name ptOff -Value Disable-PlatformTopology -Scope Global
Set-Alias -Name ptOffline -Value Disable-PlatformTopology -Scope Global
function global:Add-PlatformTopology {
    param ([Parameter(Mandatory=$false,Position=0)][string]$ComputerName)
    return Set-PlatformTopology Add $ComputerName
}
Set-Alias -Name ptAdd -Value Add-PlatformTopology -Scope Global
function global:Remove-PlatformTopology {
    param ([Parameter(Mandatory=$false,Position=0)][string]$ComputerName)
    return Set-PlatformTopology Remove $ComputerName
}
Set-Alias -Name ptRem -Value Remove-PlatformTopology -Scope Global
Set-Alias -Name ptDel -Value Remove-PlatformTopology -Scope Global

#endregion TOPOLOGY
