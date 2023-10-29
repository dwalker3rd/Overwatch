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

    $thisNode = $env:COMPUTERNAME.ToLower()
    
    $platformTopology = @{
        Nodes = @{
            $thisNode = @{
                ReadOnly = $true
                Components = @{
                    Monitor = @{
                        Instances = @{}
                    }
                }
            }
        }
        Alias = @{
            $thisNode = $thisNode
        }
        Components = @{
            Monitor = @{
                Name = "Monitor"
                Nodes = @{
                    $thisNode = @{}
                }
            }
        }
    }
    
    $platformTopology | Write-Cache platformtopology
    
    return $platformTopology
    
}
Set-Alias -Name ptInit -Value Initialize-PlatformTopology -Scope Global

function global:Get-PlatformStatusRollup {
    
    [CmdletBinding()]
    param (
        [switch]$ResetCache,
        [switch]$Quiet
    )

    $monitor = Get-PlatformTask -Id Monitor
    $issues = $monitor.Instance | Where-Object {$_.Required -and $_.Class -in ("Task") -and !$_.IsOK} | 
        Select-Object -Property Node, Class, Name, Status, @{Name="Component";Expression={"$_.Component -join ", "}"}}, ParentName

    $isOK = $monitor.IsOK
    $rollupStatus = switch ($monitor) {
        {$_.Status -in @("Running","Ready","Queued")} { "Running" }
        {$_.Status -eq "Disabled"} { "Stopped" }
        default { $_.Status }
    }

    return $isOK, $rollupStatus, $issues, $monitor.Instance

}

function global:Build-StatusFacts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$PlatformStatus,
        [Parameter(Mandatory=$true)][string]$Node,
        [switch]$ShowAll
    )

    $platformTopology = Get-PlatformTopology
    $cimInstance = $platformStatus.ByCimInstance |  
        Where-Object { $_.Node -eq $Node -and $_.Class -in 'Task' -and $_.ProductID -eq "Monitor"}

    $facts = @(
        $cimInstance | ForEach-Object {
            if (!$_.IsOK -or $ShowAll) {
                foreach ($component in $platformTopology.Nodes.$node.Components.Keys) {
                    @{
                        name = $component
                        value = "**$($_.Status.ToUpper())**"
                    }
                }
            }
        }  
    ) 

    return $facts
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

    $platformStatus = Get-PlatformStatus -ResetCache
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

        $message = "<  $($env:COMPUTERNAME) <.>38> $($platformStatus.RollupStatus)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

        Write-Host+ -NoTrace -Parse "<  $($global:Platform.Instance) <.>38> $($_platformStatusRollupStatus)" -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

    #endregion STATUS      
    #region EVENTS    

        if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {

            Write-Host+

            Write-Host+ -NoTrace -Parse "<  Event <.>38> $($platformStatus.Event)" -ForegroundColor Gray,DarkGray, $global:PlatformEventColor.($platformStatus.Event)
            Write-Host+ -NoTrace -Parse "<  EventStatus <.>38> $($global:PlatformEventStatus.($platformStatus.EventStatus))" -ForegroundColor Gray,DarkGray, $global:PlatformEventStatusColor.($platformStatus.EventStatus)
            Write-Host+ -NoTrace -Parse "<  EventCreatedBy <.>38> $($platformStatus.EventCreatedBy)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -Parse "<  EventCreatedAt <.>38> $($platformStatus.EventCreatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $(!$platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventUpdatedAt <.>38> $($platformStatus.EventUpdatedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -Iff $($platformStatus.EventHasCompleted) -NoTrace -Parse "<  EventCompletedAt <.>38> $($platformStatus.EventCompletedAt)" -ForegroundColor Gray,DarkGray, Gray
            Write-Host+ -NoTrace -Parse "<  EventHasCompleted <.>38> $($platformStatus.EventHasCompleted)" -ForegroundColor Gray,DarkGray, "$($global:PlatformStatusBooleanColor.($platformStatus.EventHasCompleted))"

            # Show-PlatformEvent -PlatformStatus $platformStatus

        }

    #endregion EVENTS     
    #region ISSUES

        $platformIssues = $platformStatus.platformIssues
        if ($Issues -and $platformIssues) {
            $platformIssues = $platformIssues | 
                Select-Object -Property @{Name='Node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId}}, @{Name='Service';Expression={"$($_.name)_$($_.instanceId)"}}, @{Name='Status';Expression={$_.processStatus}}, @{Name='Message';Expression={$_.message}}
            $platformIssues | Format-Table -Property Node, Service, Status, Message
        }

    #endregion ISSUES
    #region SERVICES

        if ($All -or ($Issues -and $platformIssues)) {
            $services = Get-PlatformServices
            if ($Required) { $services = $services | Where-Object {$_.Required} }
            if ($Issues) { $services = $services | Where-Object {!$_.StatusOK.Contains($_.Status)} }
            $services | Select-Object Node, @{Name='NodeId';Expression={ptGetAlias $_.Node}}, Class, Name, Status, Required, Transient, IsOK | 
                Sort-Object -Property Node, Name | Format-Table -GroupBy Node -Property Node, NodeId, Class, Name, Status, Required, Transient, IsOK
        }

    #endregion SERVICES

    Write-Host+ -Iff $(!$All -or !$platformStatus.Issues)

    $message = "<$($global:Platform.Instance) Status <.>48> $($_platformStatusRollupStatus.ToUpper())"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$global:PlatformStatusColor.($platformStatus.RollupStatus)

    Write-Host+

}
Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global