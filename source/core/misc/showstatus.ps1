Write-Host+
Show-CloudStatus

foreach ($overwatchController in $global:OverwatchControllers) {

    $_environ = Get-EnvironConfig -Key Environ -Scope Global -ComputerName $overwatchController
    $_platform = Get-Catalog -Type Platform -Id $_environ.Platform

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Platform","$($_platform.Name)" -ForegroundColor Gray,DarkBlue -Separator ": "
    Write-Host+ -NoTrace -NoTimestamp "Instance","$($_environ.Instance)" -ForegroundColor Gray,DarkBlue -Separator ": "
    Write-Host+ -NoTrace -NoTimestamp $emptyString.PadLeft(10 + [math]::Max($_platform.Name.Length,$_environ.Instance.Length),"-")

    Show-PlatformStatus -Issues -CacheOnly -ComputerName $overwatchController

    Show-PlatformTasks -NoGroupBy -ComputerName $overwatchController
    Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 2

    Summarize-Log -Since Today -ShowSummary Default -ShowDetails Default -NoGroupBy -Descending -ComputerName $overwatchController
    Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 2

}

function Show-PlatformStatus {

    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$ResetCache,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$CacheOnly,
        [Parameter(Mandatory=$false,ParameterSetName="All")][string]$ComputerName = $env:COMPUTERNAME
    )

    $_environ = Get-EnvironConfig -Key Environ -Scope Global -ComputerName $ComputerName
    $_expression = "Show-$($_environ.Platform)PlatformStatus"
    if ($Summary) { $_expression += " -Summary)" }
    if ($All) { $_expression += " -All" }
    if ($Required) { $_expression += " -Required" }
    if ($Issues) { $_expression += " -Issues" }
    if ($ResetCache) { $_expression += " -ResetCache" }
    if ($CacheOnly) { $_expression += " -CacheOnly" }
    if ($ComputerName -and $ComputerName -ne $env:COMPUTERNAME) { $_expression += " -ComputerName $ComputerName" }
    Invoke-Expression $_expression

}

function Show-TableauServerPlatformStatus {

    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$ResetCache,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$CacheOnly,
        [Parameter(Mandatory=$false,ParameterSetName="All")][string]$ComputerName = $env:COMPUTERNAME
    )

    if (!$Summary -and $All -and !$Required -and !$Issues) { $Required = $true; $Issues = $true }
    if ($ResetCache -and $CacheOnly) {
        throw "The -ResetCache and -CacheOnly switches cannot be used together."
    }
    if (!$ResetCache -and !$CacheOnly) { $CacheOnly = $true }
    if ($ResetCache) { $CacheOnly = $false }
    if ($CacheOnly) { $ResetCache = $false }

    if ($ComputerName -eq $env:COMPUTERNAME) {
        $platformStatus = Get-PlatformStatus -CacheOnly:$($CacheOnly.IsPresent) -ResetCache:$($ResetCache.IsPresent) -Quiet
    }
    else {
        $platformStatus = Read-Cache platformstatus -ComputerName $Computername
    }
    $_platformStatusRollupStatus = $platformStatus.RollupStatus
    if ((![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $_platformStatusRollupStatus = switch ($platformStatus.Event) {
            "Start" { "Starting" }
            "Stop"  { "Stopping" }
        }
    }

    $_environ = Get-EnvironConfig -Key Environ -Scope Global -ComputerName $ComputerName
    $_platformInstance = $_environ.Instance
    $_platformTopology = Get-PlatformTopology -ComputerName $ComputerName

    # Write-Host+
    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), "PENDING" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGray

    #region STATUS

        # Write-Host+

        $nodes = $platformStatus.StatusObject.nodes | 
            Select-Object -Property @{Name='node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId -PlatformTopology $_platformTopology}}, 
                nodeId, @{Name='rollupStatus';Expression={![string]::IsNullOrEmpty($_.rollupStatus) ? $_.rollupStatus : "Unknown"}} | 
            Sort-Object -Property node

        foreach ($node in $nodes) {
            $message = "<  $($node.node) ($($node.nodeId))$($node.node -eq ($_platformTopology.InitialNode) ? "*" : $null) <.>42> $($node.RollupStatus.ToUpper())"
            $nodeRollupStatusColor = $node.RollupStatus -in $global:PlatformStatusColor.Keys ? $global:PlatformStatusColor.($node.RollupStatus) : "DarkRed"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($node.RollupStatus) ? "DarkGray" : $nodeRollupStatusColor)
        }

        $platformRollupStatusColor = $platformStatus.RollupStatus -in $global:PlatformStatusColor.Keys ? $global:PlatformStatusColor.($platformStatus.RollupStatus) : "DarkRed"
        Write-Host+ -NoTrace -NoTimestamp -Parse "<  $($_platformInstance) <.>42> $($_platformStatusRollupStatus.ToUpper())" -ForegroundColor Gray,DarkGray, $platformRollupStatusColor

    #endregion STATUS      
    #region EVENTS    

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {

            Write-Host+

            Write-Host+ -NoTrace -NoTimestamp -Parse "<  Event <.>42> $($platformStatus.Event)" -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($platformStatus.Event) ? "DarkGray" : $global:PlatformEventColor.($platformStatus.Event))
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventStatus <.>42> $($global:PlatformEventStatus.($platformStatus.EventStatus))" -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($platformStatus.EventStatus) ? "DarkGray" : $global:PlatformEventStatusColor.($platformStatus.EventStatus))
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventCreatedBy <.>42> $($platformStatus.EventCreatedBy)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventCreatedAt <.>42> $($platformStatus.EventCreatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $(!$platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventUpdatedAt <.>42> $($platformStatus.EventUpdatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $($platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventCompletedAt <.>42> $($platformStatus.EventCompletedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventHasCompleted <.>42> $($platformStatus.EventHasCompleted)" -ForegroundColor Gray,DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"

            # Show-PlatformEvent -PlatformStatus $platformStatus

        }

    #endregion EVENTS     
    #region ISSUES

        $platformIssues = $platformStatus.platformIssues
        if ($Issues -and $platformIssues) {
            $platformIssues = $platformIssues | 
                Select-Object -Property @{Name='Node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId -PlatformTopology $_platformTopology}}, @{Name='Service';Expression={"$($_.name)_$($_.instanceId)"}}, @{Name='Status';Expression={$_.processStatus}}, @{Name='Message';Expression={$_.message}}
            $platformIssues | Format-Table -Property Node, Service, Status, Message
        }

    #endregion ISSUES
    #region SERVICES

        if ($All -or ($Issues -and $platformIssues)) {
            $services = $platformStatus.ByCimInstance # Get-PlatformServices
            if ($Required) { $services = $services | Where-Object {$_.Required} }
            if ($Issues) { $services = $services | Where-Object {!$_.StatusOK.Contains($_.Status)} }
            $services | Select-Object Node, @{Name='NodeId';Expression={ptGetAlias $_.Node}}, Class, Name, Status, Required, Transient, IsOK | 
                Sort-Object -Property Node, Name | Format-Table -GroupBy Node -Property Node, NodeId, Class, Name, Status, Required, Transient, IsOK
        }

    #endregion SERVICES

    # Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)

    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), $_platformStatusRollupStatus.ToUpper() -ForegroundColor DarkBlue,Gray,DarkGray, $platformRollupStatusColor

    # Write-Host+

}

function Show-TableauRMTPlatformStatus {

    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$ResetCache,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$CacheOnly,
        [Parameter(Mandatory=$false,ParameterSetName="All")][string]$ComputerName = $env:COMPUTERNAME
    )

    if (!$Summary -and !$All -and !$Required -and !$Issues) { $Required = $true; $Issues = $true }
    if ($ResetCache -and $CacheOnly) {
        throw "The -ResetCache and -CacheOnly switches cannot be used together."
    }
    if (!$ResetCache -and !$CacheOnly) { $CacheOnly = $true }
    if ($ResetCache) { $CacheOnly = $false }
    if ($CacheOnly) { $ResetCache = $false }

    if ($ComputerName -eq $env:COMPUTERNAME) {
        $platformStatus = Get-PlatformStatus -CacheOnly:$($CacheOnly.IsPresent) -ResetCache:$($ResetCache.IsPresent) -Quiet
    }
    else {
        $platformStatus = Read-Cache platformstatus -ComputerName $Computername
    }
    $_platformStatusRollupStatus = $platformStatus.RollupStatus
    if ((![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $_platformStatusRollupStatus = switch ($platformStatus.Event) {
            "Start" { "Starting" }
            "Stop"  { "Stopping" }
        }
    }

    $_environ = Get-EnvironConfig -Key Environ -Scope Global -ComputerName $ComputerName
    $_platformInstance = $_environ.Instance

    # Write-Host+
    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), "PENDING" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGray

    #region STATUS  

        # Write-Host+

        # $rmtStatus = Get-RMTStatus -ResetCache -Quiet
        $rmtStatus = $platformStatus.StatusObject
        $controller = $rmtStatus.ControllerStatus
        $agents = $rmtStatus.AgentStatus
        # $environments = $rmtStatus.EnvironmentStatus

        $_nodeId = 0
        $nodeStatus = @()
        # Platform
        # $nodeStatus +=  [PsCustomObject]@{
        #     NodeId = ""
        #     Node = $_platformInstance
        #     Status = $controller.RollupStatus
        #     Role = "Platform"
        #     Version = $controller.Controller.ProductVersion
        # }
        # Controller
        $nodeStatus +=  [PsCustomObject]@{
            NodeId = $_nodeId
            Node = $controller.Name
            Status = $controller.RollupStatus
            Role = "Controller" # Get-RMTRole $controller.Name
            Version = $controller.Controller.ProductVersion
        }
        # Agents
        foreach ($agent in $agents) {
            $_nodeId = $_nodeId++
            $nodeStatus +=  [PsCustomObject]@{
                NodeId = $_nodeId
                Node = $agent.Name
                Status = $agent.RollupStatus
                Role = "Agent" # Get-RMTRole $agent.Name
                Version = $agent.Agent.ProductVersion
            }
        }

        $nodeStatus = $nodeStatus | Sort-Object -Property NodeId, Node

        foreach ($_nodeStatus in $nodeStatus) {
            $message = "<  $($_nodeStatus.Role) ($($_nodeStatus.Node))$($_nodeStatus.node -eq $controller.Name ? "*" : $null) <.>42> $($_nodeStatus.Status.ToUpper())"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($_nodeStatus.Status)
        }
        # $nodeStatus | Sort-Object -Property Node | Format-Table -Property Role, Node, Status, Version

    #endregion STATUS      
    #region EVENTS       

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  Event < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.Event -ForegroundColor DarkGray, $global:PlatformEventColor.($platformStatus.Event)
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventStatus < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventStatus -ForegroundColor DarkGray, $global:PlatformEventStatusColor.($platformStatus.EventStatus)
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventCreatedBy < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventCreatedBy -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventCreatedAt < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventCreatedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventUpdatedAt < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventUpdatedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventCompletedAt < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventCompletedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventHasCompleted < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventHasCompleted -ForegroundColor DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"
        }

    #endregion EVENTS     
    #region ISSUES    

        $platformIssues = $null
        if ($Issues -and $platformIssues) {
            $platformIssues | Format-Table -Property @{Name='Role';Expression={$_.Role[0]}}, Node, Class, Name, Status
        }    

    #endregion ISSUES
    #region SERVICES        

        if ($All -or ($Issues -and $platformIssues)) {
            $services = [array]$Controller.Controller.Services + [array]$rmtStatus.AgentStatus.Agent.Services
            if ($Required) { $services = $services | Where-Object {$_.Required} }
            if ($Issues) { $services = $services | Where-Object {!$_.IsOK} }
            $services | Sort-Object -Property Node, Name | Format-Table -Property @{Name='Role';Expression={$_.Component[0]}}, Node, Class, Name, Status, Required, Transient, IsOK 
        }

    #endregion SERVICES   

    # Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)
    
    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), $_platformStatusRollupStatus.ToUpper() -ForegroundColor DarkBlue,Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

    # Write-Host+

}

function Show-NonePlatformStatus {

    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$ResetCache,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$CacheOnly,
        [Parameter(Mandatory=$false,ParameterSetName="All")][string]$ComputerName = $env:COMPUTERNAME
    )

    if (!$Summary -and !$All -and !$Required -and !$Issues) { $Required = $true; $Issues = $true }
    if ($ResetCache -and $CacheOnly) {
        throw "The -ResetCache and -CacheOnly switches cannot be used together."
    }
    if (!$ResetCache -and !$CacheOnly) { $CacheOnly = $true }
    if ($ResetCache) { $CacheOnly = $false }
    if ($CacheOnly) { $ResetCache = $false }

    if ($ComputerName -eq $env:COMPUTERNAME) {
        $platformStatus = Get-PlatformStatus -CacheOnly:$($CacheOnly.IsPresent) -ResetCache:$($ResetCache.IsPresent) -Quiet
    }
    else {
        $platformStatus = Read-Cache platformstatus -ComputerName $Computername
    }
    $_platformStatusRollupStatus = $platformStatus.RollupStatus
    if ((![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $_platformStatusRollupStatus = switch ($platformStatus.Event) {
            "Start" { "Starting" }
            "Stop"  { "Stopping" }
        }
    }

    $_environ = Get-EnvironConfig -Key Environ -Scope Global -ComputerName $ComputerName
    $_platformInstance = $_environ.Instance
    $_platformTopology = Get-PlatformTopology -ComputerName $ComputerName

    # Write-Host+
    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), "PENDING" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGray

    #region STATUS

        # Write-Host+

        $message = "<  $($ComputerName.ToLower()) <.>38> $($platformStatus.RollupStatus)"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

        Write-Host+ -NoTrace -NoTimestamp -Parse "<  $($_platformInstance) <.>38> $($_platformStatusRollupStatus)" -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

    #endregion STATUS   
    #region EVENTS    

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {

            Write-Host+

            Write-Host+ -NoTrace -NoTimestamp -Parse "<  Event <.>42> $($platformStatus.Event)" -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($platformStatus.Event) ? "DarkGray" : $global:PlatformEventColor.($platformStatus.Event))
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventStatus <.>42> $($global:PlatformEventStatus.($platformStatus.EventStatus))" -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($platformStatus.EventStatus) ? "DarkGray" : $global:PlatformEventStatusColor.($platformStatus.EventStatus))
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventCreatedBy <.>42> $($platformStatus.EventCreatedBy)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventCreatedAt <.>42> $($platformStatus.EventCreatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $(!$platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventUpdatedAt <.>42> $($platformStatus.EventUpdatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $($platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventCompletedAt <.>42> $($platformStatus.EventCompletedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -Parse "<  EventHasCompleted <.>42> $($platformStatus.EventHasCompleted)" -ForegroundColor Gray,DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"

            # Show-PlatformEvent -PlatformStatus $platformStatus

        }

    #endregion EVENTS           
    #region ISSUES

        $platformIssues = $platformStatus.platformIssues
        if ($All -or ($Issues -and $platformIssues)) {
            $platformIssues = $platformIssues | 
                Select-Object -Property @{Name='Node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId -PlatformTopology $_platformTopology}}, @{Name='Service';Expression={"$($_.name)_$($_.instanceId)"}}, @{Name='Status';Expression={$_.processStatus}}, @{Name='Message';Expression={$_.message}}
            $platformIssues | Format-Table -Property Node, Service, Status, Message
        }

    #endregion ISSUES

    # Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)

    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), $_platformStatusRollupStatus.ToUpper() -ForegroundColor DarkBlue,Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

    # Write-Host+

}

function Show-AlteryxServerPlatformStatus {

    [CmdletBinding(DefaultParameterSetName = "All")]
    param(
        [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$ResetCache,
        [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$CacheOnly,
        [Parameter(Mandatory=$false,ParameterSetName="All")][string]$ComputerName = $env:COMPUTERNAME
    )

    if (!$Summary -and !$All -and !$Required -and !$Issues) { $Required = $true; $Issues = $true }
    if ($ResetCache -and $CacheOnly) {
        throw "The -ResetCache and -CacheOnly switches cannot be used together."
    }
    if (!$ResetCache -and !$CacheOnly) { $CacheOnly = $true }
    if ($ResetCache) { $CacheOnly = $false }
    if ($CacheOnly) { $ResetCache = $false }

    if ($ComputerName -eq $env:COMPUTERNAME) {
        $platformStatus = Get-PlatformStatus -CacheOnly:$($CacheOnly.IsPresent) -ResetCache:$($ResetCache.IsPresent) -Quiet
    }
    else {
        $platformStatus = Read-Cache platformstatus -ComputerName $Computername
    }
    $_platformStatusRollupStatus = $platformStatus.RollupStatus
    if ((![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        $_platformStatusRollupStatus = switch ($platformStatus.Event) {
            "Start" { "Starting" }
            "Stop"  { "Stopping" }
        }
    }

    $_environ = Get-EnvironConfig -Key Environ -Scope Global -ComputerName $ComputerName
    $_platformInstance = $_environ.Instance
    $_platformTopology = Get-PlatformTopology -ComputerName $ComputerName

    # Write-Host+
    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), "PENDING" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGray

    #region STATUS

        # Write-Host+

        # check platform status and for any active events
        # $platformStatus = Get-PlatformStatus -ResetCache -Quiet

        $nodeStatusHashTable = $_platformStatus.StatusObject.Nodes

        $nodeStatus = @()
        $_offlineNodes = $_platformTopology.nodes.keys | Where-Object {$_platformTopology.nodes.$_.offline}
        foreach ($node in ($_offlineNodes)) {
            $ptNode = pt nodes.$node
            $nodeStatus += [PsCustomObject]@{
                Role = $_platformTopology.nodes.$node.components.Keys
                Alias = Get-PlatformTopologyAlias -Alias $node -PlatformTopology $_platformTopology
                Node = $node
                Status = !$ptNode.Shutdown ? "Offline" : "Shutdown"
            }
        }
        $_onlineNodes = $_platformTopology.nodes.keys | Where-Object {$_platformTopology.nodes.$_.online}
        foreach ($node in ($_onlineNodes)) {
            $nodeStatus += [PsCustomObject]@{
                Role = $_platformTopology.nodes.$node.components.Keys
                Alias = Get-PlatformTopologyAlias -Alias $node -PlatformTopology $_platformTopology
                Node = $node
                Status = $nodeStatusHashTable[$node]
            }
        }

        $nodeStatus = $nodeStatus | Sort-Object -Property Role, Node
        
        foreach ($_nodeStatus in $nodeStatus) {
            $message = "<  $($_nodeStatus.Role) ($($_nodeStatus.Node))$($_nodeStatus.node -eq ($_platformTopology.components.Controller.nodes.Keys) ? "*" : $null) <.>42> $($_nodeStatus.Status.ToUpper())"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($_nodeStatus.Status)
        }
        # $nodeStatus | Sort-Object -Property Node | Format-Table -Property Node, Alias, Status

    #endregion STATUS      
    #region EVENTS            

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  Event < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.Event -ForegroundColor DarkGray, $global:PlatformEventColor.($platformStatus.Event)
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventStatus < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventStatus -ForegroundColor DarkGray, $global:PlatformEventStatusColor.($platformStatus.EventStatus)
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventCreatedBy < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventCreatedBy -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventCreatedAt < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventCreatedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventUpdatedAt < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventUpdatedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventCompletedAt < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventCompletedAt -ForegroundColor DarkGray, Gray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp -NoNewLine -Parse "<  EventHasCompleted < >42> " -ForegroundColor Gray, DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoTimestamp ":", $platformStatus.EventHasCompleted -ForegroundColor DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"
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
                $_components = $_platformStatus.ByCimInstance | Where-Object {$_.Class -in ("Service","Process")}
                if ($Required) { $_components = $_components | Where-Object {$_.Required} }
                if ($Issues) { $_components = $_components | Where-Object {!$_.IsOK} }
                $_components | Sort-Object -Property Node, Name | Format-Table -GroupBy Node -Property Node, @{Name='Alias';Expression={Get-PlatformTopologyAlias -Alias $_.Node -PlatformTopology $_platformTopology}}, Class, Name, Status, Required, Transient, IsOK, Component
            }
        }

    #endregion SERVICES   
    
    # Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)
    
    Write-Host+ -NoTrace -NoTimestamp $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), $_platformStatusRollupStatus.ToUpper() -ForegroundColor DarkBlue,Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)  
    
    # Write-Host+

}