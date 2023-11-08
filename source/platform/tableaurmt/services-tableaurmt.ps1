#region TOPOLOGY

function script:Get-RMTRole {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    if ($ComputerName -in (pt components.controller.nodes -k)) {return "Controller"}
    if ($ComputerName -in (pt components.agents.nodes -k)) {return "Agent"}

    throw "Node `"$ComputerName`" is not part of this platform's topology."

}

function global:Initialize-PlatformTopology {

    [CmdletBinding()]
    param (
        [switch]$ResetCache
    )

    if (!$ResetCache) {
        if ($(Get-Cache platformtopology).Exists) {
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
            $platformTopology.Alias.$ptAlias = $controller
            $platformTopology.Alias.$controller = $controller
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
                $platformTopology.Alias.$ptAlias = $agent.Name
                $platformTopology.Alias.$($agent.Name) = $agent.Name
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
    param (
        [switch][Alias("Update")]$ResetCache
    )

    if (!$ResetCache) {
        if ($(Get-Cache platforminfo).Exists) {
            $platformInfo = Read-Cache platforminfo 
            if ($platformInfo) {
                $controllerInfo = $platformInfo | Where-Object {$_.Role -eq "Controller"}
                $global:Platform.Version = $controllerInfo.Version
                $global:Platform.Build = $controllerInfo.Build
                $global:Platform.DisplayName = $global:Platform.Name + " " + $controllerInfo.Version
                return
            }
        }
    }

    $platformInfo = @()

    $prerequisiteTestResults = Test-Prerequisites -Type "Platform" -Id "TableauRMT" -PrerequisiteType Initialization -Quiet
    $postgresqlPrerequisiteTestResult = $prerequisiteTestResults.Prerequisites | Where-Object {$_.id -eq "TableauResourceMonitoringToolPostgreSQL"}
    if (!$postgresqlPrerequisiteTestResult.Pass) { 
        Write-Host+ -NoTrace "The $($postgresqlPrerequisiteTestResult.Id) $($postgresqlPrerequisiteTestResult.Type) is $($postgresqlPrerequisiteTestResult.Status.ToUpper())" -ForegroundColor DarkYellow
        Write-Host+ -NoTrace "Unable to query the RMT database for updated platform information" -ForegroundColor DarkYellow
        return 
    }

    $controllerInfo = Get-RMTVersion
    $global:Platform.Version = $controllerInfo.ProductVersion
    $global:Platform.Build = $controllerInfo.BuildVersion
    if ($global:Platform.DisplayName -notlike "*$($global:Platform.Version)*") {
        $global:Platform.DisplayName += " " + $global:Platform.Version
    }

    $platformInfo += $controllerInfo
    foreach ($node in (pt components.agents.nodes -k)) {
        $platformInfo += Get-RMTVersion $node
    }
    $platformInfo | Write-Cache platforminfo

    return

}
Set-Alias -Name ptInfo -Value Get-PlatformInfo -Scope Global

#endregion PLATFORM INFO
#region SERVICE

function global:Get-PlatformServices {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $global:PlatformTopologyBase.Components.Controller.Nodes.Keys,
        [Parameter(Mandatory=$false)][string]$View
        # [switch]$ResetCache
    )

    # if ($(Get-Cache platformservices).Exists -and !$ResetCache) {
    #     $platformServicesCache = Read-Cache platformservices -MaxAge $(New-TimeSpan -Minutes 1)
    #     if ($platformServicesCache) {
    #         $platformServices = $platformServicesCache
    #         return $platformServices
    #     }
    # }

    $platformServices =
        foreach ($node in $ComputerName) {  

            $cimSession = New-CimSession -ComputerName $node -Credential (Get-Credentials "localadmin-$($global:Platform.Instance)")

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
        $Environment = Get-RMTEnvironment -EnvironmentIdentifier $Environment
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

        $message = "$($emptyString.PadLeft(10,"`b")) FAILURE"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red

        return $tableauServerStatus

    }

    $tableauServerStatus.IsOK = $TableauServerStatusOK.Contains($tsStatus.RollupStatus)
    $tableauServerStatus.RollupStatus = $tsStatus.RollupStatus
    $tableauServerStatus.TableauServer = $tsStatus

    $message = "$($emptyString.PadLeft(10,"`b")) $($tableauServerStatus.RollupStatus.ToUpper())"
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
    
    if ((Get-Cache rmtstatus).Exists -and !$ResetCache) {
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

    Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal +2

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

            $agents = Get-RMTAgent -Quiet:$Quiet.IsPresent

            foreach ($agent in $agents) {

                $agentStatus = [PSCustomObject]@{
                    IsOK = $true
                    RollupStatus = ""
                    ConnectionIsOK = $agent.IsConnected -eq "True"
                    ServiceIsOK = ($agent.Services.Status | Sort-Object -Unique) -eq $global:PlatformStatusOK
                    Agent = $agent
                    Name = $agent.Name
                    EnvironmentIdentifier = $agent.EnvironmentIdentifier
                    Version = $agent.ProductVersion
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

            $environments = Get-RMTEnvironment -Quiet:$Quiet.IsPresent

            Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal +2

            foreach ($environment in $environments) {

                $message = "<$($environment.Identifier) <.>48> PENDING"
                Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal +2

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

                Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -2
                $message = "<$($environment.Identifier) <.>48> $($environmentStatus.RollupStatus.ToUpper())"
                Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$($environmentStatus.IsOK ? "DarkGreen" : "Red")

                $rmtStatus.IsOK = $rmtStatus.IsOK -and $environmentStatus.IsOK
                $rmtStatus.EnvironmentStatus += $environmentStatus
            }

            Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -2

        #endregion Environments

        $rmtStatus.RollupStatus = $rmtStatus.IsOK ? "Connected" : "Degraded"

    }
    else {
        $rmtStatus.IsOK = $controller.IsOK
        $rmtStatus.RollupStatus = $controller.RollupStatus
    }

    Write-Host+ -Iff $(!$Quiet) -SetIndentGlobal -2

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
        [switch]$ResetCache,
        [switch]$Quiet
    )

    $params = @{}
    if ($ResetCache) { $params = @{ ResetCache = $ResetCache } }
    if ($Quiet) { $params = @{ Quiet = $Quiet } }
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

        $psSession = Use-PSSession+ -ComputerName $node -ErrorAction SilentlyContinue
        $response = Invoke-Command -Session $psSession {
            Get-Service -Name $using:Name -ErrorAction SilentlyContinue           
        }
        # Remove-PSSession $psSession

        $result = $response.StartType -eq $StartupType ? "Success" : "Failure"

        $logEntryType = $result -eq "Success" ? "Information" : "Error" 
        Write-Log -Action $command -Target "$node\$Alias" -EntryType $logEntryType -Status $result -Force # -Data $Name 

        $message = "$($emptyString.PadLeft(10,"`b")) $($result.ToUpper())$($emptyString.PadLeft(8," "))"
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
        
        $psSession = Use-PSSession+ -ComputerName $node -ErrorAction SilentlyContinue
        $response = Invoke-Command -Session $psSession {
            . $using:rmtAdmin $using:Command
        }
        # Remove-PSSession $psSession

        $result = ($response | Select-String -Pattern $successPattern -Quiet) ? "Success" : "Failure"

        $logEntryType = $result -eq "Success" ? "Information" : "Error" 
        Write-Log -Action $Command -Target "$node\RMT $Target" -EntryType $logEntryType -Status $result -Force

        $message = "$($emptyString.PadLeft(10,"`b")) $($result.ToUpper())$($emptyString.PadLeft(8," "))"
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

    Write-Host+ -SetIndentGlobal +2

    $message = "Controller"
    Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
    Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

    Request-Platform -Command $Command -Target "Controller" -ComputerName $ComputerName -Context $Context -Reason $Reason

    Write-Host+ -SetIndentGlobal -2

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

    Write-Host+ -SetIndentGlobal +2

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

    Write-Host+ -SetIndentGlobal -2

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
        Write-Log -Action "Start-PlatformTask -Id StartRMTAgents" -Target "Platform" -Message $Reason -Force
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

        $rmtStatus = Get-RMTStatus -ResetCache -Quiet
        $controller = $rmtStatus.ControllerStatus
        $agents = $rmtStatus.AgentStatus
        # $environments = $rmtStatus.EnvironmentStatus

        $_nodeId = 0
        $nodeStatus = @()
        # Platform
        # $nodeStatus +=  [PsCustomObject]@{
        #     NodeId = ""
        #     Node = $global:Platform.Instance
        #     Status = $controller.RollupStatus
        #     Role = "Platform"
        #     Version = $controller.Controller.ProductVersion
        # }
        # Controller
        $nodeStatus +=  [PsCustomObject]@{
            NodeId = $_nodeId
            Node = $controller.Name
            Status = $controller.RollupStatus
            Role = Get-RMTRole $controller.Name
            Version = $controller.Controller.ProductVersion
        }
        # Agents
        foreach ($agent in $agents) {
            $_nodeId = $_nodeId++
            $nodeStatus +=  [PsCustomObject]@{
                NodeId = $_nodeId
                Node = $agent.Name
                Status = $agent.RollupStatus
                Role = Get-RMTRole $agent.Name
                Version = $agent.Agent.ProductVersion
            }
        }

        $nodeStatus = $nodeStatus | Sort-Object -Property NodeId, Node

        foreach ($_nodeStatus in $nodeStatus) {
            $message = "<  $($_nodeStatus.Role) ($($_nodeStatus.Node))$($_nodeStatus.node -eq (pt components.Controller.nodes -k) ? "*" : $null) <.>38> $($_nodeStatus.Status)"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($_nodeStatus.Status)
        }
        # $nodeStatus | Sort-Object -Property Node | Format-Table -Property Role, Node, Status, Version

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

    Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)
    
    $message = "<$($global:Platform.Instance) Status <.>48> $($_platformStatusRollupStatus.ToUpper())"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

}

#endregion COMMAND/CONTROL
#region TESTS

    function global:Test-RepositoryAccess {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)][string[]]$ComputerName,
            [switch]$SSL
        )

        $hostMode = $SSL ? "hostssl" : "host"

        $leader = Format-Leader -Length 46 -Adjust ((("  Postgres Access").Length))
        Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray

        try {

            $templatePath = "$($global:Platform.InstallPath)\data\postgresql13\pg_hba.conf"
            $templateContent = [System.Collections.ArrayList](Get-Content -Path $templatePath)

            if ($templateContent) {
        
                Write-Host+ -NoTimestamp -NoTrace  " PENDING" -ForegroundColor DarkGray

                $subLeader = Format-Leader -Length 35 -Adjust ((("Updating pg_hba.conf").Length))
                Write-Host+ -NoTrace -NoNewLine "    Updating pg_hba.conf",$subLeader -ForegroundColor Gray,DarkGray

                $regionBegin = $templateContent.Trim().IndexOf("# region Overwatch")
                $regionEnd = $templateContent.Trim().IndexOf("# endregion Overwatch")

                $savedRows = @()

                if ($regionBegin -ne -1 -and $regionEnd -ne 1) {
                    for ($i = $regionBegin+1; $i -le $regionEnd-1; $i++) {
                        $savedRows += $templateContent[$i].Trim() -replace "host(?:ssl)?.*?\s", "$hostMode "
                    }
                    $templateContent.RemoveRange($regionBegin,$regionEnd-$regionBegin+2)
                }

                $newRows = $false
                foreach ($node in $ComputerName) {
                    $newRow = "$hostMode all readonly $(Get-IpAddress $node)/32 md5"
                    if ($savedRows -notcontains $newRow) {
                        $savedRows += $newRow
                        $newRows = $true
                    }
                }

                if ($newRows) {

                    if ($templateContent[-1].Trim() -ne "") { $templateContent.Add("") | Out-Null}
                    $templateContent.Add("# region Overwatch") | Out-Null
                    # $templateContent.Add("<#if pgsql.readonly.enabled >") | Out-Null
                    foreach ($row in $savedRows) {
                        $templateContent.Add($row) | Out-Null
                    }
                    # $templateContent.Add("</#if>") | Out-Null
                    $templateContent.Add("# endregion Overwatch") | Out-Null
                    $templateContent.Add("") | Out-Null
                    $templateContent | Set-Content -Path $templatePath

                }

                Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen
                Write-Log -Action "Test" -Target "pg_hba.conf" -Status "PASS"

                Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray
                Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen

            }
            else {
                
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
                Write-Log -Action "Test" -Target "pg_hba.conf" -Status "FAIL" -EntryType "Error" -Message "Invalid format"
                # throw "Invalid format"

                Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 

            }

        }
        catch {
        
            Write-Host+ -NoTimestamp -NoTrace  " FAIL" -ForegroundColor DarkRed 
            Write-Log -Action "Test" -Target "pg_hba.conf" -Status "FAIL" -EntryType "Error" -Message $_.Exception.Message
            # throw "$($_.Exception.Message)"
        
        }

    }

#region TESTS