# $TimeoutSec = 15

#region STATUS

function global:Get-PlatformStatusRollup {
        
    [CmdletBinding()]
    param (
        [switch]$NoCache
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $params = @{}
    if ($NoCache) {$params += @{NoCache = $true}}
    $tableauServerStatus = Get-TableauServerStatus @params

    Write-Verbose "IsOK: $($PlatformStatusOK.Contains($tableauServerStatus.rollupStatus)), Status: $($tableauServerStatus.rollupStatus)"
    # Write-Log -Context "$($MyInvocation.MyCommand)" -Action "Get-TableauServerStatus" -EntryType "Information" -Message "IsOK: $($PlatformStatusOK.Contains($tableauServerStatus.rollupStatus)), Status: $($tableauServerStatus.rollupStatus)" -Force  
    
    return $PlatformStatusOK.Contains($tableauServerStatus.rollupStatus), $tableauServerStatus.rollupStatus, $tableauServerStatus
}

function global:Show-PlatformStatus {

    [CmdletBinding()]
    param(
        [switch]$All
    )

    if ($All -and $Required) {
        throw "The `"All`" and `"Required`" switches cannot be used together"
    }

    # check for platform events
    $platformStatus = Get-PlatformStatus 
    # notify if platform is stopped or if a platform event is in progress
    if ($platformStatus.IsStopped -or (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted)) {
        Write-Host+
        $message = "$($Platform.Name) $($platformStatus.Event.ToUpper()) is $($($PlatformStatus.IsStopped) ? "STOPPED" : $($platformStatus.EventStatus.ToUpper()))"
        Write-Host+ -NoTrace -NoTimeStamp $message -ForegroundColor DarkRed
        Write-Host+
    }

    $platformstatus | Format-List *

    $nodeStatus = (Get-TableauServerStatus).Nodes
    $nodeStatus = $nodeStatus | 
        Select-Object -Property @{Name='NodeId';Expression={$_.nodeId}}, @{Name='Node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId}}, @{Name='Status';Expression={$_.rollupstatus}}
    $nodeStatus | Format-Table -Property Node, Status, NodeId

    $services = Get-PlatformService
    if ($All) {} else { $services = $services | Where-Object {$_.Required} }
    $services | Where-Object {!$_.StatusOK.Contains($_.Status)} | Sort-Object -Property Node, Name | Format-Table -Property Node, Name, Status, Required, Transient, IsOK
    $services | Sort-Object -Property Node, Name | Format-Table -GroupBy Node -Property Node, Name, Status, Required, Transient, IsOK

}
Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global
function global:Build-StatusFacts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][PlatformStatus]$PlatformStatus,
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
    if ($(get-cache platforminfo).Exists()) {
        $platformInfo = Read-Cache platforminfo 
        if ($platformInfo) {
            $global:Platform.Api.TsRestApiVersion = $platformInfo.TsRestApiVersion
            $global:Platform.Version = $platformInfo.Version
            $global:Platform.Build = $platformInfo.Build
            $global:Platform.DisplayName = $global:Platform.Name + " " + $platformInfo.Version
            return
        }
    }
}

$serverInfo = Get-TSServerInfo

$global:Platform.Api.TsRestApiVersion = $serverinfo.restApiVersion
$global:Platform.Version = $serverinfo.productVersion.InnerText
$global:Platform.Build = $serverinfo.productVersion.build
$global:Platform.DisplayName = $global:Platform.Name + " " + $global:Platform.Version

$platformInfo = @{
    Version=$global:Platform.Version
    Build=$global:Platform.Build
    TsRestApiVersion=$global:Platform.Api.TsRestApiVersion
}

$platformInfo | Write-Cache platforminfo

return

}

#endregion PLATFORMINFO
#region SERVICE

function global:Get-PlatformService {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Online -Keys),
    [Parameter(Mandatory=$false)][string]$View,
    [switch]$ResetCache
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

if ($(get-cache platformservices).Exists() -and !$ResetCache) {
    Write-Debug "Read-Cache platformservices"
    $platformServicesCache = Read-Cache platformservices -MaxAge $(New-TimeSpan -Minutes 1)
    if ($platformServicesCache) {
        $platformServices = $platformServicesCache
        return $platformServices
    }
}

$platformTopology = Get-PlatformTopology
$tableauServerStatus = Get-TableauServerStatus

Write-Debug "Processing PlatformServices"
if ($tableauServerStatus) {
    $platformServices = 
        foreach ($nodeId in $tableauServerStatus.nodes.nodeId) {
            $node = $platformTopology.Alias.$nodeId                   
            $services = ($tableauServerStatus.nodes | Where-Object {$_.nodeid -eq $nodeId}).services
            $services | Foreach-Object {
                $service = $_
                @(
                    [PlatformCim]@{
                        Name = $service.ServiceName
                        DisplayName = $service.ServiceName
                        Class = "Service"
                        Node = $node
                        Required = $service.rollupRequestedDeploymentState -eq "Enabled"
                        Status = $service.rollupStatus
                        StatusOK = @("Active","Running")
                        IsOK = @("Active","Running").Contains($service.rollupStatus)
                        Instance = $service.instances
                    }
                )
            }
        }
}      

Write-Debug "Write-Cache platformservices"
$platformServices | Write-Cache platformservices

return $platformServices | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)
}

function global:Request-Platform {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][ValidateSet("Stop","Start")][string]$Command,
    [Parameter(Mandatory=$false)][string]$Context = "Command",
    [Parameter(Mandatory=$false)][string]$Reason = "$Command requested."
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Write-Host+
Write-Host+ -NoTrace -NoSeparator "$($global:Platform.Name)" -ForegroundColor DarkBlue
$message = "<  Command <.>25> $($Command.ToUpper())"
Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($Command -eq "Start" ? "Green" : "Red")
$message = "<  Reason <.>25> $Reason"
Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkBlue

Write-Log -Context $Context -Action $Command -Status $PlatformEventStatus.InProgress -Message "$($global:Platform.Name) $($Command.ToUpper())"

$commandStatus = $PlatformEventStatus.InProgress
Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus

# preflight checks
if ($Command -eq "Start") {
    Update-Preflight
}

try {

    $asyncJob = Invoke-TsmApiMethod -Method $Command
    Watch-AsyncJob -Id $asyncJob.Id -Context $Context -NoEventManagement -NoMessaging
    $asyncJob = Wait-AsyncJob -Id $asyncJob.id -Context $Context -TimeoutSeconds 1800 -ProgressSeconds -60

    if ($asyncJob.status -eq $global:tsmApiConfig.Async.Status.Failed) {
        $message = "Platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) has $($asyncJob.status). $($asyncJob.errorMessage)"
        Write-Log -Context $Context -Action $Command -EntryType "Warning" -Status "Failure" -Message $message
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkRed
        throw
    } 
    elseif ($asyncJob.status -eq $global:tsmApiConfig.Async.Status.Cancelled) {
        $message = "Platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) was $($asyncJob.status). $($asyncJob.errorMessage)"
        Write-Log -Context $Context -Action $Command -EntryType "Warning" -Status "Cancelled" -Message $message
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkYellow
    }
    elseif ($asyncJob.status -ne $global:tsmApiConfig.Async.Status.Succeeded) {
        $message = "Timeout waiting for platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) to complete. $($asyncJob.statusMessage)"
        Write-Log -Context $Context -Action $Command -EntryType "Warning" -Status "Timeout" -Message $message
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkYellow
    }

    $commandStatus = $PlatformEventStatus.Completed

    # preflight checks
    if ($Command -eq "Start") {
        Confirm-PostFlight
    }
}
catch {
    $commandStatus = $PlatformEventStatus.Failed
}

Watch-AsyncJob -Remove -Id $asyncJob.Id -Context $Context -NoEventManagement -NoMessaging

$message = "<  $($Command.ToUpper()) <.>25> $($commandStatus.ToUpper())"
Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($commandStatus -eq $PlatformEventStatus.Completed ? "Green" : "Red")
Write-Host+

Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus

Write-Log -Context $Context -Action $Command -Status $commandStatus -Message "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"

if ($commandStatus -eq $PlatformEventStatus.Failed) {throw "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"}

return
}

function global:Start-Platform {

[CmdletBinding()] param (
    [Parameter(Mandatory=$false)][string]$Context = "Command",
    [Parameter(Mandatory=$false)][string]$Reason = "Start Platform"
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Request-Platform -Command Start -Context $Context -Reason $Reason
}
function global:Stop-Platform {

[CmdletBinding()] param (
    [Parameter(Mandatory=$false)][string]$Context = "Command",
    [Parameter(Mandatory=$false)][string]$Reason = "Stop platform"
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Request-Platform -Command Stop -Context $Context -Reason $Reason
}
function global:Restart-Platform {

[CmdletBinding()] param ()

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Stop-Platform
Start-Platform

}

#endregion SERVICE
#region PROCESS

function global:Get-PlatformProcess {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Online -Keys),
    [Parameter(Mandatory=$false)][string]$View,
    [switch]$ResetCache
)

Write-Debug "$($MyInvocation.MyCommand) is a STUB"
return

}

#endregion PROCESS
#region BACKUP

function global:Cleanup-Platform {

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

[CmdletBinding()] param(
    [Parameter(Mandatory=$false)][timespan]$LogFilesRetention = (New-TimeSpan -Days 7)
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

# Watch-AsyncJob (Tableau Server) will handle messaging instead of Send-TaskMessage
# Send-TaskMessage -Id "Cleanup" -Status "Running"

#region PURGE

    # purge backup files
    Remove-Files -Path $Backup.Path -Keep $Backup.Keep -Filter "*.$($Backup.Extension)" 
    Remove-Files -Path $Backup.Path -Keep $Backup.Keep -Filter "*.json" 
    
#endregion CLEANUP
#region CLEANUP

    $cleanupOptions = @(
        $LogFilesRetention.TotalSeconds.ToString(),     # logFilesRetentionSeconds
        "True",                                         # deleteLogFiles
        "True",                                         # deleteTempFiles
        "False",                                        # clearRedisCache
        "False",                                        # deleteHttpRequests
        "False"                                         # clearSheetImageCache
    )

    try {

        # . tsm maintenance cleanup -l --log-files-retention $LogFilesRetention -t
        $cleanupAsyncJob = Invoke-TsmApiMethod -Method "Cleanup" -Params $cleanupOptions
        Watch-AsyncJob -Id $cleanupAsyncJob.id -Context "Cleanup" # -Callback "Invoke-AsyncJobCallback"

        Write-Log -Context "Cleanup" -Action "Cleanup" -Target "asyncJob $($cleanupAsyncJob.id)" -Status $cleanupAsyncJob.status -Message $cleanupAsyncJob.statusMessage
        # Write-Information "asyncJob $($cleanupAsyncJob.id): $($cleanupAsyncJob.statusMessage)"

    }
    catch {

        Write-Log -Context "Cleanup" -EntryType "Error" -Action "Cleanup" -Status "Error" -Message $_.Exception.Message
        Write-Error "$($_.Exception.Message)"

        # Watch-AsyncJob (Tableau Server) will handle messaging instead of Send-TaskMessage
        # Send-TaskMessage -Id "Cleanup" -Status "Error" -Message $_.Exception.Message -MessageType $PlatformMessageType.Alert
        
    }

#endregion CLEANUP

return

}

function global:Get-BackupFileName {

$global:Backup.Name = "$($global:Environ.Instance).$(Get-Date -Format 'yyyyMMddHHmm')"
$global:Backup.File = "$($Backup.Name).$($Backup.Extension)"

return $global:Backup.File

}

function global:Backup-Platform {

[CmdletBinding()] param()

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Write-Log -Context "Backup" -Action "Backup" -Target "Platform" -Status "Running"
Write-Information "Running"
Send-TaskMessage -Id "Backup" -Status "Running"

#region EXPORT-CONFIG

    Write-Log -Context "Backup" -Action "Export" -Target "Configuration" -Status "Running"
    Write-Information "ExportConfigurationAndTopologySettings: Running"
    
    try {

        $response = Invoke-TsmApiMethod -Method "ExportConfigurationAndTopologySettings"
        $response | ConvertTo-Json -Depth 99 | Out-File "$($Backup.Path)\$($Backup.File).json" 

        Write-Log -Context "Backup" -Action "Export" -Target "Configuration" -Status "Completed"
        Write-Information "ExportConfigurationAndTopologySettings: Completed"

    }
    catch {

        Write-Log -EntryType "Warning" -Context "Backup" -Action "Export" -Target "Configuration" -Status "Error" -Message $_.Exception.Message
        Write-Warning "ExportConfigurationAndTopologySettings: $($_.Exception.Message)"

    }

#endregion EXPORT-CONFIG
#region BACKUP

    try {

        $backupAsyncJob = Invoke-TsmApiMethod -Method "Backup" -Params @(Get-BackupFileName)
        Watch-AsyncJob -Id $backupAsyncJob.id -Context "Backup" # -Callback "Invoke-AsyncJobCallback"

        Write-Log -Context "Backup" -Action "Backup" -Target "asyncJob $($backupAsyncJob.id)" -Status $backupAsyncJob.status -Message $backupAsyncJob.statusMessage
        Write-Information "asyncJob $($backupAsyncJob.id): $($backupAsyncJob.statusMessage)"

    }
    catch {

        Write-Log -EntryType "Error" -Action "Backup" -Status "Error" -Message $_.Exception.Message
        Write-Error "$($_.Exception.Message)"

        Send-TaskMessage -Id "Backup" -Status "Error" -Message $_.Exception.Message -MessageType $PlatformMessageType.Alert
        
    }

#endregion BACKUP

return
}

function global:Invoke-AsyncJobCallback {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=1)][string]$Id
)

$asyncJob = Get-AsyncJob -Id $Id
$asyncJobProduct = Get-Product -Name $(switch ($asyncJob.jobtype) {
        "GenerateBackupJob" { "Backup" }
        "CleanupJob" { "Cleanup" }
    })

if ($asyncJob.status -eq $global:tsmApiConfig.Async.Status.Cancelled) {

    Write-Log -EntryType "Warning" -Context $asyncJobProduct.Id -Action $asyncJobProduct.Id -Target "asyncJob $($asyncJob.id)" -Status $asyncJob.status -Message $asyncJob.statusMessage
    Write-Warning "asyncJob $($asyncJob.id): $($asyncJob.statusMessage)"
    Send-TaskMessage -Id $asyncJobProduct.Id -Status "Warning" -Message $asyncJob.statusMessage -MessageType $PlatformMessageType.Warning

    return

} 
elseif ($asyncJob.status -ne $global:tsmApiConfig.Async.Status.Succeeded) {

    Write-Log -EntryType "Error" -Context $asyncJobProduct.Id -Action $asyncJobProduct.Id -Target "asyncJob $($asyncJob.id)" -Status $asyncJob.status -Message $asyncJob.statusMessage
    Write-Error "asyncJob $($asyncJob.id): $($asyncJob.statusMessage)"
    Send-TaskMessage -Id $asyncJobProduct.Id -Status "Error" -Message $asyncJob.statusMessage -MessageType $PlatformMessageType.Alert

    return

} 
else {

    Send-TaskMessage -Id $asyncJobProduct.Id -Status "Completed"
    
    return
} 
}

#endregion BACKUP
#region TOPOLOGY

function global:Initialize-PlatformTopology {

[CmdletBinding()]
param (
    [switch]$ResetCache
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

if (!$ResetCache) {
    if ($(get-cache platformtopology).Exists()) {
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
    if (![string]::IsNullOrEmpty($global:RegexPattern.PlatformTopology.Alias.Match)) {
        if ($node -match $RegexPattern.PlatformTopology.Alias.Match) {
            $ptAlias = ""
            foreach ($i in $global:RegexPattern.PlatformTopology.Alias.Groups) {
                $ptAlias += $Matches[$i]
            }
            $platformTopology.Alias.($ptAlias) = $node
        }
    }

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

function global:Get-ConfigurationKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][Alias("K")][string]$Key
    )

    $currentConfigurationVersion = Invoke-TsmApiMethod -Method "ConfigurationsRequestedVersion"
    $value = Invoke-TsmApiMethod -Method "ConfigurationKey" -Params @($currentConfigurationVersion, $Key)
    return $value
}

function global:Show-TSSslProtocols {

    Write-Host+ -NoTrace "  Tableau Server SSL Protocols" -ForegroundColor DarkBlue

    $sslProtocolsAll = "+SSLv2 +SSLv3 +TLSv1 +TLSv1.1 +TLSv1.2 +TLSv1.3"
    $sslProtocols = Get-ConfigurationKey -Key "ssl.protocols"
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
        $message = "<    $($protocol.name) <.>25> $($protocol.value.ToUpper())"
        $color = $protocol.value -eq "ENABLED" ? "DarkGreen" : "DarkRed"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$color -NoSeparator
    }

}

#endregion CONFIGURATION
#region LICENSING

function global:Get-PlatformLicenses {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$View
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $indent = Format-Leader -Character " " -Length 6

    $leader = Format-Leader -Length 47 -Adjust ((("  EULA Compliance").Length))
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
            Send-LicenseMessage -License $coreLicenses -MessageType $PlatformMessageType.Alert -Subject $subject -Summary $summary
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
    
    Write-Host+ 

    $licenseWarning = @()
    $licenseWarning += [array]$expiredLIcenses + [array]$expiredMaintenance + [array]$expiringLicenses + [array]$expiringMaintenance
    $licenseWarning = $licenseWarning | Sort-Object -Unique -Property serial

    if ($licenseWarning) {

        $subject = "License Issue"
        $summary = "A license, maintenance contract or subscription has expired or is expiring soon."

        Send-LicenseMessage -License $licenseWarning -MessageType $PlatformMessageType.Warning -Subject $subject -Summary $summary
        Write-Host+ # in case anything is written to the console during Send-LicenseMessage

    }

    $leader = Format-Leader -Length 47 -Adjust ((("  EULA Compliance").Length))
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $leader = Format-Leader -Length 47 -Adjust ((("  TSM Controller").Length))
    Write-Host+ -NoTrace "  TSM Controller",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

    $fail = $false
    try {

        $leader = Format-Leader -Length 39 -Adjust ((("    Connect to $($tsmApiConfig.Controller)").Length))
        Write-Host+ -NoTrace -NoNewLine "    Connect to",$tsmApiConfig.Controller,$leader -ForegroundColor Gray,DarkBlue,DarkGray
    
        Initialize-TsmApiConfiguration

        Write-Host+ -NoTrace -NoTimestamp " PASS" -ForegroundColor DarkGreen
    
    }
    catch {

        $fail = $true
        Write-Host+ -NoTrace -NoTimestamp " UNKNOWN" -ForegroundColor DarkRed
    }

    $leader = Format-Leader -Length 47 -Adjust ((("  TSM Controller").Length))
    Write-Host+ -NoTrace -NoNewLine "  TSM Controller",$leader -ForegroundColor Gray,DarkGray

    if ($fail) {

        Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
        Write-Log -Context "Preflight" -Action "Test" -Target "TSMController" -Status "FAIL" -EntryType "Error" -Message $_.Exception.Message
        # throw "$($_.Exception.Message)"

    }
    else {

        Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen 
        Write-Log -Context "Preflight" -Action "Test" -Target "TSMController" -Status "PASS"
    
    }

}

function global:Test-RepositoryAccess {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string[]]$ComputerName
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $leader = Format-Leader -Length 47 -Adjust ((("  Postgres Access").Length))
    Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray

    try {

        $templatePath = "$($global:Platform.InstallPath)\packages\templates.$($Platform.Build)\pg_hba.conf.ftl"
        $templateContent = [System.Collections.ArrayList](Get-Content -Path $templatePath)

        if ($templateContent) {
    
            Write-Host+ -NoTimestamp -NoTrace  " PENDING" -ForegroundColor DarkGray

            $subLeader = Format-Leader -Length 35 -Adjust ((("Updating pg_hba.conf.ftl").Length))
            Write-Host+ -NoTrace -NoNewLine "    Updating pg_hba.conf.ftl",$subLeader -ForegroundColor Gray,DarkGray

            $regionBegin = $templateContent.Trim().IndexOf("# region Overwatch")
            $regionEnd = $templateContent.Trim().IndexOf("# endregion Overwatch")

            $savedRows = @()

            if ($regionBegin -ne -1 -and $regionEnd -ne 1) {
                for ($i = $regionBegin+2; $i -le $regionEnd-2; $i++) {
                    $savedRows += $templateContent[$i].Trim()
                }
                $templateContent.RemoveRange($regionBegin,$regionEnd-$regionBegin+2)
            }

            $newRows = $false
            foreach ($node in $ComputerName) {
                $newRow = "host all readonly $(Get-IpAddress $node)/32 md5"
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
            Write-Log -Context "Preflight" -Action "Test" -Target "pg_hba.conf.ftl" -Status "PASS"

            Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray
            Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen

        }
        else {
            
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
            Write-Log -Context "Preflight" -Action "Test" -Target "pg_hba.conf.ftl" -Status "FAIL" -EntryType "Error" -Message "Invalid format"
            # throw "Invalid format"

            Write-Host+ -NoNewline -NoTrace "  Postgres Access",$leader -ForegroundColor Gray,DarkGray
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 

        }

    }
    catch {
    
        Write-Host+ -NoTimestamp -NoTrace  " FAIL" -ForegroundColor DarkRed 
        Write-Log -Context "Preflight" -Action "Test" -Target "pg_hba.conf.ftl" -Status "FAIL" -EntryType "Error" -Message $_.Exception.Message
        # throw "$($_.Exception.Message)"
    
    }

}

#endregion TESTS
#region PLATFORM NOTIFICATION



#endregion PLATFORM NOTIFICATION