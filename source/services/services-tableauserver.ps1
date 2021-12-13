# $TimeoutSec = 15

#region STATUS

    function global:Get-TableauServerStatus {

        [CmdletBinding()] 
        param (
            [switch]$ResetCache,
            [switch]$NoCache
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $tableauServerStatus = $null

        $action = "Read-Cache"
        $target = "clusterstatus"
        $attemptMessage = ""

        if ((get-cache clusterstatus).Exists() -and !$ResetCache -and !$NoCache) {
            
            Write-Debug "$($action) $($target): Pending"

            # need to cache for back-to-back calls, but ... MaxAge should be as short as possible
            $tableauServerStatus = Read-Cache clusterstatus -MaxAge $(New-TimeSpan -Seconds 5)

            if ($tableauServerStatus) {
                
                Write-Debug "$($action) $($target): Success"

                return $tableauServerStatus

            }
            else {

                Write-Debug "$($action) $($target): Cache empty or expired"

            }
        }
        
        $attempt = 1
        $maxAttempts = 3
        $sleepSeconds = 5

        $action = "Query"
        $target = "TSM API"
        $attemptMessage = "Attempt #<0>"

        do {

            Write-Debug "$($action) $($target) ($($attemptMessage.replace("<0>", $attempt))): Pending"
            
            try {

                # Invoke-TsmApiMethod (1st attempt)
                $tableauServerStatus = Invoke-TsmApiMethod -Method "ClusterStatus"

                Write-Debug "$($action) $($target) ($($attemptMessage.replace("<0>", $attempt))): Success"

            }
            catch {

                if ($attempt -eq $maxAttempts) {
                    Write-Error -Message $_.Exception
                    Write-Error "$($action) $($target) ($($attemptMessage.replace("<0>", $attempt))): Failure"
                    Write-Log -Context "TableauServerStatus" -Action $action -Target $target -EntryType "Error" -Message $_.Exception.Message -Status "Failure"
                    Write-Log -Context "TableauServerStatus" -Action $action -Target $target -EntryType "Error" -Message $attemptMessage.replace("<0>", $attempt) -Status "Failure"
                }

                # give the TSM API a moment to think it over
                Write-Debug "Waiting $($sleepSeconds) before retrying ... "
                Start-Sleep -Seconds $sleepSeconds

            }

            $attempt++
            
        } until ($tableauServerStatus -or $attempt -gt $maxAttempts)

        if ($tableauServerStatus) {
            
            # if Tableau Server's rollupStatus is DEGRADED
            if ($tableauServerStatus.rollupStatus -eq "Degraded") {

                # modify the rollupStatus of services with the following serviceNames and instance.messages
                # TODO: convert this to rules-based logic (using a CSV file)
                foreach ($service in $tableauServerStatus.nodes.services) { 
                    foreach ($instance in $service.instances) {
                        switch ($service.serviceName) {
                            "backgrounder" {
                                if ($instance.message -like "Error opening named pipe*") {
                                    $instance.message = "Scheduled restart"
                                    $service.rollupStatus = "Running"
                                }
                            }
                        }
                    }
                }
                
                # enabled services (other than those excluded above) with a DEGRADED rollupStatus
                $tableauServerServicesNotOK = $tableauServerStatus.nodes.services | 
                    Where-Object {$_.rollupRequestedDeploymentState -eq "Enabled" -and !$PlatformStatusOK.Contains($_.rollupStatus)}
                # if there are no enabled services (other than those excluded above) with a DEGRADED status, then change Tableau Server's rollupStatus to RUNNING
                if (!$tableauServerServicesNotOK) {
                    $tableauServerStatus.rollupStatus = "Running"
                }

            }    
            $tableauServerStatus | Write-Cache "clusterstatus"
        }

        return $tableauServerStatus

    }

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
            [Parameter(Mandatory=$false)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Reason,
            [Parameter(Mandatory=$false)][string]$RunId
        )

        $Nodes = $true
        $Components = $true

        if ($Nodes) {
            $nodeStatus = (Get-TableauServerStatus).Nodes
            $nodeStatus = $nodeStatus | 
                Select-Object -Property @{Name='NodeId';Expression={$_.nodeId}}, @{Name='Node';Expression={Get-PlatformTopologyAlias -Alias $_.nodeId}}, @{Name='Status';Expression={$_.rollupstatus}}

            $nodeStatus | Format-Table -Property Node, Status, NodeId
        }

        if ($Components) {
            Get-PlatformService | Where-Object -Property Required -EQ "True" | Sort-Object -Property Node, Name | Format-Table -GroupBy Node -Property Node, Name, Status, Required, Transient, IsOK
        }

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
                                value = "$($instance.processStatus)" + ($msg ? ", $($msg)" : "")
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

        $params = @{ResetCache = $ResetCache.IsPresent}
        Get-TSServerInfo @params | Out-Null

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

        $verb = switch ($Command) {
            "Stop" {"Stopping"}
            "Start" {"Starting"}
        }

        $message = "$verb $($global:Platform.Name) : PENDING"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray 

        Write-Log -Context $Context -Action $Command -Status $PlatformEventStatus.InProgress -Message "$($global:Platform.Name) $($Command.ToUpper())"

        $commandStatus = $PlatformEventStatus.InProgress
        Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus

        # preflight checks
        if ($Command -eq "Start") {
            Update-Preflight
        }

        try {

            $asyncJob = Invoke-TsmApiMethod -Method $Command
            # Watch-AsyncJob -Id $asyncJob.id -Context "Request-Platform" -Callback "Request-PlatformCallback -Id $($asyncJob.id) -Command $($Command)"
            $asyncJob = Wait-AsyncJob -Id $asyncJob.id -TimeoutSeconds 1800 -ProgressSeconds -60

            if ($asyncJob.status -eq $global:tsmApiConfig.Status.Async.Failed) {
                Write-Log -Context $Context -Action $Command -EntryType "Warning" -Status "Failure" -Message "Platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) has $($asyncJob.status). $($asyncJob.errorMessage)"
                Write-Error "Platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) has $($asyncJob.status). $($asyncJob.errorMessages)"
                throw
            } 
            elseif ($asyncJob.status -ne $global:tsmApiConfig.Status.Async.Succeeded) {
                Write-Log -Context $Context -Action $Command -EntryType "Warning" -Status "Timeout" -Message "Timeout waiting for platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) to complete. $($asyncJob.statusMessage)"
                Write-Warning "Timeout waiting for Platform $($Command.ToUpper()) (async job id: $($asyncJob.id)) to complete. $($asyncJob.statusMessage)"
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

        $message = "$verb $($global:Platform.Name) : $($commandStatus.ToUpper())"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($commandStatus -eq $PlatformEventStatus.Completed ? "Green" : "Red")

        Set-PlatformEvent -Event $Command -Context $Context -EventReason $Reason -EventStatus $commandStatus
        
        Write-Log -Context $Context -Action $Command -Status $commandStatus -Message "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"
        Write-Information  "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"
        
        if ($commandStatus -eq $PlatformEventStatus.Failed) {throw "$($global:Platform.Name) $($Command.ToUpper()) $($commandStatus)"}

        return
    }

    function global:Start-Platform {

        [CmdletBinding()] param (
            [Parameter(Mandatory=$false)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Reason
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        Request-Platform -Command Start -Context $Context -Reason $Reason
    }
    function global:Stop-Platform {

        [CmdletBinding()] param (
            [Parameter(Mandatory=$false)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Reason
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

        Send-TaskMessage -Id "Cleanup" -Status "Running"

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
                Watch-AsyncJob -Id $cleanupAsyncJob.id -Context "Cleanup" -Callback "Invoke-AsyncJobCallback"

                Write-Log -Context "Cleanup" -Action "Cleanup" -Target "asyncJob $($cleanupAsyncJob.id)" -Status $cleanupAsyncJob.status -Message $cleanupAsyncJob.statusMessage
                Write-Information "asyncJob $($cleanupAsyncJob.id): $($cleanupAsyncJob.statusMessage)"

            }
            catch {

                Write-Log -Context "Cleanup" -EntryType "Error" -Action "Cleanup" -Status "Error" -Message $_.Exception.Message
                Write-Error "$($_.Exception.Message)"

                Send-TaskMessage -Id "Cleanup" -Status "Error" -Message $_.Exception.Message -MessageType $PlatformMessageType.Alert
                
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
                Watch-AsyncJob -Id $backupAsyncJob.id -Context "Backup" -Callback "Invoke-AsyncJobCallback"

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

        if ($asyncJob.status -eq $global:tsmApiConfig.Status.Async.Cancelled) {

            Write-Log -EntryType "Warning" -Context $asyncJobProduct.Id -Action $asyncJobProduct.Id -Target "asyncJob $($asyncJob.id)" -Status $asyncJob.status -Message $asyncJob.statusMessage
            Write-Warning "asyncJob $($asyncJob.id): $($asyncJob.statusMessage)"
            Send-TaskMessage -Id $asyncJobProduct.Id -Status "Warning" -Message $asyncJob.statusMessage -MessageType $PlatformMessageType.Warning

            return

        } 
        elseif ($asyncJob.status -ne $global:tsmApiConfig.Status.Async.Succeeded) {

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
#region TSMAPI
    
    function global:Initialize-TsmApiConfiguration {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$Server, # TODO: Validate $Server
            [switch]$ResetCache
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $global:tsmApiConfig = @{
            Server = $Server ? $Server : "localhost"
            Port = "8850"
            ApiVersion = "0.5"
            Credentials = "localadmin-$($global:Platform.Instance)"
            Status = @{
                Async = @{
                    Succeeded = "Succeeded"
                    Created = "Created"
                    Running = "Running"
                    Failed = "Failed"
                    Cancelled = "Cancelled"
                    Queued = "Queued"
                } 
            }
        }
        $global:tsmApiConfig.ApiUri = "https://$($global:tsmApiConfig.Server):$($global:tsmApiConfig.Port)/api/$($global:tsmApiConfig.ApiVersion)"
        $global:tsmApiConfig.Method = @{
            Bootstrap = @{
                Path = "$($global:tsmApiConfig.ApiUri)/bootstrap"
                HttpMethod = "GET"
                Response = @{Keys = "initialBootstrapSettings"}
            }
            Login = @{
                Path = "$($global:tsmApiConfig.ApiUri)/login"
                HttpMethod = "POST"
                Headers = @{"Content-Type" = "application/json"}
                Body = @{
                    authentication = @{
                        name = "<0>"
                        password = "<1>"
                    }
                } | ConvertTo-Json
                Response = @{Keys = ""}
            }      
        }       

        $global:tsmApiConfig.Session = New-TsmApiSession
        $bootstrap = Invoke-TsmApiMethod -Method "Bootstrap"

        $global:tsmApiConfig.Controller += $bootstrap.machineAddress
        $global:tsmApiConfig.Server = $bootstrap.machineAddress -eq $env:COMPUTERNAME.ToLower() ? "localhost" : $bootstrap.machineAddress
        $global:tsmApiConfig.ApiUri = "https://$($global:tsmApiConfig.Server):$($global:tsmApiConfig.Port)/api/$($global:tsmApiConfig.ApiVersion)"

        $global:tsmApiConfig.Method = @{
            Bootstrap = @{
                Path = "$($global:tsmApiConfig.ApiUri)/bootstrap"
                HttpMethod = "GET"
                Response = @{Keys = "initialBootstrapSettings"}
            }
            Login = @{
                Path = "$($global:tsmApiConfig.ApiUri)/login"
                HttpMethod = "POST"
                Headers = @{"Content-Type" = "application/json"}
                Body = @{
                    authentication = @{
                        name = "<0>"
                        password = "<1>"
                    }
                } | ConvertTo-Json
                Response = @{Keys = ""}
            }
            Logout = @{
                Path = "$($global:tsmApiConfig.ApiUri)/logout"
                HttpMethod = "POST"
            }
            TopologiesRequestedVersion = @{
                Path = "$($global:tsmApiConfig.ApiUri)/topologies/requested/version"
                HttpMethod = "GET"
                Response = @{Keys = "version"}
            }
            Topology = @{
                Path = "/topologies/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "topologyVersion.nodes"}
            }
            Nodes = @{
                Path = "$($global:tsmApiConfig.ApiUri)/nodes"
                HttpMethod = "GET"
                Response = @{Keys = "clusterNodes.nodes"}
            }
            NodeInfo = @{
                Path = "$($global:tsmApiConfig.ApiUri)/nodes/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "nodeInfo"}
            }            
            NodeHost = @{
                Path = "$($global:tsmApiConfig.ApiUri)/nodes/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "nodeInfo.address"}
            }
            NodeCores = @{
                Path = "$($global:tsmApiConfig.ApiUri)/nodes/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "nodeInfo.processorCount"}
            }
            RepositoryNodeInfo = @{
                Path = "$($global:tsmApiConfig.ApiUri)/repository/currentMaster"
                HttpMethod = "GET"
                Response = @{Keys = "repositoryNodeInfo"}
            }
            ConfigurationsRequestedVersion = @{
                Path = "$($global:tsmApiConfig.ApiUri)/configurations/requested/version"
                HttpMethod = "GET"
                Response = @{Keys = "version"}
            }
            ConfigurationKeys = @{
                Path = "$($global:tsmApiConfig.ApiUri)/configurations/<0>/keys"
                HttpMethod = "GET"
                Response = @{Keys = "configKeys"}
            }
            ConfigurationKey = @{
                Path = "$($global:tsmApiConfig.ApiUri)/configurations/<0>/keys/<1>"
                HttpMethod = "GET"
                Response = @{Keys = "configKeys.<1>"}
            }
            ExportConfigurationAndTopologySettings = @{
                Path = "$($global:tsmApiConfig.ApiUri)/export?includeBinaryVersion=true"
                HttpMethod = "GET"
                Response = @{Keys = ""}
            }
            ClusterStatus = @{
                Path = "$($global:tsmApiConfig.ApiUri)/status"
                HttpMethod = "GET"
                Response = @{Keys = "clusterStatus"}
            }
            ProductKeys = @{
                Path = "$($global:tsmApiConfig.ApiUri)/licensing/productKeys"
                HttpMethod = "GET"
                Response = @{Keys = "productKeys.items"}
            }
            ReindexSearch = @{
                Path = "$($global:tsmApiConfig.ApiUri)/reindex-search"
                HttpMethod = "POST"
                Response = @{Keys = "asyncJob"}
            }
            AsyncJob = @{
                Path = "$($global:tsmApiConfig.ApiUri)/asyncJobs/<0>"
                HttpMethod = "GET"
                Response = @{Keys = "asyncJob"}
            }                          
            AsyncJobs = @{
                Path = "$($global:tsmApiConfig.ApiUri)/asyncJobs"
                HttpMethod = "GET"
                Response = @{Keys = "asyncJobs"}
            }   
            CancelAsyncJob = @{
                Path = "$($global:tsmApiConfig.ApiUri)/asyncJobs/<0>/cancel"
                HttpMethod = "PUT"
                Response = @{Keys = "asyncJob"}
            } 
            Backup = @{
                Path = "$($global:tsmApiConfig.ApiUri)/backupFixedFile?writePath=<0>"
                HttpMethod = "POST"
                Response = @{Keys = "asyncJob"}
            }
            Cleanup = @{
                Path = "$($global:tsmApiConfig.ApiUri)/cleanup?logFilesRetentionSeconds=<0>&deleteLogFiles=<1>&deleteTempFiles=<2>&clearRedisCache=<3>&deleteHttpRequests=<4>&clearSheetImageCache=<5>"
                HttpMethod = "POST"
                Response = @{Keys = "asyncJob"}
            }
            Restore = @{
                Path = "$($global:tsmApiConfig.ApiUri)/restoreFixedFile?fixedFile=<0>"
                HttpMethod = "POST"
                Response = @{Keys = "asyncJob"}
            }
            Start = @{
                Path = "$($global:tsmApiConfig.ApiUri)/enable"
                HttpMethod = "POST"
                Response = @{Keys = "asyncJob"}
            }
            Stop = @{
                Path = "$($global:tsmApiConfig.ApiUri)/disable"
                HttpMethod = "POST"
                Response = @{Keys = "asyncJob"}
            }
        }

        return

    }
    Set-Alias -Name tsmApiInit -Value Initialize-TsmApiConfiguration -Scope Global

    function global:New-TsmApiSession {

        [CmdletBinding()]
        param ()

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $creds = Get-Credentials $global:tsmApiConfig.Credentials
        $headers = $global:tsmApiConfig.Method.Login.Headers
        $body = $global:tsmApiConfig.Method.Login.Body.replace("<0>",$creds.UserName).replace("<1>",$creds.GetNetworkCredential().Password)
        $path = $global:tsmApiConfig.Method.Login.Path 
        $httpMethod = $global:tsmApiConfig.Method.Login.HttpMethod

        # must assign the response from this Invoke-Method to a variable or $session does not get set
        $response = Invoke-RestMethod $path -Method $httpMethod -Headers $headers -Body $body -SkipCertificateCheck -SessionVariable session -Verbose:$false
        $response | Out-Null
        return $session

    }
    Set-Alias -Name tsmApiLogin -Value New-TsmApiSession -Scope Global

    function global:Remove-TsmApiSession {

        [CmdletBinding()]
        param()

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        return Invoke-TsmApiMethod -Method "Logout"

    }
    Set-Alias -Name tsmApiLogout -Value Remove-TsmApiSession -Scope Global

    function global:Invoke-TsmApiMethod {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Method,
            [Parameter(Mandatory=$false,Position=1)][string[]]$Params
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $path = $global:tsmApiConfig.Method.$Method.Path 
        $httpMethod = $global:tsmApiConfig.Method.$Method.HttpMethod
        $keys = $global:tsmApiConfig.Method.$Method.Response.Keys

        for ($i = 0; $i -lt $params.Count; $i++) {
            $path = $path -replace "<$($i)>",$Params[$i]
            $keys = $keys -replace "<$($i)>",$Params[$i]
        }   
        
        try {
            $response = Invoke-RestMethod $path -Method $httpMethod -SkipCertificateCheck -WebSession $global:tsmApiConfig.Session -Verbose:$false
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
                $global:tsmApiConfig.Session = New-TsmApiSession
                $response = Invoke-RestMethod $path -Method $httpMethod -SkipCertificateCheck -WebSession $global:tsmApiConfig.Session  -Verbose:$false
            }
            # else {
            #     Write-Error -Message $_.Exception.Message
            #     Write-Log -Context $Method -Message $_.Exception.Message -EntryType "Error" -Action Invoke-RestMethod -Target $path -Status "Failure"
            # }
        }

        if ($keys) {
            foreach ($key in $keys.split(".")) {
                $response = $response.$key
            }
        }
        return $response

    }
    Set-Alias -Name tsmApi -Value Invoke-TsmApiMethod -Scope Global

    function global:Get-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Status,
            [Parameter(Mandatory=$false)][string]$Type,
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$Latest
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        if ($Id) {
            $asyncJob = Invoke-TsmApiMethod -Method "AsyncJob" -Params @($Id)
        }
        else {
            $asyncJob = Invoke-TsmApiMethod -Method "AsyncJobs"
            if ($Status) {
                $asyncJob = $asyncJob | Where-Object {$_.status -eq $Status}
            }
            if ($Type) {
                $asyncJob = $asyncJob | Where-Object {$_.jobType -eq $Type}
            }
            if ($Latest) {
                $asyncJob = $asyncJob | Sort-Object -Property updatedAt | Select-Object -Last 1
            }
        }

        return $asyncJob # ? ($asyncJob | Select-Object -Property $($View ? $AsyncJobView.$($View) : $AsyncJobView.Default)) : $null
    }

    function global:Show-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Status,
            [Parameter(Mandatory=$false)][string]$Type,
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$Latest
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
        
        $asyncJobs = Get-AsyncJob -Id $Id -Status $Status -Type $Type

        return  $asyncJobs | Select-Object -Property $($View ? $AsyncJobView.$($View) : $AsyncJobView.Default)
    }

    function global:Watch-AsyncJob {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Callback,
            [switch]$Add,
            [switch]$Update,
            [switch]$Remove
        )
        $Command = "Add"
        if ($Update) {$Command = "Update"}
        if ($Remove) {$Command = "Remove"}

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            function Remove-AsyncJob {
                [CmdletBinding()]
                param (
                    [Parameter(ValueFromPipeline)][Object]$InputObject,
                    [Parameter(Mandatory=$true,Position=0)][object]$AsyncJob,
                    [Parameter(Mandatory=$false,Position=1)][string]$Callback
                )
                begin {$outputObject = @()}
                process {$outputObject += $InputObject}
                end {return $outputObject | Where-Object {$_.id -ne $AsyncJob.id}}
            }

            function Add-AsyncJob {
                [CmdletBinding()]
                param (
                    [Parameter(ValueFromPipeline)][Object]$InputObject,
                    [Parameter(Mandatory=$true,Position=0)][object]$AsyncJob,
                    [Parameter(Mandatory=$false)][string]$Context,
                    [Parameter(Mandatory=$false)][string]$Callback
                )
                begin {$outputObject = @()}
                process {
                    if ($InputObject) {
                        $outputObject += $InputObject
                    }
                }
                end {
                    if ($AsyncJob.id -notin $InputObject.id) {       
                        $outputObject += [PSCustomObject]@{
                            id = $AsyncJob.id
                            status = $AsyncJob.status
                            progress = $AsyncJob.progress
                            updatedAt = $AsyncJob.updatedAt
                            context = $Context
                            callback = $Callback
                        }
                    }
                    return $outputObject
                }
            }

        $asyncJob = Get-AsyncJob -Id $Id
        if (!$asyncJob) {return}

        $platformEvent = switch ($asyncJob.jobType) {
            "DeploymentsJob" {$PlatformEvent.Restart}
            "StartServerJob" {$PlatformEvent.Start}
            "StopServerJob" {$PlatformEvent.Stop}
            default {$null}
        }

        $platformEventStatusTarget = switch ($asyncJob.jobType) {
            "DeploymentsJob" {$PlatformEventStatusTarget.Start}
            "StartServerJob" {$PlatformEventStatusTarget.Start}
            "StopServerJob" {$PlatformEventStatusTarget.Stop}
            default {$null}
        }

        $watchlist = Read-Watchlist asyncJobWatchlist

        $prevAsyncJob = $watchlist | Where-Object {$_.id -eq $Id}

        switch ($Command) {
            "Add" {
                $watchlist = $watchlist | Add-AsyncJob -AsyncJob $asyncJob -Context $Context -Callback $Callback 

                # send alerts for new entries
                if (!$prevAsyncJob) {
                    Send-AsyncJobMessage $asyncJob.id -Context $Context
                } 

                # set platform event 
                if ($platformEvent) {
                    Set-PlatformEvent -Event $platformEvent -EventStatus $PlatformEventStatus.InProgress -EventStatusTarget $platformEventStatusTarget
                }
            }
            "Update" {
                # remove previous entry and add updated entry
                $watchlist = $watchlist | Remove-AsyncJob -AsyncJob $asyncJob 
                if (!$asyncJob.completedAt) {
                    $watchlist = $watchlist | Add-AsyncJob -AsyncJob $asyncJob -Context $prevAsyncJob.context -Callback $prevAsyncJob.callback
                }

                # send alerts for updates
                if ($asyncJob.updatedAt -gt $prevAsyncJob.updatedAt) {
                    if ($asyncJob.status -ne $prevAsyncJob.status -or $asyncJob.progress -gt $prevAsyncJob.progress) {
                        Send-AsyncJobMessage $asyncJob.id -Context ($Context ? $Context : $prevAsyncJob.context)
                    }
                }
                if ($asyncJob.completedAt) {
                    if ($prevAsyncJob.callback) {
                        Invoke-Expression "$($prevAsyncJob.Callback) -Id $($asyncJob.id)"
                    }

                    # set platform event (completed or failed)
                    if ($platformEvent) {
                        Set-PlatformEvent -Event $platformEvent -EventStatus ($asyncJob.status -ne "Succeeded" ? $PlatformEventStatus.Failed : $PlatformEventStatus.Completed) -EventStatusTarget $platformEventStatusTarget
                    }
                }                
            }
            "Remove" {
                $watchlist = $watchlist | Remove-AsyncJob $asyncJOb
            }
        }

        $watchlist | Write-Watchlist asyncJobWatchlist
        
        return

    }

    Set-Alias -Name Write-Watchlist -Value Write-Cache -Scope Global
    Set-Alias -Name Clear-Watchlist -Value Clear-Cache -Scope Global
    Set-Alias -Name Read-Watchlist -Value Read-Cache -Scope Global
    
    function global:Show-Watchlist {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Watchlist,
            [Parameter(Mandatory=$false)][string]$View="Watchlist"
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        return (Read-Watchlist $Watchlist) | Select-Object -Property $($View ? $AsyncJobView.$($View) : $AsyncJobView.Default)

    }

    function global:Update-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false,Position=0)][string]$Id
        )

        $watchlist = Read-Watchlist asyncJobWatchlist
        if ($Id) { 
            $watchlist = $watchlist | Where-Object {$_.id -eq $Id}
            if (!$watchlist) {return}
        }
        foreach ($asyncJob in $watchlist) {
            
            Write-Host+ -NoNewLine -ForegroundColor Gray "Updating asyncJob $($asyncJob.id) ... "

            Watch-AsyncJob $asyncJob.id -Update

            Write-Host+ -NoTimestamp -NoTrace -ForegroundColor DarkGreen "DONE"

        }

        # check TSM for running asyncJobs started by others
        # this step returns all running jobs: dupes removed by Watch-AsyncJob
        $asyncJobs = Get-AsyncJob -Status "Running" | Where-Object {$_.id -notin $watchlist.id}
        foreach ($asyncJob in $asyncJobs) {

            Write-Host+ -NoNewLine -ForegroundColor Gray "Updating asyncJob $($asyncJob.id) ... "

            Watch-AsyncJob $asyncJob.Id -Add -Context "External Service/Person"
            
            Write-Host+ -NoTimestamp -NoTrace -ForegroundColor DarkGreen "DONE"
        }

        return

    }

    function global:Wait-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][int]$IntervalSeconds = 15,
            [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 300,
            [Parameter(Mandatory=$false)][int]$ProgressSeconds
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $asyncJob = Invoke-TsmApiMethod -Method "AsyncJob" -Params @($Id)

        $timeout = $false
        $timeoutTimer = [Diagnostics.Stopwatch]::StartNew()

        do {
            Start-Sleep -seconds $IntervalSeconds
            $asyncJob = Invoke-TsmApiMethod -Method "AsyncJob" -Params @($Id)
        } 
        until ($asyncJob.completedAt -or 
                [math]::Round($timeoutTimer.Elapsed.TotalSeconds,0) -gt $TimeoutSeconds)

        if ([math]::Round($timeoutTimer.Elapsed.TotalSeconds,0) -gt $TimeoutSeconds) {
            $timeout = $true
        }

        $timeoutTimer.Stop()

        return $asyncJob, $timeout

    }

#endregion TSMAPI
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
            $platformTopology.Alias.($node.replace("tbl-","").replace("-0","")) = $node

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

        $productColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $productColumnHeader.Length) + (Write-Dots -Character " " -Length $productColumnLength -Adjust (-($productColumnHeader.Length)))
        $serialColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $serialColumnHeader.Length) + (Write-Dots -Character " " -Length $serialColumnLength -Adjust (-($serialColumnHeader.Length)))
        $numCoresColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $numCoresColumnHeader.Length) + (Write-Dots -Character " " -Length $numCoresColumnLength -Adjust (-($numCoresColumnHeader.Length)))
        $userCountColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $userCountColumnHeader.Length) + (Write-Dots -Character " " -Length $userCountColumnLength -Adjust (-($userCountColumnHeader.Length)))
        $expirationColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $expirationColumnHeader.Length) + (Write-Dots -Character " " -Length $expirationColumnLength -Adjust (-($expirationColumnHeader.Length)))
        $maintenanceColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $maintenanceColumnHeader.Length) + (Write-Dots -Character " " -Length $maintenanceColumnLength -Adjust (-($maintenanceColumnHeader.Length)))
        $validColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $validColumnHeader.Length) + (Write-Dots -Character " " -Length $validColumnLength -Adjust (-($validColumnHeader.Length)))
        $isActiveColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $isActiveColumnHeader.Length) + (Write-Dots -Character " " -Length $isActiveColumnLength -Adjust (-($isActiveColumnHeader.Length)))
        # $expiredColumnHeaderUnderscore = (Write-Dots -Character "-" -Length $expiredColumnHeader.Length) + (Write-Dots -Character " " -Length $expiredColumnLength -Adjust (-($expiredColumnHeader.Length)))

        $productColumnHeader += (Write-Dots -Character " " -Length $productColumnLength -Adjust (-($productColumnHeader.Length)))
        $serialColumnHeader += (Write-Dots -Character " " -Length $serialColumnLength -Adjust (-($serialColumnHeader.Length)))
        $numCoresColumnHeader += (Write-Dots -Character " " -Length $numCoresColumnLength -Adjust (-($numCoresColumnHeader.Length)))
        $userCountColumnHeader += (Write-Dots -Character " " -Length $userCountColumnLength -Adjust (-($userCountColumnHeader.Length)))
        $expirationColumnHeader += (Write-Dots -Character " " -Length $expirationColumnLength -Adjust (-($expirationColumnHeader.Length)))
        $maintenanceColumnHeader += (Write-Dots -Character " " -Length $maintenanceColumnLength -Adjust (-($maintenanceColumnHeader.Length)))
        $validColumnHeader += (Write-Dots -Character " " -Length $validColumnLength -Adjust (-($validColumnHeader.Length)))
        $isActiveColumnHeader += (Write-Dots -Character " " -Length $isActiveColumnLength -Adjust (-($isActiveColumnHeader.Length)))
        # $expiredColumnHeader += (Write-Dots -Character " " -Length $expiredColumnLength -Adjust (-($expiredColumnHeader.Length)))

        $indent = Write-Dots -Character " " -Length 6

        Write-Host+ -NoTrace -NoTimestamp $indent,$productColumnHeader,$serialColumnHeader,$numCoresColumnHeader,$userCountColumnHeader,$expirationColumnHeader,$maintenanceColumnHeader,$validColumnHeader,$isActiveColumnHeader #,$expiredColumnHeader
        Write-Host+ -NoTrace -NoTimestamp $indent,$productColumnHeaderUnderscore,$serialColumnHeaderUnderscore,$numCoresColumnHeaderUnderscore,$userCountColumnHeaderUnderscore,$expirationColumnHeaderUnderscore,$maintenanceColumnHeaderUnderscore,$validColumnHeaderUnderscore,$isActiveColumnHeaderUnderscore #,$expiredColumnHeaderUnderscore         

        foreach ($license in $PlatformLicenses) {
            
            $licenseExpiryDays = $license.expiration - $now
            $maintenanceExpiryDays = $license.maintenance - $now
            $expirationColumnColor = $licenseExpiryDays -le $30days ? 2 : ($licenseExpiryDays -le $90days ? 1 : 0)
            $maintenanceColumnColor = $maintenanceExpiryDays -le $30days ? 2 : ($maintenanceExpiryDays -le $90days ? 1 : 0)
            $productColumnColor = ($expirationColumnColor, $maintenanceColumnColor | Measure-Object -Maximum).Maximum
            
            $productColumnValue = $license.product + (Write-Dots -Character " " -Length $productColumnLength -Adjust (-($license.product.Length)))
            $serialColumnValue = $license.serial + (Write-Dots -Character " " -Length $serialColumnLength -Adjust (-($license.serial.Length)))
            $numCoresColumnValue = (Write-Dots -Character " " -Length $numCoresColumnLength -Adjust (-($license.numCores.ToString().Length))) + $license.numCores.ToString()
            $userCountColumnValue = (Write-Dots -Character " " -Length $userCountColumnLength -Adjust (-($license.userCount.ToString().Length))) + $license.userCount.ToString()
            $expirationColumnValue = $license.expiration.ToString('u').Substring(0,10) + (Write-Dots -Character " " -Length $expirationColumnLength -Adjust (-($license.expiration.ToString('u').Substring(0,10).Length)))
            $maintenanceColumnValue = $license.maintenance.ToString('u').Substring(0,10) + (Write-Dots -Character " " -Length $maintenanceColumnLength -Adjust (-($license.maintenance.ToString('u').Substring(0,10).Length)))
            $validColumnValue = (Write-Dots -Character " " -Length $validColumnLength -Adjust (-($license.valid.ToString().Length))) + $license.valid.ToString()
            $isActiveColumnValue = (Write-Dots -Character " " -Length $isActiveColumnLength -Adjust (-($license.isActive.ToString().Length))) + $license.isActive.ToString()
            # $expiredColumnValue = $license.expired.ToString() + (Write-Dots -Character " " -Length $expiredColumnLength -Adjust (-($license.expired.ToString().Length)))

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

        $indent = Write-Dots -Character " " -Length 6

        $dots = Write-Dots -Length 47 -Adjust (-(("  EULA Compliance").Length))
        Write-Host+ -NoTrace "  EULA Compliance",$dots,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

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

        $dots = Write-Dots -Length 47 -Adjust (-(("  EULA Compliance").Length))
        Write-Host+ -NoTrace -NoNewLine "  EULA Compliance",$dots -ForegroundColor Gray,DarkGray
        
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

        $dots = Write-Dots -Length 47 -Adjust (-(("  TSM Controller").Length))
        Write-Host+ -NoTrace "  TSM Controller",$dots,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

        $fail = $false
        try {

            $dots = Write-Dots -Length 39 -Adjust (-(("    Connect to $($tsmApiConfig.Controller)").Length))
            Write-Host+ -NoTrace -NoNewLine "    Connect to",$tsmApiConfig.Controller,$dots -ForegroundColor Gray,DarkBlue,DarkGray
        
            Initialize-TsmApiConfiguration

            Write-Host+ -NoTrace -NoTimestamp " PASS" -ForegroundColor DarkGreen
        
        }
        catch {

            $fail = $true
            Write-Host+ -NoTrace -NoTimestamp " UNKNOWN" -ForegroundColor DarkRed
        }

        $dots = Write-Dots -Length 47 -Adjust (-(("  TSM Controller").Length))
        Write-Host+ -NoTrace -NoNewLine "  TSM Controller",$dots -ForegroundColor Gray,DarkGray

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
            [Parameter(Mandatory=$false)][string[]]$ComputerName
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $dots = Write-Dots -Length 47 -Adjust (-(("  Postgres Access").Length))
        Write-Host+ -NoNewline -NoTrace "  Postgres Access",$dots -ForegroundColor Gray,DarkGray

        try {

            $templatePath = "$($global:Platform.InstallPath)\packages\templates.$($Platform.Build)\pg_hba.conf.ftl"
            $templateContent = [System.Collections.ArrayList](Get-Content -Path $templatePath)

            if ($templateContent) {
        
                Write-Host+ -NoTimestamp -NoTrace  " PENDING" -ForegroundColor DarkGray

                $subDots = Write-Dots -Length 35 -Adjust (-(("Updating pg_hba.conf.ftl").Length))
                Write-Host+ -NoTrace -NoNewLine "    Updating pg_hba.conf.ftl",$subDots -ForegroundColor Gray,DarkGray

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

                Write-Host+ -NoNewline -NoTrace "  Postgres Access",$dots -ForegroundColor Gray,DarkGray
                Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen

            }
            else {
                
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
                Write-Log -Context "Preflight" -Action "Test" -Target "pg_hba.conf.ftl" -Status "FAIL" -EntryType "Error" -Message "Invalid format"
                # throw "Invalid format"

                Write-Host+ -NoNewline -NoTrace "  Postgres Access",$dots -ForegroundColor Gray,DarkGray
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
