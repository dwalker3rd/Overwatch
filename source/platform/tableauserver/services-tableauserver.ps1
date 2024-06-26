﻿# $TimeoutSec = 15

#region STATUS

function global:Get-PlatformStatusRollup {
        
    [CmdletBinding()]
    param (
        [switch]$ResetCache,
        [switch]$Quiet
    )

    $params = @{}
    if ($ResetCache) {$params += @{ResetCache = $true}}
    $tableauServerStatus = Get-TableauServerStatus @params

    if (!$tableauServerStatus) { return $false, "StatusUnAvailable", $null, $null }

    $issues = @()
    foreach ($nodeId in $tableauServerStatus.nodes.nodeId) {
        foreach ($service in ($tableauServerStatus.nodes | Where-Object {$_.nodeid -eq $nodeId}).services) { 
            if ($service.rollupRequestedDeploymentState -eq "Enabled" -and !$PlatformStatusOK.Contains($service.rollupStatus)) {
                foreach ($instance in $service.instances) {
                    if ($instance.currentDeploymentState -eq "Enabled" -and !$PlatformStatusOK.Contains($instance.processStatus)) {
                        $issues += @{
                            nodeId = $nodeId
                            component = "Service"
                            name = $service.serviceName
                            rollupStatus = $service.rollupStatus
                            instanceId = $instance.instanceId
                            processStatus = $instance.processStatus
                            message = $instance.message
                        }
                    }
                }
            }
        }
    }

    Write-Host+ -NoTrace -IfVerbose "IsOK: $($PlatformStatusOK.Contains($tableauServerStatus.rollupStatus)), Status: $($tableauServerStatus.rollupStatus)" -ForegroundColor DarkYellow
    return $PlatformStatusOK.Contains($tableauServerStatus.rollupStatus), $tableauServerStatus.rollupStatus, $issues, $tableauServerStatus
}

function global:Show-PlatformStatus {

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
    Write-Host+ -NoTrace $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), "PENDING" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGray

    #region STATUS

        # Write-Host+

        $nodes = $platformStatus.StatusObject.nodes | 
            Select-Object -Property @{Name='node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId -PlatformTopology $_platformTopology}}, 
                nodeId, @{Name='rollupStatus';Expression={![string]::IsNullOrEmpty($_.rollupStatus) ? $_.rollupStatus : "Unknown"}} | 
            Sort-Object -Property node

        foreach ($node in $nodes) {
            $message = "<  $($node.node) ($($node.nodeId))$($node.node -eq ($_platformTopology.InitialNode) ? "*" : $null) <.>42> $($node.RollupStatus.ToUpper())"
            $nodeRollupStatusColor = $node.RollupStatus -in $global:PlatformStatusColor.Keys ? $global:PlatformStatusColor.($node.RollupStatus) : "DarkRed"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($node.RollupStatus) ? "DarkGray" : $nodeRollupStatusColor)
        }

        $platformRollupStatusColor = $platformStatus.RollupStatus -in $global:PlatformStatusColor.Keys ? $global:PlatformStatusColor.($platformStatus.RollupStatus) : "DarkRed"
        Write-Host+ -NoTrace -Parse "<  $($global:Platform.Instance) <.>42> $($_platformStatusRollupStatus.ToUpper())" -ForegroundColor Gray,DarkGray, $platformRollupStatusColor

    #endregion STATUS      
    #region EVENTS    

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {

            Write-Host+

            Write-Host+ -NoTrace -Parse "<  Event <.>42> $($platformStatus.Event)" -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($platformStatus.Event) ? "DarkGray" : $global:PlatformEventColor.($platformStatus.Event))
            Write-Host+ -NoTrace -Parse "<  EventStatus <.>42> $($global:PlatformEventStatus.($platformStatus.EventStatus))" -ForegroundColor Gray,DarkGray, ([string]::IsNullOrEmpty($platformStatus.EventStatus) ? "DarkGray" : $global:PlatformEventStatusColor.($platformStatus.EventStatus))
            Write-Host+ -NoTrace -Parse "<  EventCreatedBy <.>42> $($platformStatus.EventCreatedBy)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -Parse "<  EventCreatedAt <.>42> $($platformStatus.EventCreatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $(!$platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventUpdatedAt <.>42> $($platformStatus.EventUpdatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $($platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventCompletedAt <.>42> $($platformStatus.EventCompletedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -Parse "<  EventHasCompleted <.>42> $($platformStatus.EventHasCompleted)" -ForegroundColor Gray,DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"

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

    Write-Host+ -NoTrace $_platformInstance, "Status", (Format-Leader -Length 39 -Adjust $_platformInstance.Length), $_platformStatusRollupStatus.ToUpper() -ForegroundColor DarkBlue,Gray,DarkGray, $platformRollupStatusColor

    # Write-Host+

}
Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global

function global:Build-StatusFacts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$true)][string]$Node,
        [switch]$ShowAll
    )

    # $nodeId = Get-PlatformTopology nodes.$Node.NodeId

    $facts = @(
        $PlatformStatus.ByCimInstance | Where-Object {$_.Node -eq $Node -and $_.Class -in 'Service'} | ForEach-Object {
            $component = $_
            foreach ($instance in $component.instance) {
                if ($instance.currentDeploymentState -eq "Enabled") {
                    if ((!$component.IsOK -and (!$PlatformStatusOK.Contains($instance.processStatus) -and $instance.currentDeploymentState -eq "Enabled")) -or $ShowAll) {
                        @{
                            name = "$($component.name)" + ($component.instance.Count -gt 1 ? "_$($instance.instanceId)" : "")
                            value = "$($instance.processStatus)" + ($($instance.message) ? ", $($instance.message)" : "")
                        }
                    }
                }
            }
        }  
    )

    return $facts
}

#endregion STATUS
#region PLATFORMINFO

function global:Get-PlatformInfo {

[CmdletBinding()]
param (
    [switch][Alias("Update")]$ResetCache
)

if (!$ResetCache) {
    if ($(Get-Cache platforminfo).Exists) {
        $platformInfo = Read-Cache platforminfo 
        if ($platformInfo) {
            # $global:Platform.Api.TsRestApiVersion = $platformInfo.TsRestApiVersion
            $global:Platform.Version = $platformInfo.Version
            $global:Platform.Build = $platformInfo.Build
            $global:Platform.DisplayName = $global:Platform.Name + " " + $platformInfo.Version
            return
        }
    }
}

$serverInfo = Get-TSServerInfo

# $global:Platform.Api.TsRestApiVersion = $serverinfo.restApiVersion
$global:Platform.Version = $serverinfo.productVersion.InnerText
$global:Platform.Build = $serverinfo.productVersion.build
$global:Platform.DisplayName = $global:Platform.Name + " " + $global:Platform.Version

$platformInfo = @{
    Version=$global:Platform.Version
    Build=$global:Platform.Build
    # TsRestApiVersion=$global:Platform.Api.TsRestApiVersion
}
$platformInfo | Write-Cache platforminfo

return

}

#endregion PLATFORMINFO
#region SERVICE

    function global:Get-PlatformServices {

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

        if ($(Get-Cache platformservices).Exists -and !$ResetCache) {
            Write-Host+ -IfDebug "Read-Cache platformservices" -ForegroundColor DarkYellow
            $platformServicesCache = Read-Cache platformservices -MaxAge $(New-TimeSpan -Minutes 1)
            if ($platformServicesCache) {
                $platformServices = $platformServicesCache
                return $platformServices
            }
        }

        $platformTopology = Get-PlatformTopology
        $platformStatus = Read-Cache platformstatus
        # $tableauServerStatus = Get-TableauServerStatus

        $eventVerb = $null
        $serviceStatusOK = @("Active","Running")
        if ($platformStatus.Event -and !$platformStatus.EventHasCompleted) {
            switch ($platformStatus.Event) {
                "Stop" {
                    $eventVerb = "Stopping"
                    $serviceStatusOK += "Stopping"
                    $serviceStatusOK += "Stopped"
                }
                "Start" {
                    $eventVerb = "Starting"
                    $serviceStatusOK += "Starting"
                }
            }
        }

        Write-Host+ -IfDebug "Processing PlatformServices" -ForegroundColor DarkYellow
        if ($platformStatus.StatusObject) {
            $platformServices = @()
                foreach ($nodeId in $platformStatus.StatusObject.nodes.nodeId) {
                    $node = $platformTopology.Alias.$nodeId                   
                    $services = ($platformStatus.StatusObject.nodes | Where-Object {$_.nodeid -eq $nodeId}).services
                    $services | Foreach-Object {
                        $service = $_
                        $platformService = @(
                            [PlatformCim]@{
                                Name = $service.ServiceName
                                DisplayName = $service.ServiceName
                                Class = "Service"
                                Node = $node
                                Required = $service.rollupRequestedDeploymentState -eq "Enabled"
                                Status = $service.rollupStatus -eq "Error" -or [string]::IsNullOrEmpty($service.rollupStatus) ? $eventVerb : $service.rollupStatus
                                StatusOK = $serviceStatusOK
                                IsOK = $serviceStatusOK.Contains($service.rollupStatus)
                                Instance = $service.instances
                            }
                        )
                        $platformServices += $platformService
                    }
                }
        }      

        Write-Host+ -IfDebug "Write-Cache platformservices" -ForegroundColor DarkYellow
        $platformServices | Write-Cache platformservices

        return $platformServices | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)

    }

    function global:Request-Platform {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)][ValidateSet("Stop","Start")][string]$Command,
            [Parameter(Mandatory=$true)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Reason,
            [switch]$NoWait,
            [switch]$IgnoreCurrentState,
            [switch]$IgnorePendingChanges
        )

        $commandPresentParticiple = $Command + ($Command -eq "Stop" ? "p" : $null) + "ing"
        # $commandPastTense = $Command + ($Command -eq "Stop" ? "p" : $null) + "ed"
        
        $platformStatus = Get-PlatformStatus

        Set-CursorInvisible

        Write-Host+
        Write-Host+ -NoTrace -NoSeparator "$($global:Platform.Name)" -ForegroundColor DarkBlue
        $message = "< Command <.>48> $($Command.ToUpper())"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($Command -eq "Start" ? "Green" : "Red")
        if (![string]::IsNullOrEmpty($Reason)) {
            $message = "< Reason <.>48> $($Reason.ToUpper())"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        }

        $message = "< Platform Status <.>48> $($platformStatus.RollupStatus.ToUpper())"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.$($platformStatus.RollupStatus)

        Write-Log -Action $Command -Target "Platform" -EntryType "Information" -Status "Created" -Message $message -Force

        if (!$IgnoreCurrentState -and 
            ($Command -eq "Start" -and $platformStatus.RollupStatus -eq "Running") -or
            ($Command -eq "Stop" -and $platformStatus.RollupStatus -eq "Stopped")) {
                $message = "Platform is already $($platformStatus.RollupStatus.ToUpper())"
                Write-Log -Action $Command -Target "Platform" -EntryType "Information" -Status $platformStatus.RollupStatus.ToUpper() -Message $message -Force
                Set-CursorVisible
                return
            }

        $commandStatus = $PlatformEventStatus.InProgress
        $message = "< Set Platform Event <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus
        Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS " -ForegroundColor DarkGreen
        Write-Log -Action $Command -Target "Platform" -EntryType "Information" -Status $commandStatus -Message $message -Force

        # preflight checks
        if ($Command -eq "Start") {

            # apply any pending changes
            $message = "< Pending Changes <.>48> REVIEWING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            $pendingChanges = Get-TsmPendingChanges
            if ($pendingChanges.hasPendingChanges -and !$IgnorePendingChanges) {
                Write-Host+ -NoTrace -NoTimestamp -NoNewline "$($emptyString.PadLeft(10,"`b")) APPLYING " -ForegroundColor DarkGray
                $pendingChangesResult = Apply-TsmPendingChanges <# @{ successfulDeployment = $false; changes = @("this was a test") } #>
                $_entryType = $pendingChangesResult.successfulDeployment ? "Information" : "Error"
                $_status = $pendingChangesResult.successfulDeployment ? "Applied" : "Error"
                $_color = $pendingChangesResult.successfulDeployment ? "DarkGreen" : "Red"
                $_message = $pendingChangesResult.changes[-1]
                Write-Log -Action "Apply Pending-Changes" -Target "Platform" -EntryType $_entryType -Status $_status -Message $_message -Force
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(10,"`b")) $($_status.ToUpper())" -ForegroundColor $_color
                Write-Host+ -Iff $($_status -eq "Error") -NoTrace "    $_message" -ForegroundColor $_color
            }
            else {
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(10,"`b")) NONE" -ForegroundColor DarkGray
            }

            # preflight update
            if (HasPreflightUpdate) {
                Update-Preflight -Force
            }

        }

        try {

            $message = "< Platform Status <.>48> $($commandPresentParticiple.ToUpper())"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($Command -eq "Start" ? "Green" : "Red")

            $platformJob = Invoke-TsmApiMethod -Method $Command
            Watch-PlatformJob -Id $platformJob.Id -Context $Context -NoEventManagement -NoMessaging

            if (!$NoWait) {
                $platformJob = Wait-PlatformJob -Id $platformJob.id -Context $Context -TimeoutSeconds 1800 -ProgressSeconds -60
                $platformJob = Get-PlatformJob -Id $platformJob.id
                $commandStatus = $platformJob.status
            }

            if ($platformJob.status -eq $global:tsmApiConfig.Async.Status.Succeeded -and $NoWait) {
                $commandStatus = $global:PlatformEventStatus.Succeeded
                $message = "Platform $($Command.ToUpper()) (Job id: $($platformJob.id)) has "
                Write-Log -Action $Command  -Target "Platform" -EntryType "Information" -Status "Succeeded" -Message "$($message) $commandStatus." -Force
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message, $commandStatus, ". ", $platformJob.errorMessage -ForegroundColor Gray,$global:PlatformEventStatusColor.$commandStatus,Gray,$global:PlatformEventStatusColor.$commandStatus
            }
            elseif ($platformJob.status -eq $global:tsmApiConfig.Async.Status.Failed) {
                $commandStatus = $global:PlatformEventStatus.Failed
                $message = "Platform $($Command.ToUpper()) (Job id: $($platformJob.id)) has "
                Write-Log -Action $Command  -Target "Platform" -EntryType "Warning" -Status "Failure" -Message "$($message) $commandStatus. $($platformJob.errorMessage)." 
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message, $commandStatus, ". ", $platformJob.errorMessage -ForegroundColor Gray,$global:PlatformEventStatusColor.$commandStatus,Gray,$global:PlatformEventStatusColor.$commandStatus
            } 
            elseif ($platformJob.status -eq $global:tsmApiConfig.Async.Status.Cancelled) {
                $commandStatus = $global:PlatformEventStatus.Cancelled
                $message = "Platform $($Command.ToUpper()) (Job id: $($platformJob.id)) was "
                Write-Log -Action $Command  -Target "Platform" -EntryType "Warning" -Status "Cancelled" -Message "$($message) $commandStatus. $($platformJob.errorMessage)."
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message, $commandStatus, ". ", $platformJob.errorMessage -ForegroundColor Gray,$global:PlatformEventStatusColor.$commandStatus,Gray,$global:PlatformEventStatusColor.$commandStatus
            }
            elseif ($platformJob.status -eq $global:tsmApiConfig.Async.Status.Created -and $NoWait) {
                $commandStatus = $global:PlatformEventStatus.Created
                $message = "Platform $($Command.ToUpper()) (Job id: $($platformJob.id)) was "
                Write-Log -Action $Command  -Target "Platform" -EntryType "Information" -Status "Created" -Message "$($message) $commandStatus. $($platformJob.statusMessage)." -Force
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message, $commandStatus, ". ", $platformJob.statusMessage -ForegroundColor Gray,$global:PlatformEventStatusColor.$commandStatus,Gray,Gray
            }
            elseif ($platformJob.status -ne $global:tsmApiConfig.Async.Status.Succeeded) {
                $commandStatus = $global:PlatformEventStatus.Completed
                $message = "Timeout waiting for platform $($Command.ToUpper()) (Job id: $($platformJob.id)) to complete. $($platformJob.statusMessage)"
                Write-Log -Action $Command  -Target "Platform" -EntryType "Warning" -Status "Timeout" -Message "$($message) $commandStatus. $($platformJob.statusMessage)."
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor $global:PlatformEventStatusColor.$commandStatus
            }

            if ($Command -eq "Start") {
                # postflight checks
                if (HasPostflightCheck) {
                    Confirm-PostFlight -Force
                }
            
            }

        }
        catch {
            $commandStatus = $global:PlatformEventStatus.Failed
        }

        if (!$NoWait) {
            Watch-PlatformJob -Remove -Id $platformJob.Id -Context $Context -NoEventManagement -NoMessaging
        }
        
        Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus

        Write-Log -Action $Command  -Target "Platform" -Status $commandStatus -Message "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"

        $platformStatus = Get-PlatformStatus

        $message = "< Platform Status <.>48> $($platformStatus.RollupStatus.ToUpper())"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.$($platformStatus.RollupStatus)

        Set-CursorVisible

        if ($commandStatus -eq $PlatformEventStatus.Failed) {throw "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"}

        return

    }

    function global:Start-Platform {

        [CmdletBinding()] param (
            [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id ?? "Command",
            [Parameter(Mandatory=$false)][string]$Reason<#  = "Start platform" #>,
            [switch]$NoWait,
            [switch]$IgnoreCurrentState,
            [switch]$IgnorePendingChanges
        )

        Request-Platform -Command Start -Context $Context -Reason $Reason -NoWait:$NoWait.IsPresent -IgnoreCurrentState:$IgnoreCurrentState.IsPresent -IgnorePendingChanges:$IgnorePendingChanges.IsPresent
    }
    function global:Stop-Platform {

        [CmdletBinding()] param (
            [Parameter(Mandatory=$false)][string]$Context = "Command",
            [Parameter(Mandatory=$false)][string]$Reason<#  = "Stop platform" #>,
            [switch]$NoWait,
            [switch]$IgnoreCurrentState,
            [switch]$IgnorePendingChanges
        )
        
        Request-Platform -Command Stop -Context $Context -Reason $Reason -NoWait:$NoWait.IsPresent -IgnoreCurrentState:$IgnoreCurrentState.IsPresent -IgnorePendingChanges:$IgnorePendingChanges.IsPresent
    }

    function global:Restart-Platform {

        [CmdletBinding()] param (
            [Parameter(Mandatory=$false)][string]$Context = "Command",
            [Parameter(Mandatory=$false)][string]$Reason = "Restart",
            [switch]$NoWait,
            [switch]$IgnoreCurrentState,
            [switch]$IgnorePendingChanges
        )

        Stop-Platform -Context $Context -Reason $Reason
        Start-Platform -Context $Context -Reason $Reason -NoWait:$NoWait.IsPresent -IgnoreCurrentState:$IgnoreCurrentState.IsPresent -IgnorePendingChanges:$IgnorePendingChanges.IsPresent
    }

#endregion SERVICE
#region PROCESS

function global:Get-PlatformProcess {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string[]]$ComputerName,
    [Parameter(Mandatory=$false)][string]$View,
    [switch]$ResetCache
)

Write-Host+ -IfDebug "$($MyInvocation.MyCommand) is a STUB" -ForegroundColor DarkYellow
return

}

#endregion PROCESS
#region CLEANUP

function global:Cleanup-Platform {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()] param(
        [Parameter(Mandatory=$false)][Alias("a")][switch]$All = $global:Cleanup.All,
        [Parameter(Mandatory=$false)][Alias("ic")][switch]$SheetImageCache = $global:Cleanup.SheetImageCache,
        [Parameter(Mandatory=$false)][Alias("b")][switch]$BackupFiles = $global:Cleanup.BackupFiles,
        [Parameter(Mandatory=$false)][Alias("backup-files-retention")][int]$BackupFilesRetention = $global:Cleanup.BackupFilesRetention,
        [Parameter(Mandatory=$false)][Alias("l")][switch]$LogFiles = $global:Cleanup.LogFiles,
        [Parameter(Mandatory=$false)][Alias("log-files-retention")][int]$LogFilesRetention = $global:Cleanup.LogFilesRetention,
        [Parameter(Mandatory=$false)][Alias("q")][switch]$HttpRequestsTable = $global:Cleanup.HttpRequestsTable,
        [Parameter(Mandatory=$false)][Alias("http-requests-table-retention")][int]$HttpRequestsTableRetention = $global:Cleanup.HttpRequestsTableRetention,
        [Parameter(Mandatory=$false)][Alias("r")][switch]$RedisCache = $global:Cleanup.RedisCache,
        [Parameter(Mandatory=$false)][Alias("t")][switch]$TempFiles = $global:Cleanup.TempFiles,
        [Parameter(Mandatory=$false)][int]$TimeoutInSeconds = $global:Cleanup.TimeoutInSeconds
    )
    
    if ($All) {
        $BackupFiles = $true
        $LogFiles = $true
    }

    if (!$BackupFiles -and !$LogFiles -and !$SheetImageCache -and !$HttpRequestsTable -and !$RedisCache -and !$TempFiles) {
        $message = "You must specify at least one of the following switches: -All, -BackupFiles, -LogFiles, -HttpRequestsTable, -TempFiles, -SheetImageCache or -RedisCache."
        Write-Host+ $message -ForegroundColor Red
        Write-Log -Context "Product.Cleanup" -Action "NONE" -EntryType "Error" -Status "Failure" -Message $message
        return
    }

    Write-Host+
    $message = "<Cleanup <.>48> PENDING"
    Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    $purgeBackupFilesSuccess = $true

    # purge backup files
    if ($BackupFiles) {

        $message = "<  Backup files <.>48> PENDING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $backupFileCount = (Get-Files -Path $global:Backup.Path -Filter "*.$($global:Backup.Extension)").fileInfo.Count
        $configFileCount = (Get-Files -Path $global:Backup.Path -Filter "*.json").fileInfo.Count

        if ($backupFileCount -gt $BackupFilesRetention -or $configFileCount -gt $BackupFilesRetention) {

            try{
                $fileCountBeforePurge = $backupFileCount + $configFileCount
                Remove-Files -Path $global:Backup.Path -Keep $BackupFilesRetention -Filter "*.$($global:Backup.Extension)"
                Remove-Files -Path $global:Backup.Path -Keep $BackupFilesRetention -Filter "*.json"
                $backupFileCount = (Get-Files -Path $global:Backup.Path -Filter "*.$($global:Backup.Extension)").fileInfo.Count
                $configFileCount = (Get-Files -Path $global:Backup.Path -Filter "*.json").fileInfo.Count
                $fileCountAfterPurge = $backupFileCount + $configFileCount
                Write-Log -Context "Product.Cleanup" -Action "Purge" -Target "Backup Files" -Status "Success" -Message "$($fileCountBeforePurge-$fileCountAfterPurge) backup files purged." -Force
                Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) SUCCESS" -ForegroundColor DarkGreen
            }
            catch {
                Write-Log -Context "Product.Cleanup" -Action "Purge" -Target "Backup Files" -EntryType -Exception $_.Exception
                Write-Host+ -NoTrace -NoTimestamp "$($_.Exception.Message)" -ForegroundColor Red
                $message = "<  Backup files <.>48> FAILURE"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,Red
                $purgeBackupFilesSuccess = $false
            }

        }
        elseif ($backupFileCount -gt 0 -or $configFileCount -gt 0) {
            Write-Log -Context "Product.Cleanup" -Action "Purge" -Target "Backup Files" -Status "NoPurge" -Message "Backup files found. No purge required." -EntryType Warning -Force
            Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) NOPURGE" -ForegroundColor DarkYellow
        }
        else {
            Write-Log -Context "Product.Cleanup" -Action "Purge" -Target "Backup Files" -Status "NoFiles" -Message "Backup files not found." -EntryType Warning -Force
            Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(8,"`b")) NOFILES" -ForegroundColor DarkYellow
        }

    }
    else {
        $message = "<  Backup files <.>48> SKIPPED"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
    }

    # Write-Host+ -MaxBlankLines 1

    $tsmCleanupJobSuccess = $true

    # run TSM cleanupjob
    if ($LogFiles -or $SheetImageCache -or $HttpRequestsTable -or $RedisCache -or $TempFiles) {

        $tsmMaintenanceCleanupExpression = ". tsm maintenance cleanup"
        if ($All) {
            $tsmMaintenanceCleanupExpression += " -a"
        }
        else {
            if ($SheetImageCache) { $tsmMaintenanceCleanupExpression += " -ic"}
            if ($LogFiles) { $tsmMaintenanceCleanupExpression += " -l"}
            if ($HttpRequestsTable) { $tsmMaintenanceCleanupExpression += " -q"}
            if ($RedisCache) { $tsmMaintenanceCleanupExpression += " -r"}
            if ($TempFiles) { $tsmMaintenanceCleanupExpression += " -t"}
        }
        if ($TimeoutInSeconds -gt 0) { $tsmMaintenanceCleanupExpression += " --request-timeout $TimeoutInSeconds"}
        if ($All -or $LogFiles) { $tsmMaintenanceCleanupExpression += " --log-files-retention $LogFilesRetention" }
        if ($All -or $HttpRequestsTable) { $tsmMaintenanceCleanupExpression += " --http-requests-table-retention $HttpRequestsTableRetention" }

        $message = "<  TSM Maintenance Cleanup <.>48> PENDING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        try {

            Invoke-Expression -Command $tsmMaintenanceCleanupExpression
            $cleanupPlatformJob = Get-PlatformJob -Type "CleanupJob" -Latest
            $cleanupPlatformJob
            
            $message = "<  TSM Maintenance Cleanup <.>48> SUCCESS"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

            Write-Log -Context "Product.Cleanup" -Action "CleanupJob" -Target "Platform job $($cleanupPlatformJob.id)" -Status $cleanupPlatformJob.status -Message $cleanupPlatformJob.statusMessage -Force # -Data $cleanupPlatformJob.args
            # $result = Send-PlatformJobMessage -Context "Cleanup" -Id $cleanupPlatformJob.Id -NoThrottle
            # $result | Out-Null

        }
        catch {

            Write-Host+ -NoTrace -NoTimestamp "$($_.Exception.Message)" -ForegroundColor Red

            Write-Host+
            $message = "<  TSM Maintenance Cleanup <.>48> FAILURE"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Red
            
            Write-Log -Context "Product.Cleanup" -Action "CleanupJob" -Exception $_.Exception

            $tsmCleanupJobSuccess = $false

        }

    }
    else {
        $message = "<  TSM Maintenance Cleanup <.>48> SKIPPED"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
    }

    $status = "SUCCESS"
    if (!$purgeBackupFilesSuccess -and $tsmCleanupJobSuccess) { $status = "WARNING"}
    if (!$tsmCleanupJobSuccess) { $status = "FAILURE"}

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

    Write-Log -Context "Product.Cleanup" -Action "Cleanup" -Status $status -EntryType $entryType -Force
    Send-TaskMessage -Id "Cleanup" -Status "Completed" -Message $($status -eq "SUCCESS" ? "" : "See log files for details.") | Out-Null

    return

}

#endregion CLEANUP
#region BACKUP

function global:Backup-Platform {

    [CmdletBinding()] param()  

    #region EXPORT

        $message = "<Export Settings <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        
        try {

            $response = Invoke-TsmApiMethod -Method "ExportConfigurationAndTopologySettings"
            $exportFile = "$($global:Backup.Path)/$($global:Backup.Name).json" -replace "\/","\"
            $response | ConvertTo-Json -Depth 99 | Out-File $exportFile

            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

        }
        catch {

            Write-Log -Context "Backup" -Action "Export" -Target "Configuration" -EntryType "Warning" -Exception $_.Exception

            $message = "$($emptyString.PadLeft(8,"`b")) FAILURE$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red 

        }

    #endregion EXPORT

    #region BACKUP JOB

        $message = "<Creating Backup Job <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        
        try {

            $backupFile = "$($global:Backup.Name).$($global:Backup.Extension)"
            $backupPlatformJob = Invoke-TsmApiMethod -Method "Backup" -Params @($backupFile)
            Watch-PlatformJob -Id $backupPlatformJob.id -Context "Backup" -Callback "Invoke-PlatformJobCallback"

            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

            Send-TaskMessage -Id "Backup" -Status "Running" | Out-Null

        }
        catch {

            Write-Log -EntryType "Error" -Action "Backup" -Exception $_.Exception
           
            $message = "$($emptyString.PadLeft(8,"`b")) FAILURE$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red 
            
        }

    #endregion BACKUP JOB

    return
}

#endregion BACKUP
#region PLATFORM JOBS

function global:Get-PlatformJob {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Status,
        [Parameter(Mandatory=$false)][string]$Type,
        [switch]$Latest
    )

    if ($Id) {
        $platformJob = Invoke-TsmApiMethod -Method "AsyncJob" -Params @($Id)
    }
    else {
        $platformJob = Invoke-TsmApiMethod -Method "AsyncJobs"
        if ($Status) {
            $platformJob = $platformJob | Where-Object {$_.status -eq $Status}
        }
        if ($Type) {
            $platformJob = $platformJob | Where-Object {$_.jobType -eq $Type}
        }
        if ($Latest) {
            $platformJob = $platformJob | Sort-Object -Property updatedAt | Select-Object -Last 1
        }
    }

    return $platformJob
}

function global:Show-PlatformJob {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Status,
        [Parameter(Mandatory=$false)][string]$Type,
        [Parameter(Mandatory=$false)][string]$View,
        [switch]$Latest
    )
    
    $platformJobs = Get-PlatformJob -Id $Id -Status $Status -Type $Type

    return  $platformJobs | Select-Object -Property $($View ? $platformJobView.$($View) : $platformJobView.Default)
}

function global:Watch-PlatformJob {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id,
        [Parameter(Mandatory=$false)][string]$Source,
        [Parameter(Mandatory=$false)][string]$Callback,
        [switch]$Add,
        [switch]$Update,
        [switch]$Remove,
        [switch]$NoEventManagement,
        [switch]$NoMessaging
    )

    function Remove-PlatformJobFromWatchlist {
        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline)][Object]$InputObject,
            [Parameter(Mandatory=$true,Position=0)][object]$PlatformJob,
            [Parameter(Mandatory=$false,Position=1)][string]$Callback
        )
        begin {$outputObject = @()}
        process {$outputObject += $InputObject}
        end {return $outputObject | Where-Object {$_.id -ne $PlatformJob.id}}
    }

    function Add-PlatformJobToWatchlist {
        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline)][Object]$InputObject,
            [Parameter(Mandatory=$true,Position=0)][object]$PlatformJob,
            [Parameter(Mandatory=$false)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Source,
            [Parameter(Mandatory=$false)][string]$Callback
        )
        begin {$outputObject = @()}
        process {
            if ($InputObject) {
                $outputObject += $InputObject
            }
        }
        end {
            if ($PlatformJob.id -notin $InputObject.id) {       
                $outputObject += [PSCustomObject]@{
                    id = $PlatformJob.id
                    status = $PlatformJob.status
                    progress = $PlatformJob.progress
                    updatedAt = $PlatformJob.updatedAt
                    context = $Context
                    source = $Source
                    callback = $Callback
                    noMessaging = $NoMessaging
                    noEventManagement = $NoEventManagement
                }
            }
            return $outputObject
        }
    }

    $Command = "Add"
    if ($Update) {$Command = "Update"}
    if ($Remove) {$Command = "Remove"}

    $platformJob = Get-PlatformJob -Id $Id
    if (!$platformJob) {return}

    $platformEvent = switch ($platformJob.jobType) {
        "DeploymentsJob" {$PlatformEvent.Restart}
        "StartServerJob" {$PlatformEvent.Start}
        "StopServerJob" {$PlatformEvent.Stop}
        default {$null}
    }

    $platformEventStatusTarget = switch ($platformJob.jobType) {
        "DeploymentsJob" {$PlatformEventStatusTarget.Start}
        "StartServerJob" {$PlatformEventStatusTarget.Start}
        "StopServerJob" {$PlatformEventStatusTarget.Stop}
        default {$null}
    }

    $watchlist = Read-Watchlist platformJobsWatchlist

    $prevPlatformJob = $watchlist | Where-Object {$_.id -eq $Id}

    switch ($Command) {
        "Add" {
            $watchlist = $watchlist | Add-PlatformJobToWatchlist -PlatformJob $platformJob -Context $Context -Source $Source -Callback $Callback 

            # send alerts for new entries
            if (!$prevPlatformJob) {
                if (!$NoMessaging) {
                    Send-PlatformJobMessage $platformJob.id -Context $Context | Out-Null
                }
            } 

            # set platform event 
            if ($platformEvent) {
                if (!$NoEventManagement) {
                    Set-PlatformEvent -Event $platformEvent -EventStatus $PlatformEventStatus.InProgress -EventStatusTarget $platformEventStatusTarget -Context $Source
                }
            }
        }
        "Update" {
            # remove previous entry and add updated entry
            $watchlist = $watchlist | Remove-PlatformJobFromWatchlist -PlatformJob $platformJob 

            $NoMessaging = $prevPlatformJob.noMessaging
            $NoEventManagement = $prevPlatformJob.noEventManagement

            if (!$platformJob.completedAt) {
                $watchlist = $watchlist | Add-PlatformJobToWatchlist -PlatformJob $platformJob -Context $prevPlatformJob.context -Source $prevPlatformJob.source-Callback $prevPlatformJob.callback
            }

            # send alerts for updates
            if ($platformJob.updatedAt -gt $prevPlatformJob.updatedAt) {
                if ($platformJob.status -ne $prevPlatformJob.status -or $platformJob.progress -gt $prevPlatformJob.progress) {
                    if (!$NoMessaging) {
                        Send-PlatformJobMessage $platformJob.id -Context ($Context ? $Context : $prevPlatformJob.context) | Out-Null
                    }
                }
            }
            if ($platformJob.completedAt) {
                if ($prevPlatformJob.callback) {
                    Invoke-Expression "$($prevPlatformJob.Callback) -Id $($platformJob.id)"
                }

                # set platform event (completed or failed)
                if ($platformEvent) {
                    if (!$NoEventManagement) {
                        Set-PlatformEvent -Event $platformEvent -EventStatus ($platformJob.status -ne "Succeeded" ? $PlatformEventStatus.Failed : $PlatformEventStatus.Completed) -EventStatusTarget $platformEventStatusTarget -Context $prevPlatformJob.source
                    }
                }
            }                
        }
        "Remove" {
            $watchlist = $watchlist | Remove-PlatformJobFromWatchlist $platformJob
        }
    }

    $watchlist | Write-Watchlist platformJobsWatchlist
    
    return

}

Set-Alias -Name Write-Watchlist -Value Write-Cache -Scope Global
Set-Alias -Name Clear-Watchlist -Value Clear-Cache -Scope Global
Set-Alias -Name Read-Watchlist -Value Read-Cache -Scope Global

function global:Show-Watchlist {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Watchlist = "platformJobsWatchlist",
        [Parameter(Mandatory=$false)][string]$View="Watchlist"
    )

    Update-PlatformJob

    return (Read-Watchlist $Watchlist) | Select-Object -Property $($View ? $PlatformJobView.$($View) : $PlatformJobView.Default)

}

function global:Update-PlatformJob {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Id
    )

    $watchlist = Read-Watchlist platformJobsWatchlist
    if ($Id) { 
        $watchlist = $watchlist | Where-Object {$_.id -eq $Id}
        if (!$watchlist) {return}
    }
    foreach ($platformJob in $watchlist) {
        Watch-PlatformJob $platformJob.id -Update
    }

    # check TSM for running platformJobs started by others
    # this step returns all running jobs: dupes removed by Watch-PlatformJob
    $platformJobs = Get-PlatformJob -Status "Running" | Where-Object {$_.id -notin $watchlist.id -and $_.jobType -notin $global:tsmApiConfig.Async.DontWatchExternalJobType}
    foreach ($platformJob in $platformJobs) {
        Watch-PlatformJob $platformJob.Id -Add -Source "External Service/Person"
    }

    return

}

function global:Write-PlatformJobStatusToLog {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id
    )

    $platformJob = Get-PlatformJob $Id

    # $data = $null
    $message = $platformJob.statusMessage
    if ($platformJob.status -eq "Succeeded") {
        # $data = "Duration: $($platformJob.completedAt - $platformJob.createdAt) ms"
        $message = "This job completed successfully at $($epoch.AddSeconds($platformJob.completedAt/1000).ToString('u'))."
    }

    Write-Log -Action $platformJob.jobType -Target $platformJob.id -Status $platformJob.status -Message $message -Force # -Data $data 

}

function global:Wait-PlatformJob {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id,
        [Parameter(Mandatory=$false)][int]$IntervalSeconds = 15,
        [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 300,
        [Parameter(Mandatory=$false)][int]$ProgressSeconds
    )

    $platformJob = Invoke-TsmApiMethod -Method "AsyncJob" -Params @($Id)

    $timeout = $false
    $timeoutTimer = [Diagnostics.Stopwatch]::StartNew()

    do {
        Start-Sleep -seconds $IntervalSeconds
        $platformJob = Invoke-TsmApiMethod -Method "AsyncJob" -Params @($Id)
    } 
    until ($platformJob.completedAt -or 
            [math]::Round($timeoutTimer.Elapsed.TotalSeconds,0) -gt $TimeoutSeconds)

    if ([math]::Round($timeoutTimer.Elapsed.TotalSeconds,0) -gt $TimeoutSeconds) {
        $timeout = $true
    }

    $timeoutTimer.Stop()

    return $platformJob, $timeout

}

function global:Invoke-PlatformJobCallback {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=1)][string]$Id
)

$platformJob = Get-PlatformJob -Id $Id
$platformJobProduct = Get-Product -Id $(switch ($platformJob.jobtype) {
        "GenerateBackupJob" { "Backup" }
        "CleanupJob" { "Cleanup" }
    })

if ($platformJob.status -eq $global:tsmApiConfig.Async.Status.Cancelled) {

    Write-Log -EntryType "Warning" -Context $platformJobProduct.Id -Action $platformJobProduct.Id -Target "platformJob $($platformJob.id)" -Status $platformJob.status -Message $platformJob.statusMessage
    Write-Warning "platformJob $($platformJob.id): $($platformJob.statusMessage)"
    Send-TaskMessage -Id $platformJobProduct.Id -Status "Warning" -Message $platformJob.statusMessage -MessageType $PlatformMessageType.Warning | Out-Null

    return

} 
elseif ($platformJob.status -ne $global:tsmApiConfig.Async.Status.Succeeded) {

    Write-Log -EntryType "Error" -Context $platformJobProduct.Id -Action $platformJobProduct.Id -Target "platformJob $($platformJob.id)" -Status $platformJob.status -Message $platformJob.statusMessage
    Write-Host+ "platformJob $($platformJob.id): $($platformJob.statusMessage)" -ForegroundColor DarkRed
    Send-TaskMessage -Id $platformJobProduct.Id -Status "Error" -Message $platformJob.statusMessage -MessageType $PlatformMessageType.Alert | Out-Null

    return

} 
else {

    Send-TaskMessage -Id $platformJobProduct.Id -Status "Completed" | Out-Null
    
    return
} 
}

#endregion PLATFORM JOBS
#region TOPOLOGY

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

$platformTopology = @{
    Nodes = @{}
    Components = @{}
    Alias = @{}
    Repository = @{}
}


$platformConfiguration = @{
    Keys = @{}
}

# $tsmApiSession = New-TsmApiSession
$response = Invoke-TsmApiMethod -Method "ExportConfigurationAndTopologySettings" 

foreach ($nodeId in $response.topologyVersion.nodes.psobject.properties.name) {
    
    $nodeInfo = Invoke-TsmApiMethod -Method "NodeInfo" -Params @($nodeId) 
    $node = $nodeInfo.address

    $platformTopology.Alias.$nodeId = $node
    $platformTopology.Alias.$node = $node
    # $platformTopology.Alias.$node = $nodeId
    # if (![string]::IsNullOrEmpty($global:RegexPattern.PlatformTopology.Alias.Match)) {
    #     if ($node -match $RegexPattern.PlatformTopology.Alias.Match) {
    #         $ptAlias = ""
    #         foreach ($i in $global:RegexPattern.PlatformTopology.Alias.Groups) {
    #             $ptAlias += $Matches[$i]
    #         }
    #         $platformToplogy.Alias.$node = $ptAlias
    #         $platformTopology.Alias.($ptAlias) = $node
    #     }
    # }

    $platformTopology.Nodes.$node += @{
        NodeId = $nodeId
        NodeInfo = @{
            ProcessorCount = $nodeInfo.processorCount
            AvailableMemory = $nodeInfo.availableMemory
            TotalDiskSpace = $nodeInfo.totalDiskSpace
        }
        Components = @{}
    }
    $services = ($response.topologyversion.nodes.$nodeId.services.psobject.members | Where-Object {$_.MemberType -eq "NoteProperty"} | Select-object -property Name).Name
    foreach ($service in $services) {
        $platformTopology.Nodes.$node.Components.$service += @{
            Instances = @()
        }
        foreach ($instance in $response.topologyVersion.nodes.$node.services.$service.instances) {
            $platformTopology.Nodes.$node.Components.$service.Instances += @{
                ($instance.instanceId) = @{
                    InstanceId = $instance.instanceId
                    BinaryVersion = $instance.binaryVersion
                }
            }
        }
    }
}

foreach ($key in $response.configKeys.psobject.properties.name) {
    $platformConfiguration.Keys += @{
        $key = $response.configKeys.$key
    }
}

foreach ($node in $platformTopology.Nodes.Keys) {

    foreach ($component in $platformTopology.Nodes.$node.Components.Keys) {

        if (!$platformTopology.Components.$component) {
            $platformTopology.Components += @{
                $component = @{
                    Nodes = @{}
                }
            }
        }
        $platformTopology.Components.$component.Nodes += @{
            $node = @{
                Instances = $platformTopology.Nodes.$node.Components.$component.instances
            }
        }
    }

}

$platformTopology.InitialNode = $platformTopology.Components.tabadmincontroller.Nodes.Keys

$repositoryNodeInfo = Invoke-TsmApiMethod -Method "RepositoryNodeInfo"
$platformTopology.repository.HostName = $repositoryNodeInfo.hostName
$platformTopology.repository.Port = $repositoryNodeInfo.port
$platformTopology.repository.Active = $platformTopology.Alias.($platformTopology.repository.HostName) ?? $platformTopology.repository.HostName
$platformTopology.repository.Passive = $platformTopology.Components.pgsql.Nodes.Keys | Where-Object {$_ -ne $platformTopology.repository.Active}
$platformTopology.repository.Preferred = $platformConfiguration.Keys."pgsql.preferred_host"
$platformTopology.repository.Preferred ??= $platformTopology.InitialNode

if ($platformTopology.Nodes) {
    $platformTopology | Write-Cache platformtopology
}

return $platformTopology

}
Set-Alias -Name ptInit -Value Initialize-PlatformTopology -Scope Global

#endregion TOPOLOGY
#region CONFIGURATION

function global:Show-TSSslProtocols {

    Write-Host+ -NoTrace "  Tableau Server SSL Protocols" -ForegroundColor DarkBlue

    $sslProtocolsAll = "+SSLv2 +SSLv3 +TLSv1 +TLSv1.1 +TLSv1.2 +TLSv1.3"
    $sslProtocols = Get-TsmConfigurationKey -Key "ssl.protocols"
    $sslProtocols = $sslProtocols.PSObject.Properties.Value -replace "all",$sslProtocolsAll
    $sslProtocols = $sslProtocols -split " " | Sort-Object

    $protocols = @{}
    foreach ($sslProtocol in $sslProtocols) {
        $state = $sslProtocol.Substring(0,1) -eq "-" ? "Disabled" : "Enabled"
        $protocol = $sslProtocol.Substring(1,$sslProtocol.Length-1)
        if (!$protocols.$protocol) {
            $protocols += @{
                $protocol = $state
            }
        }
        else {
            $protocols.$protocol = $state
        }
    }

    $protocols = $protocols.GetEnumerator() | Sort-Object -Property value -Descending | Sort-Object -Property name

    foreach ($protocol in $protocols) {
        $message = "<    $($protocol.name) <.>48> $($protocol.value.ToUpper())"
        $color = $protocol.value -eq "ENABLED" ? "DarkGreen" : "DarkRed"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$color
    }

}

#endregion CONFIGURATION
#region LICENSING

function global:Get-PlatformLicenses {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$View
    )

    $response = Invoke-TsmApiMethod -Method "ProductKeys"

    return $response | Select-Object -Property $($View ? $LicenseView.$($View) : $LicenseView.Default)

}
Set-Alias -Name licGet -Value Get-PlatformLicenses -Scope Global

function global:Show-PlatformLicenses {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][object]$PlatformLicenses=(Get-PlatformLicenses)
    )

    $now = Get-Date
    $30days = New-TimeSpan -days 30
    $90days = New-TimeSpan -days 90
    $colors = @("White","DarkYellow","DarkRed")

    # $PlatformLicenses = Get-PlatformLicenses

    $productColumnHeader = "Product"
    $serialColumnHeader = "Product Key"
    $numCoresColumnHeader = "Cores"
    $userCountColumnHeader = "Users"
    $expirationColumnHeader = "Expiration"
    $maintenanceColumnHeader = "Maintenance"
    $validColumnHeader = "Valid"
    $isActiveColumnHeader = "Active"
    # $expiredColumnHeader = "Expired"

    $productColumnLength = ($productColumnHeader.Length, ($PlatformLicenses.product | Measure-Object -Maximum -Property Length).Maximum | Measure-Object -Maximum).Maximum
    $serialColumnLength = ($serialColumnHeader.Length, ($PlatformLicenses.serial | Measure-Object -Maximum -Property Length).Maximum | Measure-Object -Maximum).Maximum
    $numCoresColumnLength = ($numCoresColumnHeader.Length, 4 | Measure-Object -Maximum).Maximum
    $userCountColumnLength = ($userCountColumnHeader.Length, 4 | Measure-Object -Maximum).Maximum
    $expirationColumnLength = ($expirationColumnHeader.Length, 10 | Measure-Object -Maximum).Maximum
    $maintenanceColumnLength = ($maintenanceColumnHeader.Length, 10 | Measure-Object -Maximum).Maximum
    $validColumnLength = ($validColumnHeader.Length, 5 | Measure-Object -Maximum).Maximum
    $isActiveColumnLength = ($isActiveColumnHeader.Length, 5 | Measure-Object -Maximum).Maximum
    # $expiredColumnLength = ($expiredColumnHeader.Length, 5 | Measure-Object -Maximum).Maximum

    $productColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $productColumnHeader.Length) + (Format-Leader -Character " " -Length $productColumnLength -Adjust (($productColumnHeader.Length)))
    $serialColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $serialColumnHeader.Length) + (Format-Leader -Character " " -Length $serialColumnLength -Adjust (($serialColumnHeader.Length)))
    $numCoresColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $numCoresColumnHeader.Length) + (Format-Leader -Character " " -Length $numCoresColumnLength -Adjust (($numCoresColumnHeader.Length)))
    $userCountColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $userCountColumnHeader.Length) + (Format-Leader -Character " " -Length $userCountColumnLength -Adjust (($userCountColumnHeader.Length)))
    $expirationColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $expirationColumnHeader.Length) + (Format-Leader -Character " " -Length $expirationColumnLength -Adjust (($expirationColumnHeader.Length)))
    $maintenanceColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $maintenanceColumnHeader.Length) + (Format-Leader -Character " " -Length $maintenanceColumnLength -Adjust (($maintenanceColumnHeader.Length)))
    $validColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $validColumnHeader.Length) + (Format-Leader -Character " " -Length $validColumnLength -Adjust (($validColumnHeader.Length)))
    $isActiveColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $isActiveColumnHeader.Length) + (Format-Leader -Character " " -Length $isActiveColumnLength -Adjust (($isActiveColumnHeader.Length)))
    # $expiredColumnHeaderUnderscore = (Format-Leader -Character "-" -Length $expiredColumnHeader.Length) + (Format-Leader -Character " " -Length $expiredColumnLength -Adjust (($expiredColumnHeader.Length)))

    $productColumnHeader += (Format-Leader -Character " " -Length $productColumnLength -Adjust (($productColumnHeader.Length)))
    $serialColumnHeader += (Format-Leader -Character " " -Length $serialColumnLength -Adjust (($serialColumnHeader.Length)))
    $numCoresColumnHeader += (Format-Leader -Character " " -Length $numCoresColumnLength -Adjust (($numCoresColumnHeader.Length)))
    $userCountColumnHeader += (Format-Leader -Character " " -Length $userCountColumnLength -Adjust (($userCountColumnHeader.Length)))
    $expirationColumnHeader += (Format-Leader -Character " " -Length $expirationColumnLength -Adjust (($expirationColumnHeader.Length)))
    $maintenanceColumnHeader += (Format-Leader -Character " " -Length $maintenanceColumnLength -Adjust (($maintenanceColumnHeader.Length)))
    $validColumnHeader += (Format-Leader -Character " " -Length $validColumnLength -Adjust (($validColumnHeader.Length)))
    $isActiveColumnHeader += (Format-Leader -Character " " -Length $isActiveColumnLength -Adjust (($isActiveColumnHeader.Length)))
    # $expiredColumnHeader += (Format-Leader -Character " " -Length $expiredColumnLength -Adjust (($expiredColumnHeader.Length)))

    $indent = Format-Leader -Character " " -Length 6

    Write-Host+ -NoTrace -NoTimestamp $indent,$productColumnHeader,$serialColumnHeader,$numCoresColumnHeader,$userCountColumnHeader,$expirationColumnHeader,$maintenanceColumnHeader,$validColumnHeader,$isActiveColumnHeader #,$expiredColumnHeader
    Write-Host+ -NoTrace -NoTimestamp $indent,$productColumnHeaderUnderscore,$serialColumnHeaderUnderscore,$numCoresColumnHeaderUnderscore,$userCountColumnHeaderUnderscore,$expirationColumnHeaderUnderscore,$maintenanceColumnHeaderUnderscore,$validColumnHeaderUnderscore,$isActiveColumnHeaderUnderscore #,$expiredColumnHeaderUnderscore         

    foreach ($license in $PlatformLicenses) {

        $license.serial = $license.serial -replace "(.{4}-){3}","XXXX-XXXX-XXXX-"
        
        $licenseExpiryDays = $license.expiration - $now
        $maintenanceExpiryDays = $license.maintenance - $now
        $expirationColumnColor = $licenseExpiryDays -le $30days ? 2 : ($licenseExpiryDays -le $90days ? 1 : 0)
        $maintenanceColumnColor = $maintenanceExpiryDays -le $30days ? 2 : ($maintenanceExpiryDays -le $90days ? 1 : 0)
        $productColumnColor = ($expirationColumnColor, $maintenanceColumnColor | Measure-Object -Maximum).Maximum
        
        $productColumnValue = $license.product + (Format-Leader -Character " " -Length $productColumnLength -Adjust (($license.product.Length)))
        $serialColumnValue = $license.serial + (Format-Leader -Character " " -Length $serialColumnLength -Adjust (($license.serial.Length)))
        $numCoresColumnValue = (Format-Leader -Character " " -Length $numCoresColumnLength -Adjust (($license.numCores.ToString().Length))) + $license.numCores.ToString()
        $userCountColumnValue = (Format-Leader -Character " " -Length $userCountColumnLength -Adjust (($license.userCount.ToString().Length))) + $license.userCount.ToString()
        $expirationColumnValue = $license.expiration.ToString('u').Substring(0,10) + (Format-Leader -Character " " -Length $expirationColumnLength -Adjust (($license.expiration.ToString('u').Substring(0,10).Length)))
        $maintenanceColumnValue = $license.maintenance.ToString('u').Substring(0,10) + (Format-Leader -Character " " -Length $maintenanceColumnLength -Adjust (($license.maintenance.ToString('u').Substring(0,10).Length)))
        $validColumnValue = (Format-Leader -Character " " -Length $validColumnLength -Adjust (($license.valid.ToString().Length))) + $license.valid.ToString()
        $isActiveColumnValue = (Format-Leader -Character " " -Length $isActiveColumnLength -Adjust (($license.isActive.ToString().Length))) + $license.isActive.ToString()
        # $expiredColumnValue = $license.expired.ToString() + (Format-Leader -Character " " -Length $expiredColumnLength -Adjust (($license.expired.ToString().Length)))

        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator $indent," ",$productColumnValue," "
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator $serialColumnValue," " -ForegroundColor $colors[$productColumnColor]
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator $numCoresColumnValue," ",$userCountColumnValue," "
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator $expirationColumnValue," " -ForegroundColor $colors[$expirationColumnColor]
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator $maintenanceColumnValue," " -ForegroundColor $colors[$maintenanceColumnColor]
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $validColumnValue," ",$isActiveColumnValue

    }

    Write-Host+

    return

}

function global:Confirm-PlatformLicenses {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$View
    )

    $indent = Format-Leader -Character " " -Length 6

    $leader = Format-Leader -Length 46 -Adjust ((("  EULA Compliance").Length))
    Write-Host+ -NoTrace "  EULA Compliance",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

    $now = Get-Date
    $30days = New-TimeSpan -days 30
    $90days = New-TimeSpan -days 90

    $pass = $true
    
    $platformLicenses = Get-PlatformLicenses
    
    Write-Host+
    Show-PlatformLicenses $platformLicenses

    #region CORE-LICENSING

        $nodeCores = @()
        foreach ($node in Invoke-TsmApiMethod -Method "Nodes") {
            $nodeCores += Invoke-TsmApiMethod -Method "NodeCores" -Params @($node)
        }
        $clusterCores = ($nodeCores | Measure-Object -Sum).Sum

        $coreLicenses = $platformLicenses | Where-Object {$_.product -eq "Server Core" -and $_.valid -and $_.isActive -and $now -lt $_.expiration -and $now -lt $_.maintenance}
        $licensedCores = ($coreLicenses.numCores | Measure-Object -Sum).Sum

        if ($licensedCores -and $licensedCores -lt $clusterCores) {

            $pass = $false

            $subject = "Compliance Issue"
            $summary = "$($Platform.Instance) has $($clusterCores) cores but is only licensed for $($licensedCores) cores."

            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -ForeGroundColor DarkRed $indent,"$($subject.ToUpper()): $($message)"
            Send-LicenseMessage -License $coreLicenses -MessageType $PlatformMessageType.Alert -Subject $subject -Summary $summary | Out-Null
        }

    #endregion CORE-LICENSING

    $expiredLicenses = $PlatformLicenses | Where-Object {$_.licenseExpired}
    $expiredLicenses | ForEach-Object {Write-Host+ -NoTrace -NoTimestamp -ForeGroundColor DarkRed $indent,"EXPIRED: $($_.product) [$($_.serial)] license expired $($_.expiration.ToString('d MMMM yyyy'))"}
    $expiredMaintenance = $PlatformLicenses | Where-Object {$_.maintenanceExpired}
    $expiredMaintenance | ForEach-Object {Write-Host+ -NoTrace -NoTimestamp -ForeGroundColor DarkRed $indent,"EXPIRED: $($_.product) [$($_.serial)] maintenance expired $($_.maintenance.ToString('d MMMM yyyy'))"}

    $expiringLicenses = $PlatformLicenses | Where-Object {$_.licenseExpiry -le $90days}
    $expiringLicenses | ForEach-Object {Write-Host+ -NoTrace -NoTimestamp -ForeGroundColor ($_.licenseExpiry -le $30days ? "DarkRed" : "DarkYellow") $indent,"$($_.licenseExpiry -le $30days ? "URGENT" : "WARNING"): $($_.product) license expires in $([math]::Round($_.licenseExpiry.TotalDays,0)) days on $($_.expiration.ToString('d MMMM yyyy'))"}
    $expiringMaintenance = $PlatformLicenses | Where-Object {$_.maintenanceExpiry -le $90days}
    $expiringMaintenance | ForEach-Object {Write-Host+ -NoTrace -NoTimestamp -ForeGroundColor ($_.maintenanceExpiry -le $30days ? "DarkRed" : "DarkYellow") $indent,"$($_.licenseExpiry -le $30days ? "URGENT" : "WARNING"): $($_.product) maintenance expires in $([math]::Round($_.maintenanceExpiry.TotalDays,0)) days on $($_.maintenance.ToString('d MMMM yyyy'))"}
    
    # Write-Host+ 

    $licenseWarning = @()
    $licenseWarning += [array]$expiredLIcenses + [array]$expiredMaintenance + [array]$expiringLicenses + [array]$expiringMaintenance
    $licenseWarning = $licenseWarning | Sort-Object -Unique -Property serial

    if ($licenseWarning) {

        $subject = "License Issue"
        $summary = "A license, maintenance contract or subscription has expired or is expiring soon."

        Send-LicenseMessage -License $licenseWarning -MessageType $PlatformMessageType.Warning -Subject $subject -Summary $summary | Out-Null
        Write-Host+ # in case anything is written to the console during Send-LicenseMessage

    }

    $leader = Format-Leader -Length 46 -Adjust ((("  EULA Compliance").Length))
    Write-Host+ -NoTrace -NoNewLine "  EULA Compliance",$leader -ForegroundColor Gray,DarkGray
    
    if (!$pass) {
        Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
    }
    else {
        Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen 
    }

    return

}
Set-Alias -Name licCheck -Value Confirm-PlatformLicenses -Scope Global

#endregion LICENSING
#region TESTS

function global:Test-TsmController {

    [CmdletBinding()]
    param ()

    $leader = Format-Leader -Length 46 -Adjust ((("  TSM Controller").Length))
    Write-Host+ -NoTrace "  TSM Controller",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

    $fail = $false
    try {

        $leader = Format-Leader -Length 40 -Adjust ((("    Connect to $($tsmApiConfig.Controller)").Length))
        Write-Host+ -NoTrace -NoNewLine "    Connect to",$tsmApiConfig.Controller,$leader -ForegroundColor Gray,DarkBlue,DarkGray
    
        Initialize-TsmApiConfiguration

        Write-Host+ -NoTrace -NoTimestamp " PASS" -ForegroundColor DarkGreen
    
    }
    catch {

        $fail = $true
        Write-Host+ -NoTrace -NoTimestamp " UNKNOWN" -ForegroundColor DarkRed
    }

    $leader = Format-Leader -Length 46 -Adjust ((("  TSM Controller").Length))
    Write-Host+ -NoTrace -NoNewLine "  TSM Controller",$leader -ForegroundColor Gray,DarkGray

    if ($fail) {

        Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
        Write-Log -Action "Test" -Target "TSMController" -Exception $_.Exception

    }
    else {

        Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen 
        Write-Log -Action "Test" -Target "TSMController" -Status "PASS"
    
    }

}

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

        $templatePath = "$($global:Platform.InstallPath)\packages\templates.$($Platform.Build)\pg_hba.conf.ftl"
        $templateContent = [System.Collections.ArrayList](Get-Content -Path $templatePath)

        if ($templateContent) {
    
            Write-Host+ -NoTimestamp -NoTrace  " PENDING" -ForegroundColor DarkGray

            $subLeader = Format-Leader -Length 36 -Adjust ((("Updating pg_hba.conf.ftl").Length))
            Write-Host+ -NoTrace -NoNewLine "    Updating pg_hba.conf.ftl",$subLeader -ForegroundColor Gray,DarkGray

            $regionBegin = $templateContent.Trim().IndexOf("# region Overwatch")
            $regionEnd = $templateContent.Trim().IndexOf("# endregion Overwatch")

            $savedRows = @()

            if ($regionBegin -ne -1 -and $regionEnd -ne 1) {
                for ($i = $regionBegin+2; $i -le $regionEnd-2; $i++) {
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
                $templateContent.Add("<#if pgsql.readonly.enabled >") | Out-Null
                foreach ($row in $savedRows) {
                    $templateContent.Add($row) | Out-Null
                }
                $templateContent.Add("</#if>") | Out-Null
                $templateContent.Add("# endregion Overwatch") | Out-Null
                $templateContent.Add("") | Out-Null
                $templateContent | Set-Content -Path $templatePath

            }

            Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen
            Write-Log -Action "Test" -Target "pg_hba.conf.ftl" -Status "PASS"

            Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray
            Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen

        }
        else {
            
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
            Write-Log -Action "Test" -Target "pg_hba.conf.ftl" -Status "FAIL" -EntryType "Error" -Message "Invalid format"
            # throw "Invalid format"

            Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 

        }

    }
    catch {
    
        Write-Host+ -NoTimestamp -NoTrace  " FAIL" -ForegroundColor DarkRed 
        Write-Log -Action "Test" -Target "pg_hba.conf.ftl" -Exception $_.Exception
    
    }

}

#endregion TESTS