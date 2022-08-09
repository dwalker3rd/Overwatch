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
        throw "Multiple Tableau RMT controllers are not supported."
    }

    $controller = [string]$global:PlatformTopologyBase.Components.Controller.Nodes.Keys
    $agents = Get-RMTAgents -Quiet

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

    try{
        Initialize-TsmApiConfiguration -Server $initialNode
        $tsStatus = Get-TableauServerStatus -ResetCache

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
    }
    catch {
        $message = "$($emptyString.PadLeft(8,"`b")) FAILURE"
        Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor Red
    }

    $tableauServerStatus = [PSCustomObject]@{
        Name = $Environment.Identifier
        IsOK = $TableauServerStatusOK.Contains($tsStatus.RollupStatus)
        RollupStatus = $tsStatus.RollupStatus
        TableauServer = $tsStatus
        Environment = $Environment
    }

    $message = "/","$($tableauServerStatus.RollupStatus.ToUpper())"
    Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,($tableauServerStatus.IsOK ? "DarkGreen" : "Red")

    return $tableauServerStatus

}

function global:Get-RMTStatus {

    [CmdletBinding()]
    param (
        [switch]$ResetCache
    )
    
    if ((get-cache rmtstatus).Exists() -and !$ResetCache) {
        $rmtStatus = Read-Cache rmtstatus -MaxAge $(New-TimeSpan -Seconds 60)
        if ($rmtStatus) {
            return $rmtStatus
        }
    }

    $controllerStatus = @{}
    $agentStatus = @{}
    $environmentStatus = @()

    Write-Host+ -MaxBlankLines 1
    $message = "<Getting Tableau RMT Status <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    Write-host+ -SetIndentGlobal -Indent 2

    #region Controller

        $controller = Get-RMTController -Quiet
        $controllerStatus = [PSCustomObject]@{
            Name = $controller.Name
            IsOK = $controller.IsOK
            RollupStatus = $controller.RollupStatus
            Controller = $controller
        }

    #endregion Controller

    if ($controller.IsOK) {
    
        #region Agents

            $agents = Get-RMTAgents -Controller $controller -Quiet
            $agentStatus = [PSCustomObject]@{
                IsOK = $true
                RollupStatus = ""
                Agents = $agents
            }

            foreach ($agent in $agents) {
                $agentStatus.IsOK = $agentStatus.IsOK -and $agent.IsConnected
            }
            $agentStatus.RollupStatus = $agentStatus.IsOK ? "Connected" : "Connection Issue"           

        #endregion Agents
        #region Environments

            $environments = Get-RMTEnvironments -Controller $controller
            foreach ($environment in $environments) {
                $environStatus = [PSCustomObject]@{
                    Name = $environment.Identifier
                    IsOK = $true
                    RollupStatus = ""
                    Environment = $environment
                    Agents = @()
                    TableauServer = $null
                }
                $environStatus.Agents = $agents | Where-Object {$_.EnvironmentIdentifier -eq $environment.Identifier}

                Write-Host+ -SetIndentGlobal -Indent 2
                $environStatus.TableauServer = Get-RMTTableauServerStatus $environment
                Write-Host+ -SetIndentGlobal -Indent -2

                foreach ($agent in $environStatus.Agents) {
                    $environStatus.IsOK = $environStatus.IsOK -and $agent.IsConnected
                }
                $environStatus.RollupStatus = $environStatus.IsOK ? "Connected" : "Connection Issue"
                $environmentStatus += $environStatus
            }

        #endregion Environments

    }

    Write-host+ -SetIndentGlobal -Indent -2

    $message = "<Getting Tableau RMT Status <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    $rmtStatus = [PSCustomObject]@{
        IsOK = $controllerStatus.IsOK
        RollupStatus = $controllerStatus.rollupStatus
        ControllerStatus = $controllerStatus
        AgentStatus = $agentStatus
        EnvironmentStatus = $environmentStatus
    }

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
    # $agents = $PlatformStatus.StatusObject.AgentStatus.Agents
    $environs = $PlatformStatus.StatusObject.EnvironmentStatus

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
    foreach ($environ in $environs) {
        $facts += @(
            @{
                name = "$($environ.Name)"
                value = "$($environ.RollupStatus -eq "Connected" ? "All agents connected" : "Agent[s] with a connection issue")"
            }
        )
        if (!$environ.IsOK -or $ShowAll) {
            $facts += foreach ($agent in $environ.Environment.Agents) {
                @{
                    name = "$($agent.Name)"
                    value = "Agent $($agent.IsConnected -eq "False" ? "connected" : "has a connection issue")"
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
    [Parameter(Mandatory=$true)][ValidateSet("Enable","Disable")][string]$Command
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
    Write-Log -Context $Product.Id -Action $command -Target "$node\$Alias" -EntryType $logEntryType -Status $result -Data $Name -Force

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
        Write-Log -Context $Product.Id -Action $Command -Target "$node\RMT $Target" -EntryType $logEntryType -Status $result -Force

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
    $message = "<$($Command.ToUpper()) Tableau RMT Controller <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    Write-Host+ -SetIndentGlobal -Indent 2

    $message = "Controller"
    Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
    Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

    Request-Platform -Command $Command -Target "Controller" -ComputerName $ComputerName -Context $Context -Reason $Reason

    Write-Host+ -SetIndentGlobal -Indent -2

    Write-Host+
    $message = "<$($Command.ToUpper()) Tableau RMT Controller <.>48> SUCCESS"
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

function global:Request-RMTAgents {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][ValidateSet("Stop","Start")][string]$Command,
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason,
        [switch]$IfTableauServerIsRunning
    )

    if ($ComputerName -and $EnvironmentIdentifier) {
        throw "The `$ComputerName/`$Agent and `$EnvironmentIdentifier parameters cannot be used together"
    }

    $rmtStatus = Get-RMTStatus
    $controller = $rmtStatus.ControllerStatus.Controller
    $agents = $rmtStatus.AgentStatus.Agents
    $environs = $rmtStatus.EnvironmentStatus.Environment

    if (!$controller.IsOK) {
        $message = "<$($Command.ToUpper()) Tableau RMT Agents <.>48> FAILURE"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Red
        $message = "/","CONTROLLER:$($controller.RollupStatus.ToUpper())"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,Red
        return
    }

    if (!$ComputerName -and !$EnvironmentIdentifier) {
        $EnvironmentIdentifier = $environs.Identifier
    }
    elseif ($ComputerName) {
        $EnvironmentIdentifier = ($agents | Where-Object {$_.Name -in $ComputerName}).EnvironmentIdentifier | Sort-Object -Unique
    }

    $environs = $environs | Where-Object {$_.Identifier -in $EnvironmentIdentifier}
    
    Write-Host+
    $message = "<$($Command.ToUpper()) Tableau RMT Agents <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    Write-Host+ -SetIndentGlobal -Indent 2

    $agentsCompleted = @()
    $environsCompleted = @()
    $agentsSkipped = @()
    $environsSkipped = @()

    foreach ($environ in $environs) {

        $message = "$($environ.Identifier)"
        Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
        Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

        $targetAgents = ![string]::IsNullOrEmpty($ComputerName) ? ($agents | Where-Object {$_.Name -in $ComputerName}) : ($agents | Where-Object {$_.EnvironmentIdentifier -eq $environ.Identifier})

        if ($IfTableauServerIsRunning) {
            $tableauServerStatus = Get-RMTTableauServerStatus $environ
            if (!$tableauServerStatus.IsOK) { 
                $environsSkipped += $environ 
                $agentsSkipped += $targetAgents
            }                 
        }
        if ($environ.Identifier -in $environsSkipped.Identifier) {
            foreach ($agent in $targetAgents) {
                $message = "<$($Command -eq "Stop" ? "Disable" : "Enable") Tableau RMT Agent on $($agent.Name) <.>48> SKIPPED"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                $message = "<$Command Tableau RMT Agent on $($agent.Name) <.>48> SKIPPED"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            }
        }
        else {
            $environsCompleted += $environ
            $agentsCompleted += $targetAgents
            Request-RMTService -Command ($Command -eq "Stop" ? "Disable" : "Enable") -Name "TableauResourceMonitoringToolAgent" -Alias "Tableau RMT Agent" -Computername $targetAgents.Name
            Request-Platform -Command $Command -Target "Agent" -ComputerName $targetAgents.Name -Context $Context -Reason $Reason
        }

        Write-Host+

    }

    Write-Host+ -SetIndentGlobal -Indent -2

    $message = "<$($Command.ToUpper()) Tableau RMT Agents <.>48> SUCCESS"
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
    }

    return $Command -eq "Start" ? $result : $null

}  

function global:Stop-RMTAgents {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop RMT Agents"
    )

    Set-CursorInvisible

    $params = @{ Command = "Stop"}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    Request-RMTAgents @params

    Set-CursorVisible

}
Set-Alias -Name Stop-RMTEnvironments -Value Stop-RMTAgents -Scope Global

function global:Start-RMTAgents {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start RMT Agents",
        [switch]$IfTableauServerIsRunning
    )

    if ($Context -and $Context -like "Azure*") {
        Write-Log -Context "StartRMTAgents" -Action "Start-PlatformTask -Id StartRMTAgents" -Target "Platform" -Message $Reason -Force
        Start-PlatformTask -Id StartRMTAgents
        return
    }

    $params = @{ Command = "Start"}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Request-RMTAgents @params
    $result | Out-Null
    
    return

}
Set-Alias -Name Start-RMTEnvironments -Value Start-RMTAgents -Scope Global

function global:Restart-RMTAgents {

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
    Stop-RMTAgents @params

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Start-RMTAgents @params
    $result | Out-Null

    Set-CursorVisible

}

function global:Stop-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop platform"
    )

    Set-CursorInvisible

    # Get-RMTStatus -ResetCache | Out-Null
    $platformStatus = Get-PlatformStatus -ResetCache

    Set-PlatformEvent -Event "Stop" -Context $Context -EventReason $Reason -EventStatus $PlatformEventStatus.InProgress -PlatformStatus $platformStatus

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    
    Stop-RMTAgents @params

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
    $result = Start-RMTAgents @params
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
        [Parameter(Mandatory=$false)][string]$Reason,
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
    param ()

    $rmtStatus = Get-RMTStatus -ResetCache

    # $agents = $rmtStatus.AgentStatus
    $controller = $rmtStatus.ControllerStatus
    $environs = $rmtStatus.EnvironmentStatus

    Write-Host+
    $message = $global:Platform.DisplayName
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
    Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
    Write-Host+
    Write-Host+ -SetIndentGlobal -Indent 2

    Write-Host+ -NoTrace -NoTimestamp "Controller"
    Write-Host+ -SetIndentGlobal -Indent 2

    $message = "<$($controller.Name) <.>48> $($controller.RollupStatus)"
    Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($controller.IsOK ? "DarkGreen" : "Red")
    $message = "<BuildVersion <.>48> $($controller.Controller.BuildVersion)"
    Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray
    Write-Host+ -NoTrace -NoTimestamp "Services" -ForegroundColor DarkGray
    Write-Host+ -SetIndentGlobal -Indent 2
    foreach ($service in $controller.Controller.Services) {
        $message = "<$($service.Name) <.>48> $($service.Status)"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,($service.IsOK ? "DarkGreen" : "Red")
    }
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+
    
    foreach ($environ in $environs) {

        $message = $environ.Name
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
        Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
        Write-Host+

        Write-Host+ -SetIndentGlobal -Indent 2

        Write-Host+ -NoTrace -NoTimestamp "Tableau Server"
        Write-Host+ -SetIndentGlobal -Indent 2
        $tableauServer = $environ.TableauServer
        $message = "<$($tableauServer.Name) <.>48> $($tableauServer.RollupStatus)"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($tableauServer.IsOK ? "DarkGreen" : "Red")
        Write-Host+ -SetIndentGlobal -Indent -2

        Write-Host+
        
        foreach ($agent in $environ.Agents) {

            Write-Host+ -NoTrace -NoTimestamp "Agent"
            Write-Host+ -SetIndentGlobal -Indent 2
            
            $message = "<$($agent.Name) <.>48> $($agent.IsConnected -eq "True" ? "Connected" : "Connection Issue")"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($agent.IsConnected -eq "True" ? "DarkGreen" : "Red")
            $message = "<BuildVersion <.>48> $($agent.BuildVersion)"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray
            Write-Host+ -NoTrace -NoTimestamp "Services" -ForegroundColor DarkGray
            Write-Host+ -SetIndentGlobal -Indent 2
            foreach ($service in $agent.Services) {
                $message = "<$($service.Name) <.>48> $($service.Status)"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,($service.IsOK ? "DarkGreen" : "Red")
            }
            Write-Host+ -SetIndentGlobal -Indent -2
            Write-Host+ -SetIndentGlobal -Indent -2

            Write-Host+

        }
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
        throw "Multiple Tableau RMT controllers are not supported."
    }

    $controller = [string]$global:PlatformTopologyBase.Components.Controller.Nodes.Keys
    $agents = Get-RMTAgents -Quiet

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

    try{
        Initialize-TsmApiConfiguration -Server $initialNode
        $tsStatus = Get-TableauServerStatus -ResetCache

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
    }
    catch {
        $message = "$($emptyString.PadLeft(8,"`b")) FAILURE"
        Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor Red
    }

    $tableauServerStatus = [PSCustomObject]@{
        Name = $Environment.Identifier
        IsOK = $TableauServerStatusOK.Contains($tsStatus.RollupStatus)
        RollupStatus = $tsStatus.RollupStatus
        TableauServer = $tsStatus
        Environment = $Environment
    }

    $message = "/","$($tableauServerStatus.RollupStatus.ToUpper())"
    Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,($tableauServerStatus.IsOK ? "DarkGreen" : "Red")

    return $tableauServerStatus

}

function global:Get-RMTStatus {

    [CmdletBinding()]
    param (
        [switch]$ResetCache
    )
    
    if ((get-cache rmtstatus).Exists() -and !$ResetCache) {
        $rmtStatus = Read-Cache rmtstatus -MaxAge $(New-TimeSpan -Seconds 60)
        if ($rmtStatus) {
            return $rmtStatus
        }
    }

    $controllerStatus = @{}
    $agentStatus = @{}
    $environmentStatus = @()

    Write-Host+ -MaxBlankLines 1
    $message = "<Getting Tableau RMT Status <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    Write-host+ -SetIndentGlobal -Indent 2

    #region Controller

        $controller = Get-RMTController -Quiet
        $controllerStatus = [PSCustomObject]@{
            Name = $controller.Name
            IsOK = $controller.IsOK
            RollupStatus = $controller.RollupStatus
            Controller = $controller
        }

    #endregion Controller

    if ($controller.IsOK) {
    
        #region Agents

            $agents = Get-RMTAgents -Controller $controller -Quiet
            $agentStatus = [PSCustomObject]@{
                IsOK = $true
                RollupStatus = ""
                Agents = $agents
            }

            foreach ($agent in $agents) {
                $agentStatus.IsOK = $agentStatus.IsOK -and $agent.IsConnected
            }
            $agentStatus.RollupStatus = $agentStatus.IsOK ? "Connected" : "Connection Issue"           

        #endregion Agents
        #region Environments

            $environments = Get-RMTEnvironments -Controller $controller
            foreach ($environment in $environments) {
                $environStatus = [PSCustomObject]@{
                    Name = $environment.Identifier
                    IsOK = $true
                    RollupStatus = ""
                    Environment = $environment
                    Agents = @()
                    TableauServer = $null
                }
                $environStatus.Agents = $agents | Where-Object {$_.EnvironmentIdentifier -eq $environment.Identifier}

                Write-Host+ -SetIndentGlobal -Indent 2
                $environStatus.TableauServer = Get-RMTTableauServerStatus $environment
                Write-Host+ -SetIndentGlobal -Indent -2

                foreach ($agent in $environStatus.Agents) {
                    $environStatus.IsOK = $environStatus.IsOK -and $agent.IsConnected
                }
                $environStatus.RollupStatus = $environStatus.IsOK ? "Connected" : "Connection Issue"
                $environmentStatus += $environStatus
            }

        #endregion Environments

    }

    Write-host+ -SetIndentGlobal -Indent -2

    $message = "<Getting Tableau RMT Status <.>48> SUCCESS"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    $rmtStatus = [PSCustomObject]@{
        IsOK = $controllerStatus.IsOK
        RollupStatus = $controllerStatus.rollupStatus
        ControllerStatus = $controllerStatus
        AgentStatus = $agentStatus
        EnvironmentStatus = $environmentStatus
    }

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
    # $agents = $PlatformStatus.StatusObject.AgentStatus.Agents
    $environs = $PlatformStatus.StatusObject.EnvironmentStatus

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
    foreach ($environ in $environs) {
        $facts += @(
            @{
                name = "$($environ.Name)"
                value = "$($environ.RollupStatus -eq "Connected" ? "All agents connected" : "Agent[s] with a connection issue")"
            }
        )
        if (!$environ.IsOK -or $ShowAll) {
            $facts += foreach ($agent in $environ.Environment.Agents) {
                @{
                    name = "$($agent.Name)"
                    value = "Agent $($agent.IsConnected -eq "False" ? "connected" : "has a connection issue")"
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
    [Parameter(Mandatory=$true)][ValidateSet("Enable","Disable")][string]$Command
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
    Write-Log -Context $Product.Id -Action $command -Target "$node\$Alias" -EntryType $logEntryType -Status $result -Data $Name -Force

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
        Write-Log -Context $Product.Id -Action $Command -Target "$node\RMT $Target" -EntryType $logEntryType -Status $result -Force

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
    $message = "<$($Command.ToUpper()) Tableau RMT Controller <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    Write-Host+ -SetIndentGlobal -Indent 2

    $message = "Controller"
    Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
    Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

    Request-Platform -Command $Command -Target "Controller" -ComputerName $ComputerName -Context $Context -Reason $Reason

    Write-Host+ -SetIndentGlobal -Indent -2

    Write-Host+
    $message = "<$($Command.ToUpper()) Tableau RMT Controller <.>48> SUCCESS"
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

function global:Request-RMTAgents {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][ValidateSet("Stop","Start")][string]$Command,
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Context,
        [Parameter(Mandatory=$true)][string]$Reason,
        [switch]$IfTableauServerIsRunning
    )

    if ($ComputerName -and $EnvironmentIdentifier) {
        throw "The `$ComputerName/`$Agent and `$EnvironmentIdentifier parameters cannot be used together"
    }

    $rmtStatus = Get-RMTStatus
    $controller = $rmtStatus.ControllerStatus.Controller
    $agents = $rmtStatus.AgentStatus.Agents
    $environs = $rmtStatus.EnvironmentStatus.Environment

    if (!$controller.IsOK) {
        $message = "<$($Command.ToUpper()) Tableau RMT Agents <.>48> FAILURE"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Red
        $message = "/","CONTROLLER:$($controller.RollupStatus.ToUpper())"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,Red
        return
    }

    if (!$ComputerName -and !$EnvironmentIdentifier) {
        $EnvironmentIdentifier = $environs.Identifier
    }
    elseif ($ComputerName) {
        $EnvironmentIdentifier = ($agents | Where-Object {$_.Name -in $ComputerName}).EnvironmentIdentifier | Sort-Object -Unique
    }

    $environs = $environs | Where-Object {$_.Identifier -in $EnvironmentIdentifier}
    
    Write-Host+
    $message = "<$($Command.ToUpper()) Tableau RMT Agents <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    Write-Host+ -SetIndentGlobal -Indent 2

    $agentsCompleted = @()
    $environsCompleted = @()
    $agentsSkipped = @()
    $environsSkipped = @()

    foreach ($environ in $environs) {

        $message = "$($environ.Identifier)"
        Write-Host+ -NoTrace -NoSeparator $message -ForeGroundColor Gray
        Write-Host+ -NoTrace (Format-Leader -Character "-" -Length $message.Length -NoIndent)

        $targetAgents = ![string]::IsNullOrEmpty($ComputerName) ? ($agents | Where-Object {$_.Name -in $ComputerName}) : ($agents | Where-Object {$_.EnvironmentIdentifier -eq $environ.Identifier})

        if ($IfTableauServerIsRunning) {
            $tableauServerStatus = Get-RMTTableauServerStatus $environ
            if (!$tableauServerStatus.IsOK) { 
                $environsSkipped += $environ 
                $agentsSkipped += $targetAgents
            }                 
        }
        if ($environ.Identifier -in $environsSkipped.Identifier) {
            foreach ($agent in $targetAgents) {
                $message = "<$($Command -eq "Stop" ? "Disable" : "Enable") Tableau RMT Agent on $($agent.Name) <.>48> SKIPPED"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                $message = "<$Command Tableau RMT Agent on $($agent.Name) <.>48> SKIPPED"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            }
        }
        else {
            $environsCompleted += $environ
            $agentsCompleted += $targetAgents
            Request-RMTService -Command ($Command -eq "Stop" ? "Disable" : "Enable") -Name "TableauResourceMonitoringToolAgent" -Alias "Tableau RMT Agent" -Computername $targetAgents.Name
            Request-Platform -Command $Command -Target "Agent" -ComputerName $targetAgents.Name -Context $Context -Reason $Reason
        }

        Write-Host+

    }

    Write-Host+ -SetIndentGlobal -Indent -2

    $message = "<$($Command.ToUpper()) Tableau RMT Agents <.>48> SUCCESS"
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
    }

    return $Command -eq "Start" ? $result : $null

}  

function global:Stop-RMTAgents {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop RMT Agents"
    )

    Set-CursorInvisible

    $params = @{ Command = "Stop"}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    Request-RMTAgents @params

    Set-CursorVisible

}
Set-Alias -Name Stop-RMTEnvironments -Value Stop-RMTAgents -Scope Global

function global:Start-RMTAgents {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][Alias("Agent")][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string[]]$EnvironmentIdentifier,
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Start RMT Agents",
        [switch]$IfTableauServerIsRunning
    )

    if ($Context -and $Context -like "Azure*") {
        Write-Log -Context "StartRMTAgents" -Action "Start-PlatformTask -Id StartRMTAgents" -Target "Platform" -Message $Reason -Force
        Start-PlatformTask -Id StartRMTAgents
        return
    }

    $params = @{ Command = "Start"}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Request-RMTAgents @params
    $result | Out-Null
    
    return

}
Set-Alias -Name Start-RMTEnvironments -Value Start-RMTAgents -Scope Global

function global:Restart-RMTAgents {

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
    Stop-RMTAgents @params

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    if ($EnvironmentIdentifier) {$params += @{ EnvironmentIdentifier = $EnvironmentIdentifier } }
    if ($ComputerName) { $params += @{ ComputerName = $ComputerName } }
    if ($IfTableauServerIsRunning) { $params += @{ IfTableauServerIsRunning = $true } }
    $result = Start-RMTAgents @params
    $result | Out-Null

    Set-CursorVisible

}

function global:Stop-Platform {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = "Command",
        [Parameter(Mandatory=$false)][string]$Reason = "Stop platform"
    )

    Set-CursorInvisible

    # Get-RMTStatus -ResetCache | Out-Null
    $platformStatus = Get-PlatformStatus -ResetCache

    Set-PlatformEvent -Event "Stop" -Context $Context -EventReason $Reason -EventStatus $PlatformEventStatus.InProgress -PlatformStatus $platformStatus

    $params = @{}
    if ($Context) { $params += @{ Context = $Context } }
    if ($Reason) { $params += @{ Reason = $Reason } }
    
    Stop-RMTAgents @params

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
    $result = Start-RMTAgents @params
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
        [Parameter(Mandatory=$false)][string]$Reason,
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
    param ()

    $rmtStatus = Get-RMTStatus -ResetCache

    # $agents = $rmtStatus.AgentStatus
    $controller = $rmtStatus.ControllerStatus
    $environs = $rmtStatus.EnvironmentStatus

    Write-Host+
    $message = $global:Platform.DisplayName
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
    Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
    Write-Host+
    Write-Host+ -SetIndentGlobal -Indent 2

    Write-Host+ -NoTrace -NoTimestamp "Controller"
    Write-Host+ -SetIndentGlobal -Indent 2

    $message = "<$($controller.Name) <.>48> $($controller.RollupStatus)"
    Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($controller.IsOK ? "DarkGreen" : "Red")
    $message = "<BuildVersion <.>48> $($controller.Controller.BuildVersion)"
    Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray
    Write-Host+ -NoTrace -NoTimestamp "Services" -ForegroundColor DarkGray
    Write-Host+ -SetIndentGlobal -Indent 2
    foreach ($service in $controller.Controller.Services) {
        $message = "<$($service.Name) <.>48> $($service.Status)"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,($service.IsOK ? "DarkGreen" : "Red")
    }
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+ -SetIndentGlobal -Indent -2
    Write-Host+
    
    foreach ($environ in $environs) {

        $message = $environ.Name
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message
        Write-Host+ -NoTrace -NoTimestamp (Format-Leader -Character "-" -Length $message.Length -NoIndent) -ForegroundColor DarkGray
        Write-Host+

        Write-Host+ -SetIndentGlobal -Indent 2

        Write-Host+ -NoTrace -NoTimestamp "Tableau Server"
        Write-Host+ -SetIndentGlobal -Indent 2
        $tableauServer = $environ.TableauServer
        $message = "<$($tableauServer.Name) <.>48> $($tableauServer.RollupStatus)"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($tableauServer.IsOK ? "DarkGreen" : "Red")
        Write-Host+ -SetIndentGlobal -Indent -2

        Write-Host+
        
        foreach ($agent in $environ.Agents) {

            Write-Host+ -NoTrace -NoTimestamp "Agent"
            Write-Host+ -SetIndentGlobal -Indent 2
            
            $message = "<$($agent.Name) <.>48> $($agent.IsConnected -eq "True" ? "Connected" : "Connection Issue")"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($agent.IsConnected -eq "True" ? "DarkGreen" : "Red")
            $message = "<BuildVersion <.>48> $($agent.BuildVersion)"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray
            Write-Host+ -NoTrace -NoTimestamp "Services" -ForegroundColor DarkGray
            Write-Host+ -SetIndentGlobal -Indent 2
            foreach ($service in $agent.Services) {
                $message = "<$($service.Name) <.>48> $($service.Status)"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor DarkGray,DarkGray,($service.IsOK ? "DarkGreen" : "Red")
            }
            Write-Host+ -SetIndentGlobal -Indent -2
            Write-Host+ -SetIndentGlobal -Indent -2

            Write-Host+

        }

        Write-Host+ -SetIndentGlobal -Indent -2
        

        Write-Host+

    }
}

#endregion COMMAND/CONTROL
        Write-Host+ -SetIndentGlobal -Indent -2
        

        Write-Host+

    }
}

#endregion COMMAND/CONTROL