#region TOPOLOGY

function global:Get-RMTComponent {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string[]]$ComputerName
    )

    if ($ComputerName -in $global:PlatformTopologyBase.Components.Controller.Nodes.Keys) {return "Controller"}
    if ($ComputerName -in (pt components.agent.nodes -k)) {return "Agent"}

    throw "Node `"$ComputerName`" : not part of this platform's topology"

}

function global:Initialize-PlatformTopology {

    [CmdletBinding()]
    param (
        [switch]$ResetCache
    )

    if (!$ResetCache) {
        if ($(get-cache platformtopology).Exists()) {
            return Read-Cache platformtopology
        }
    }

    $platformTopology = $null
    $platformTopology = $global:PlatformTopologyBase | Copy-Object

    if ($platformTopology.Components.Controller.Nodes.Keys.Count -gt 1) {
        throw "Multiple RMT controllers are not supported."
    }

    $controller = [string]$global:PlatformTopologyBase.Components.Controller.Nodes.Keys
    $agents = Get-RMTAgent -Quiet

    $platformTopology.Nodes.$controller += @{ Components = @{ Controller = @{ Instances = @{} } }  }
    if (![string]::IsNullOrEmpty($global:RegexPattern.PlatformTopology.Alias.Match)) {
        if ($controller -match $RegexPattern.PlatformTopology.Alias.Match) {
            $ptAlias = ""
            foreach ($i in $global:RegexPattern.PlatformTopology.Alias.Groups) {
                $ptAlias += $Matches[$i]
            }
            $platformTopology.Alias.($ptAlias) = $controller
        }
    }

    foreach ($agent in $agents) {
        $platformTopology.Components.Agents.Nodes += @{ $agent.Name = @{ Instances = @{} } }
        if (![string]::IsNullOrEmpty($global:RegexPattern.PlatformTopology.Alias.Match)) {
            if ($agent.Name -match $RegexPattern.PlatformTopology.Alias.Match) {
                $ptAlias = ""
                foreach ($i in $global:RegexPattern.PlatformTopology.Alias.Groups) {
                    $ptAlias += $Matches[$i]
                }
                $platformTopology.Alias.($ptAlias) = $agent.Name
            }
        }
    }

    if ($platformTopology.Nodes) {
        $platformTopology | Write-Cache platformtopology
    }

    return $platformTopology

}
Set-Alias -Name ptInit -Value Initialize-PlatformTopology -Scope Global

#endregion TOPOLOGY
#region PLATFORM INFO

function global:Get-PlatformInfo {

    [CmdletBinding()]
    param ()

    $version = Get-RMTVersion
    $global:Platform.Version = $version.ProductVersion
    $global:Platform.Build = $version.BuildVersion
    if ($global:Platform.DisplayName -notlike "*$($global:Platform.Version)*") {
        $global:Platform.DisplayName += " " + $global:Platform.Version
    }
    
    return

}
Set-Alias -Name ptInfo -Value Get-PlatformInfo -Scope Global

#endregion PLATFORM INFO
#region SERVICE

function global:Get-PlatformService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $global:PlatformTopologyBase.Components.Controller.Nodes.Keys,
        [Parameter(Mandatory=$false)][string]$View
        # [switch]$ResetCache
    )

    # if ($(get-cache platformservices).Exists() -and !$ResetCache) {
    #     $platformServicesCache = Read-Cache platformservices -MaxAge $(New-TimeSpan -Minutes 1)
    #     if ($platformServicesCache) {
    #         $platformServices = $platformServicesCache
    #         return $platformServices
    #     }
    # }

    $platformServices =
        foreach ($node in $ComputerName) {  

            $cimSession = New-CimSession -ComputerName $node -Credential (Get-Credentials "localadmin-$($Platform.Instance)")

            $nodeRole = ""
            if ($node -in $global:PlatformTopologyBase.Components.Controller.Nodes.Keys) {
                $nodeRole = "Controller"
            }
            else {
                $nodeRole = "Agents"
            }
            foreach ($serviceName in $global:PlatformTopologyBase.Components.$nodeRole.Services) {

                # $service = Get-Service -Name $serviceName
                $service = Get-CimInstance -ClassName Win32_Service -CimSession $cimSession -Property * | Where-Object {$_.Name -eq $serviceName} 

                @(
                    [PlatformCim]@{
                        Name = $service.Name
                        DisplayName = $service.DisplayName
                        Class = "Service"
                        Node = $node
                        Required = $true
                        Status = $service.State
                        StatusOK = @("Running")
                        IsOK = @("Running").Contains($service.State)
                        Instance = $service
                        Component = $nodeRole
                    }
                )
            }

            Remove-CimSession $cimSession

        }

    # $platformServices | Write-Cache platformservices

    return $platformServices | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)
}

#endregion SERVICE
#region STATUS

function global:IsRMTEnvironmentOK {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$EnvironmentIdentifier
    )

    return (Get-RMTEnvironmentStatus $EnvironmentIdentifier).RollupStatus -eq "Running"

}

function global:Get-RMTTableauServerStatus {

    [CmdletBinding()]
    param (
        # [Parameter(Mandatory=$false)][string]$EnvironmentIdentifier,
        [Parameter(Mandatory=$true)][Alias("EnvironmentIdentifier")][object]$Environment,
        [switch]$Quiet
    )

    if ($Environment.GetType().Name -eq "String") {
        $Environment = Get-RMTEnvironments -EnvironmentIdentifier $Environment
    }

    $message = "<Tableau Server $($Environment.Identifier) <.>48> PENDING"
    Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $initialNode = $Environment.RepoServer

    $tsStatus = $null

    $tableauServerStatus = [PSCustomObject]@{
        Name = $Environment.Identifier
        IsOK = $false
        RollupStatus = ""
        TableauServer = $null
        Environment = $Environment
    }

    try{

        Initialize-TsmApiConfiguration -Server $initialNode
        $tsStatus = Get-TableauServerStatus -ResetCache

    }
    catch {

        $message = "$($emptyString.PadLeft(8,"`b")) FAILURE"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red

        return $tableauServerStatus

    }

    $tableauServerStatus.IsOK = $TableauServerStatusOK.Contains($tsStatus.RollupStatus)
    $tableauServerStatus.RollupStatus = $tsStatus.RollupStatus
    $tableauServerStatus.TableauServer = $tsStatus

    $message = "$($emptyString.PadLeft(8,"`b")) $($tableauServerStatus.RollupStatus.ToUpper())"
    $messageColor = switch ($tableauServerStatus.RollupStatus) {
        "Starting" { "DarkYellow" }
        default {
            $tableauServerStatus.IsOK ? "DarkGreen" : "Red"
        }
    }
    Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor $messageColor

    return $tableauServerStatus

}

function global:Get-RMTStatus {

    [CmdletBinding()]
    param (
        [switch]$ResetCache,
        [switch]$Quiet
    )
    
    if ((get-cache rmtstatus).Exists() -and !$ResetCache) {
        $rmtStatus = Read-Cache rmtstatus -MaxAge $(New-TimeSpan -Seconds 60)
        if ($rmtStatus) {
            return $rmtStatus
        }
    }

    $rmtStatus = [PSCustomObject]@{
        IsOK = $true
        RollupStatus = ""
        ControllerStatus = $null
        AgentStatus = @()
        EnvironmentStatus = @()
    }

    Write-Host+ -Iff $(!$Quiet) -MaxBlankLines 1
    $message = "<Getting RMT Status <.>48> PENDING"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -Indent 2

    #region Controller

        $controller = Get-RMTController -Quiet:$Quiet.IsPresent
        $rmtStatus.IsOK = $rmtStatus.IsOK -and $controller.IsOK
        $rmtStatus.ControllerStatus = [PSCustomObject]@{
            Name = $controller.Name
            IsOK = $controller.IsOK
            RollupStatus = $controller.RollupStatus
            Controller = $controller
        }

    #endregion Controller

    if ($controller.IsOK) {
    
        #region Agents

            $agents = Get-RMTAgent -Controller $controller -Quiet:$Quiet.IsPresent

            foreach ($agent in $agents) {

                $agentStatus = [PSCustomObject]@{
                    IsOK = $true
                    RollupStatus = ""
                    ConnectionIsOK = $agent.IsConnected -eq "True"
                    ServiceIsOK = ($agent.Services.Status | Sort-Object -Unique) -eq $global:PlatformStatusOK
                    Agent = $agent
                    Name = $agent.Name
                    EnvironmentIdentifier = $agent.EnvironmentIdentifier
                }
                $agentStatus.IsOK = $agentStatus.ConnectionIsOK -and $agentStatus.ServiceIsOK
                
                if ($agentStatus.ConnectionIsOK -and $agentStatus.ServiceIsOK) {
                    $agentStatus.RollupStatus = "Connected"
                }
                elseif (!$agentStatus.ConnectionIsOK -and $agentStatus.ServiceIsOK) {
                    $agentStatus.RollupStatus = "Connecting"
                }
                elseif (!$agentStatus.ConnectionIsOK -or !$agentStatus.ServiceIsOK) {
                    $agentStatus.RollupStatus = "Disconnected"
                }

                $rmtStatus.IsOK = $rmtStatus.IsOK -and $agentStatus.IsOK
                $rmtStatus.AgentStatus += $agentStatus

            }

        #endregion Agents
        #region Environments

            $environments = Get-RMTEnvironments -Controller $controller -Quiet:$Quiet.IsPresent

            Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -Indent 2

            foreach ($environment in $environments) {

                $message = "<$($environment.Identifier) <.>48> PENDING"
                Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -Indent 2

                $environmentStatus = [PSCustomObject]@{
                    Name = $environment.Identifier
                    IsOK = $true
                    RollupStatus = ""
                    Environment = $environment
                    AgentStatus = $rmtStatus.AgentStatus | Where-Object {$_.EnvironmentIdentifier -eq $environment.Identifier}
                    TableauServer = Get-RMTTableauServerStatus $environment -Quiet
                }

                foreach ($agentStatus in $environmentStatus.AgentStatus) {

                    $message = "<$($agentStatus.Name) <.>32> $($agentStatus.RollupStatus.ToUpper())"
                    Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$($agentStatus.IsOK ? "DarkGreen" : "Red")

                    $environmentStatus.IsOK = $environmentStatus.IsOK -and $agentStatus.IsOK

                }
                $environmentStatus.RollupStatus = $environmentStatus.IsOK ? "Connected" : "Degraded"

                Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -Indent -2
                $message = "<$($environment.Identifier) <.>48> $($environmentStatus.RollupStatus.ToUpper())"
                Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$($environmentStatus.IsOK ? "DarkGreen" : "Red")

                $rmtStatus.IsOK = $rmtStatus.IsOK -and $environmentStatus.IsOK
                $rmtStatus.EnvironmentStatus += $environmentStatus
            }

            Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -Indent -2

        #endregion Environments

        $rmtStatus.RollupStatus = $rmtStatus.IsOK ? "Connected" : "Degraded"

    }
    else {
        $rmtStatus.IsOK = $controller.IsOK
        $rmtStatus.RollupStatus = $controller.RollupStatus
    }

    Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -Indent -2

    $message = "<Getting RMT Status <.>48> SUCCESS"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
    Write-Host+ -Iff $(!$Quiet)


    $rmtStatus | Write-Cache rmtstatus

    return $rmtStatus

}
Set-Alias -Name rmtStat -Value Get-RMTStatus -Scope Global
Set-Alias -Name rmtStatus -Value Get-RMTStatus -Scope Global

function global:Get-PlatformStatusRollup {
    
    [CmdletBinding()]
    param (
        [switch]$ResetCache
    )

    $params = @{}
    if ($ResetCache) { $params = @{ ResetCache = $ResetCache } }
    $tableauRMTStatus = Get-RMTStatus @params

    $issues = $null

    return $tableauRMTStatus.IsOK, $tableauRMTStatus.RollupStatus, $issues, $tableauRMTStatus
}

function global:Build-StatusFacts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$true)][string]$Node,
        [switch]$ShowAll
    )

    $controller = $PlatformStatus.StatusObject.ControllerStatus.Controller

    $facts = @()
    if (!$controller.IsOK -or $ShowAll) {
        $facts += foreach ($service in $controller.Services) {
            $abbrev = $service.Name -replace "TableauResourceMonitoringTool",($service.Name -eq "TableauResourceMonitoringTool" ? "Controller" : "")
            if ($abbrev) {
                @{
                    name = "$abbrev"
                    value = "Service $($service.Status.ToLower())"
                }
            }
        }
    }
    foreach ($environmentStatus in $PlatformStatus.StatusObject.EnvironmentStatus) {
        $facts += @(
            @{
                name = "$($environmentStatus.Name)"
                value = "$($environmentStatus.RollupStatus.ToUpper())"
            }
        )
        if (!$environmentStatus.IsOK -or $ShowAll) {
            $facts += foreach ($agentStatus in $environmentStatus.AgentStatus) {
                @{
                    name = "$($agentStatus.Name)"
                    value = "Agent $($agentStatus.RollupStatus)"
                }
            }
        }
    }

    return $facts
}

#endregion STATUS
#region SERVICE

function global:Request-RMTService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Alias = $Name,
        [Parameter(Mandatory=$true)][ValidateSet("Enable","Disable")][string]$Command,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason
    )

    $StartupType = switch ($Command) {
        "Enable" { "Automatic" }
        "Disable" { "Disabled" }
    }

    foreach ($node in $ComputerName) {

        $message = "<$Command $Alias on $node <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        Set-PlatformService -ComputerName $ComputerName -Name $Name -StartupType $StartupType

        $psSession = Get-PSSession+ -ComputerName $node -ErrorAction SilentlyContinue
        $response = Invoke-Command -Session $psSession {
            Get-Service -Name $using:Name -ErrorAction SilentlyContinue           
        }

        $result = $response.StartType -eq $StartupType ? "Success" : "Failure"

        $logEntryType = $result -eq "Success" ? "Information" : "Error" 
        Write-Log -Context $Context -Action $command -Target "$node\$Alias" -EntryType $logEntryType -Status $result -Force # -Data $Name 

        $message = "$($emptyString.PadLeft(8,"`b")) $($result.ToUpper())$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($result -eq "SUCCESS" ? "DarkGreen" : "DarkRed" )

    }

    return

}

#endregion SERVICE
#region COMMAND/CONTROL

function global:Request-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][ValidateSet("Stop","Start")][string]$Command,
        [Parameter(Mandatory=$true)][ValidateSet("Controller","Agent")][string]$Target,
        [Parameter(Mandatory=$true)][string[]]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason
    )

    $rmtAdmin = switch ($Target) {
        "Controller" { "$($global:Platform.InstallPath)\$global:RMTControllerAlias\rmtAdmin" }
        default { "$($global:Platform.InstallPath)\$Target\rmtAdmin" }
    }

    $verbing = switch ($Command) {
        "Stop" {"Stopping"}
        "Start" {"Starting"}
    }
    $successPattern = "(successfully|currently "
    $successPattern += switch ($Command) {
        "Stop" {"stopped"}
        "Start" {"running"}
    }
    $successPattern += ")"

    foreach ($node in $ComputerName) {
    
        $message = "<$verbing RMT $Target on $node <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        
        $psSession = Get-PSSession+ -ComputerName $node -ErrorAction SilentlyContinue
        $response = Invoke-Command -Session $psSession {
            . $using:rmtAdmin $using:Command
        }

        $result = ($response | Select-String -Pattern $successPattern -Quiet) ? "Success" : "Failure"

        $logEntryType = $result -eq "Success" ? "Information" : "Error" 
        Write-Log -Context $Context -Action $Command -Target "$node\RMT $Target" -EntryType $logEntryType -Status $result -Force

        $message = "$($emptyString.PadLeft(8,"`b")) $($result.ToUpper())$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($result -eq "SUCCESS" ? "DarkGreen" : "DarkRed" )
    
    }

}

function global:Request-RMTController {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][ValidateSet("Stop","Start")][string]$Command,
        [Parameter(Mandatory=$true)][string[]]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason
    )

    Write-Host+
    $message = "<$($Command.ToUpper()) RMT Controller <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    Write-Host+ -SetIndentGlobal -Indent 2

    $message = "Controller"
    Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
    Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

    Request-Platform -Command $Command -Target "Controller" -ComputerName $ComputerName -Context $Context -Reason $Reason

    Write-Host+ -SetIndentGlobal -Indent -2

    Write-Host+
    $message = "<$($Command.ToUpper()) RMT Controller <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
    Write-Host+

}

function global:Stop-RMTController {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $global:PlatformTopologyBase.Components.Controller.Nodes.Keys,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop RMT Controller"
    )

    Request-RMTController -Command "Stop" -ComputerName $ComputerName -Context $Context -Reason $Reason

}

function global:Start-RMTController {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $global:PlatformTopologyBase.Components.Controller.Nodes.Keys,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start RMT Controller"
    )

    Request-RMTController -Command "Start" -ComputerName $ComputerName -Context $Context -Reason $Reason
    
}

function global:Restart-RMTController {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $global:PlatformTopologyBase.Components.Controller.Nodes.Keys,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$true)][string]$Reason
    )
    
    Stop-RMTController -ComputerName $ComputerName -Context $Context -Reason $Reason
    Start-RMTController -ComputerName $ComputerName -Context $Context -Reason $Reason

}

function global:Request-RMTAgent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][ValidateSet("Stop","Start")][string]$Command,
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason,
        [switch]$IfTableauServerIsRunning,
        [switch]$DisableAgentService
    )

    if ($ComputerName -and $EnvironmentIdentifier) {
        throw "The `$ComputerName/`$Agent and `$EnvironmentIdentifier parameters cannot be used together"
    }

    Write-Host+ -MaxBlankLines 1

    $rmtStatus = Get-RMTStatus
    $controller = $rmtStatus.ControllerStatus.Controller
    $agents = $rmtStatus.AgentStatus.Agent
    $environments = $rmtStatus.EnvironmentStatus.Environment

    if (!$controller.IsOK) {
        $message = "<$($Command.ToUpper()) RMT Agents <.>48> FAILURE"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Red
        $message = "/","CONTROLLER:$($controller.RollupStatus.ToUpper())"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,Red
        return
    }

    if (!$ComputerName -and !$EnvironmentIdentifier) {
        $EnvironmentIdentifier = $environments.Identifier
    }
    elseif ($ComputerName) {
        $EnvironmentIdentifier = ($agents | Where-Object {$_.Name -in $ComputerName}).EnvironmentIdentifier | Sort-Object -Unique
    }
    elseif (!$ComputerName) {
        $ComputerName = ($rmtStatus.EnvironmentStatus | Where-Object ($_.EnvironmentIdentifier -in $EnvironmentIdentifier)).AgentStatus.Agent
    }

    $environments = $environments | Where-Object {$_.Identifier -in $EnvironmentIdentifier}
    # $agents = $environments.AgentStatus.Agent
    
    Write-Host+
    $message = "<$($Command.ToUpper()) RMT Agents <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    Write-Host+ -SetIndentGlobal -Indent 2

    $agentsCompleted = @()
    $environsCompleted = @()
    $agentsSkipped = @()
    $environsSkipped = @()

    foreach ($environment in $environments) {

        $message = "$($environment.Identifier)"
        Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
        Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

        if ($ComputerName) {
            $targetAgents = $agents | Where-Object {$_.Name -in $ComputerName -and $_.EnvironmentIdentifier -eq $environment.Identifier}
        }
        else {
            $targetAgents = $agents | Where-Object {$_.EnvironmentIdentifier -eq $environment.Identifier}
        }

        if ($IfTableauServerIsRunning) {
            $tableauServerStatus = Get-RMTTableauServerStatus $environment
            if (!$tableauServerStatus.IsOK) { 
                $environsSkipped += $environment 
                $agentsSkipped += $targetAgents
            }                 
        }
        if ($environment.Identifier -in $environsSkipped.Identifier) {
            foreach ($agent in $targetAgents) {
                $message = "<$($Command -eq "Stop" ? "Disable" : "Enable") RMT Agent on $($agent.Name) <.>48> SKIPPED"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                $message = "<$Command RMT Agent on $($agent.Name) <.>48> SKIPPED"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            }
        }
        else {
            $environsCompleted += $environment
            $agentsCompleted += $targetAgents

            # enable agent service before start
            if ($Command -eq "Start") {
                Enable-RMTAgentService -Context $Context -Computername $targetAgents.Name -Reason $Reason
            }

            # start/stop agent service
            Request-Platform -Command $Command -Target "Agent" -ComputerName $targetAgents.Name -Context $Context -Reason $Reason

            # # disable agent service after stop
            if ($Command -eq "Stop" -and $DisableAgentService) {
                Disable-RMTAgentService -Context $Context -Computername $targetAgents.Name -Reason $Reason
            }

        }

        Write-Host+

    }

    Write-Host+ -SetIndentGlobal -Indent -2

    $message = "<$($Command.ToUpper()) RMT Agents <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
    Write-Host+

    $result = @{
        Command = $Command
        EnvironmentIdentifier = $EnvironmentIdentifier
        ComputerName = $ComputerName
        Completed = @{
            Environments = $environsCompleted
            Agents = $agentsCompleted
        }
        Skipped = @{
            Environments = $environsSkipped
            Agents = $agentsSkipped
        }
        RmtStatusBefore = $rmtStatus
        RmtStatusAfter = Get-RMTStatus -ResetCache
    }

    return $Command -eq "Start" ? $result : $null

}  

function global:Disable-RMTAgentService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Disable RMT Agent Service"
    )

    Set-CursorInvisible

    $params = @{ 
        Command = "Disable"
        Name = "TableauResourceMonitoringToolAgent"
        Alias= "RMT Agent"
    }
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    $result = Request-RMTService @params

    Set-CursorVisible

    return $result

}

function global:Enable-RMTAgentService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Enable RMT Agent Service"
    )

    Set-CursorInvisible

    $params = @{ 
        Command = "Enable"
        Name = "TableauResourceMonitoringToolAgent"
        Alias= "RMT Agent"
    }
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    $result = Request-RMTService @params

    Set-CursorVisible

    return $result

}


function global:Stop-RMTAgent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop RMT Agent",
        [switch]$DisableAgentService
    )

    Set-CursorInvisible

    $params = @{ Command = "Stop"}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($DisableAgentService) { $params += @{ DisableAgentService = $true } }
    $result = Request-RMTAgent @params

    Set-CursorVisible

    return $result

}
Set-Alias -Name Stop-RMTEnvironments -Value Stop-RMTAgent -Scope Global

function global:Start-RMTAgent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start RMT Agents",
        [switch]$IfTableauServerIsRunning
    )

    if ($Context -and $Context -like "Azure*") {
        Write-Log -Context $Context -Action "Start-PlatformTask -Id StartRMTAgents" -Target "Platform" -Message $Reason -Force
        $isStarted = Start-PlatformTask -Id StartRMTAgents -Quiet
        $isStarted | Out-Null
        return
    }

    Set-CursorInvisible

    $params = @{ Command = "Start"}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Request-RMTAgent @params

    Set-CursorVisible

    # $messageStatus = Send-PlatformStatusMessage -MessageType "Alert"
    # $messageStatus | Out-Null
    
    return $result

}
Set-Alias -Name Start-RMTEnvironments -Value Start-RMTAgent -Scope Global

function global:Restart-RMTAgent {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$true)][string]$Reason,
        [switch]$IfTableauServerIsRunning
    )

    Set-CursorInvisible
    
    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    Stop-RMTAgent @params

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Start-RMTAgent @params

    Set-CursorVisible

    return $result

}

function global:Stop-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop platform",
        [switch]$DisableAgentService
    )

    Set-CursorInvisible

    # Get-RMTStatus -ResetCache | Out-Null
    $platformStatus = Get-PlatformStatus -ResetCache

    Set-PlatformEvent -Event "Stop" -Context $Context -EventReason $Reason -EventStatus $PlatformEventStatus.InProgress -PlatformStatus $platformStatus

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($DisableAgentService) { $params += @{ DisableAgentService = $true } }
    
    Stop-RMTAgent @params

    $platformStatus = Get-PlatformStatus -ResetCache

    Stop-RMTController @params

    Set-PlatformEvent -Event "Stop" -Context $Context -EventReason $Reason -EventStatus $PlatformEventStatus.Completed -PlatformStatus $platformStatus

    Set-CursorVisible

}

function global:Start-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start platform",
        [switch]$IfTableauServerIsRunning
    )

    Set-CursorInvisible

    # Get-RMTStatus -ResetCache | Out-Null
    $platformStatus = Get-PlatformStatus -ResetCache

    Set-PlatformEvent -Event "Start" -Context $Context -EventReason $Reason -EventStatus $PlatformEventStatus.InProgress -PlatformStatus $platformStatus

    # preflight checks
    Update-Preflight

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    Start-RMTController @params

    $platformStatus = Get-PlatformStatus -ResetCache

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Start-RMTAgent @params
    $result | Out-Null

    # postflight checks
    Confirm-PostFlight

    Set-PlatformEvent -Event "Start" -Context $Context -EventReason $Reason -EventStatus $PlatformEventStatus.Completed -PlatformStatus $platformStatus

    Set-CursorVisible

}

function global:Restart-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Restart platform",
        [switch]$IfTableauServerIsRunning
    )

    Set-CursorInvisible
    
    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    Stop-Platform @params

    Write-Host+

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    Start-Platform @params

    Set-CursorVisible

}

function global:Show-PlatformStatus {

    [CmdletBinding()]
    param (
        [switch]$BuildVersion
    )

    Write-Host+ -ResetAll

    $rmtStatus = Get-RMTStatus -ResetCache -Quiet

    $controller = $rmtStatus.ControllerStatus
    $environments = $rmtStatus.EnvironmentStatus

    Write-Host+
    $message = $global:Platform.DisplayName
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
    Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
    Write-Host+

    # $message =  "Controller"
    # Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
    # Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
    # Write-Host+
    # Write-Host+ -SetIndentGlobal -Indent 2

    $message = "<Controller\$($controller.Name) <.>56> $($controller.RollupStatus.ToUpper())"
    Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($controller.IsOK ? "DarkGreen" : "Red")
    Write-Host+ -SetIndentGlobal -Indent 2
    if ($BuildVersion) {
        $message = "<BuildVersion <.>56> $($controller.Controller.BuildVersion)"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray
    }
    # Write-Host+ -NoTrace -NoTimestamp "Services" -ForegroundColor DarkGray
    # Write-Host+ -SetIndentGlobal -Indent 2
    foreach ($service in $controller.Controller.Services) {
        $message = "<service\$($service.Name) <.>56> $($service.Status.ToUpper())"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,($service.IsOK ? "DarkGreen" : "Red")
    }
    # Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+
    
    foreach ($environment in $environments) {

        $message = "Environment\$($environment.Name)"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
        Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
        Write-Host+
        Write-Host+ -SetIndentGlobal -Indent 2

        # Write-Host+ -NoTrace -NoTimestamp "Tableau Server"
        # Write-Host+ -SetIndentGlobal -Indent 2
        $tableauServer = $environment.TableauServer
        $message = "<TableauServer\$($tableauServer.Name) <.>56> $($tableauServer.RollupStatus.ToUpper())"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($tableauServer.IsOK ? "DarkGreen" : "Red")
        # Write-Host+ -SetIndentGlobal -Indent -2

        Write-Host+
        
        foreach ($agent in $environment.AgentStatus.Agent) {

            # Write-Host+ -NoTrace -NoTimestamp "Agent"
            # Write-Host+ -SetIndentGlobal -Indent 2
            
            $agentStatus = $agent.IsConnected -eq "True" ? ($agent.Services.Status -eq "Running" ? "Connected" : "Connecting") : "Degraded"
            $message = "<Agent\$($agent.Name) <.>56> $($agentStatus.ToUpper())"
            $agentStatusColor = switch ($agentStatus) {
                "Connected" { "DarkGreen" }
                "Connecting" { "DarkYellow" }
                "Degraded" { "Red" }
            }
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,$agentStatusColor
            Write-Host+ -SetIndentGlobal -Indent 2
            if ($BuildVersion) {
                $message = "<BuildVersion <.>56> $($agent.BuildVersion)"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray
            }
            # Write-Host+ -NoTrace -NoTimestamp "Services" -ForegroundColor DarkGray
            # Write-Host+ -SetIndentGlobal -Indent 2
            foreach ($service in $agent.Services) {
                $message = "<Service\$($service.Name) <.>56> $($service.Status.ToUpper())"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,($service.IsOK ? "DarkGreen" : "Red")
            }
            # Write-Host+ -SetIndentGlobal -Indent -2
            Write-Host+ -SetIndentGlobal -Indent -2

            Write-Host+

        }

        Write-Host+ -SetIndentGlobal -Indent -2
        Write-Host+

    }

    Write-Host+ -ResetAll

}

#endregion COMMAND/CONTROL