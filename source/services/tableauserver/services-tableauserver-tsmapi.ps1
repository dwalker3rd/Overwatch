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
        ApiVersion = "$($global:Catalog.Platform.$($global:Platform.Id).Api.TsmApi.Version)"
        Credentials = "localadmin-$($global:Platform.Instance)"
        Async = @{
            Status = @{
                Succeeded = "Succeeded"
                Created = "Created"
                Running = "Running"
                Failed = "Failed"
                Cancelled = "Cancelled"
                Queued = "Queued"
            } 
            DontWatchExternalJobType = @("RebuildSearchIndex")
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
        CurrentConfigurationVersion = @{
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
            Response = @{Keys = "configKeys"}
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
        RebuildSearchIndex = @{
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
    param (
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 15
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $creds = Get-Credentials $global:tsmApiConfig.Credentials
    $headers = $global:tsmApiConfig.Method.Login.Headers
    $body = $global:tsmApiConfig.Method.Login.Body.replace("<0>",$creds.UserName).replace("<1>",$creds.GetNetworkCredential().Password)
    $path = $global:tsmApiConfig.Method.Login.Path 
    $httpMethod = $global:tsmApiConfig.Method.Login.HttpMethod

    # must assign the response from this Invoke-Method to a variable or $session does not get set
    $response = Invoke-RestMethod $path -Method $httpMethod -Headers $headers -Body $body -TimeoutSec $TimeoutSec -SkipCertificateCheck -SessionVariable session -Verbose:$false
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
        [Parameter(Mandatory=$false,Position=1)][string[]]$Params,
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 15
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
        $response = Invoke-RestMethod $path -Method $httpMethod -TimeoutSec $TimeoutSec -SkipCertificateCheck -WebSession $global:tsmApiConfig.Session -Verbose:$false
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
            $global:tsmApiConfig.Session = New-TsmApiSession
            $response = Invoke-RestMethod $path -Method $httpMethod -TimeoutSec $TimeoutSec -SkipCertificateCheck -WebSession $global:tsmApiConfig.Session -Verbose:$false
        }
        else {
            throw $_.Exception.Message
        }
    }

    if ($keys) {
        foreach ($key in $keys.split(".")) {
            $response = $response.$key
        }
    }
    return $response

}
Set-Alias -Name tsmApi -Value Invoke-TsmApiMethod -Scope Global


function global:Get-TableauServerStatus {

    [CmdletBinding()] 
    param (
        [switch]$ResetCache
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tableauServerStatus = $null

    $action = "Read-Cache"
    $target = "clusterstatus"
    $attemptMessage = ""

    if ((get-cache clusterstatus).Exists() -and !$ResetCache) {
        
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

            $asyncJob = Get-AsyncJob | Where-Object {$_.status -eq "Running" -and $_.jobType -in ("StartServerJob","StopServerJob","RestartServerJob")}

            # Check for running async jobs
            # modify Tableau Server status if these jobs are running
            $tableauServerStatus.RollupStatus = 
                switch ($asyncJob.jobType) {
                    "StartServerJob" {"Starting"}
                    "StopServerJob" {"Stopping"}
                    "RestartServerJob" {"Restarting"}
                    default {$tableauServerStatus.RollupStatus}
                }

            Write-Debug "$($action) $($target) ($($attemptMessage.replace("<0>", $attempt))): Success"

        }
        catch {

            if ($attempt -eq $maxAttempts) {
                # Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor Red
                # Write-Host+ -NoTrace "$($action) $($target) ($($attemptMessage.replace("<0>", $attempt))): Failure" -ForegroundColor Red
                Write-Log -Context "TableauServerStatus" -Action $action -Target $target -EntryType "Error" -Message $_.Exception.Message -Status "Failure"
                Write-Log -Context "TableauServerStatus" -Action $action -Target $target -EntryType "Error" -Message $attemptMessage.replace("<0>", $attempt) -Status "Failure"
            }
            else {
                # give the TSM API a moment to think it over
                Write-Debug "Waiting $($sleepSeconds) before retrying ... "
                Start-Sleep -Seconds $sleepSeconds
            }

        }

        $attempt++
        
    } until ($tableauServerStatus -or $attempt -gt $maxAttempts)

    if ($tableauServerStatus) {
        
        # if Tableau Server's rollupStatus is DEGRADED
        if ($tableauServerStatus.rollupStatus -eq "Degraded") {

            # modify the rollupStatus of services with the following serviceNames and instance.messages
            # TODO: convert this to rules-based logic (using a CSV file)
            foreach ($nodeId in $tableauServerStatus.nodes.nodeId) { 
                $node = Get-PlatformTopologyAlias $nodeId
                foreach ($service in ($tableauServerStatus.nodes | Where-Object {$_.nodeid -eq $nodeId}).services) { 
                    foreach ($instance in $service.instances) {
                        switch ($service.serviceName) {
                            "backgrounder" {
                                if ($instance.message -like "Error opening named pipe*") {
                                    # this isn't an error, but a scheduled restart (occurs every 8 hours)
                                    $instance.message = "Scheduled restart"
                                    $service.rollupStatus = "Running"
                                }
                            }
                            "clientfileservice" {
                                if ($instance.processStatus -eq "StatusUnavailable") {

                                    # get the detailed message from the clientfileservice log file
                                    $installPath = $global:Platform.InstallPath -replace ":","$"
                                    $path = "\\$node\$installPath\data\tabsvc\logs\clientfileservice\clientfileservice_$nodeId-0.log"
                                    $pattern = "java.lang.RuntimeException: "
                                    $match = select-string -path $path -pattern $pattern
                                    $message = ($match[-1] -split $pattern)[-1]
                                    $instance | Add-Member -NotePropertyName "message" -NotePropertyValue $message

                                    # restart the clientfileservice, but don't clear $instance.processStatus
                                    # if restarting the clientfileservice resolves the error, Overwatch's flap detection 
                                    # will not report the error.  otherwise, the alert needs to be sent
                                    $cimSession = New-CimSession -ComputerName $node
                                    $clientFileService = Get-CimInstance -ClassName "Win32_Service" -CimSession $cimSession -Property * | Where-Object {$_.Name -eq "clientfileservice_0"}
                                    $clientFileService | Invoke-CimMethod -Name "StopService" 
                                    $clientFileService | Invoke-CimMethod -Name "StartService"
                                    Remove-CimSession $cimSession
                                }
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

function global:Get-TsmConfigurationKey {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )

    $currentConfigurationVersion = Invoke-TsmApiMethod -Method CurrentConfigurationVersion
    $configurationKey =  Invoke-TsmApiMethod -Method ConfigurationKey -params @($currentConfigurationVersion,$Name)

    return $configurationKey.$Name

}