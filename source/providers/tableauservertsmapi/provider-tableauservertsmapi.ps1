class TsmApiResponse {

    [string]$Keys

    TSRestApiResponse() { $this.Init() }

    [void]Init() {}

}

class TsmApiMethodPrerequisite {

    [string[]]$Platform
    [object]$ApiVersion

    TsmApiMethodPrerequisite() { $this.Init() }

    [void]Init() {}

    [void]Validate() {

        if ($this.ApiVersion) {
            if (![string]::IsNullOrEmpty($this.ApiVersion.Minimum) -or ![string]::IsNullOrEmpty($this.ApiVersion.Maximum)) {
                $_apiVersion = $global:tsmApiConfig.ApiVersion
                if ((![string]::IsNullOrEmpty($this.ApiVersion.Minimum) -and $_apiVersion -lt $this.ApiVersion.Minimum) -or
                    (![string]::IsNullOrEmpty($this.ApiVersion.Maximum) -and $_apiVersion -gt $this.ApiVersion.Maximum))
                {
                    throw "Method `"($this.Name)`" is not supported for Tableau Server TSM API $($this.ApiVersion.Minimum)."
                }
            }
        }

        if (![string]::IsNullOrEmpty($this.Platform)) {
            if ($this.Platform -notcontains $global:tsmApiConfig.Platform.Id) {
                throw "Method `"($this.Name)`" is not supported for the $($global:tsmApiConfig.Platform.Name) platform."
            }
        }
    }

}

class TsmApiMethod {

    [string]$Name
    [string]$Endpoint
    # [uri]$Uri
    [ValidateSet("GET","PUT","POST","DELETE")][string]$HttpMethod 
    [object]$Headers
    [string]$Body 
    [TsmApiResponse]$Response
    [TsmApiMethodPrerequisite]$Prerequisite

    TsmApiMethod() { $this.Init() }

    [void]Init() {}

    [uri]Uri() { return "$($global:tsmApiConfig.ApiUri)/$($this.Endpoint)" }

}

function global:Initialize-TsmApiConfiguration {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $env:COMPUTERNAME, # TODO: Validate $Server
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($global:Platform.Instance)",
        [switch]$ResetCache
    )

    $prerequisiteTestResults = Test-Prerequisites -Type "Provider" -Id "TableauServerTsmApi" -ComputerName $Server -Quiet
    if (!$prerequisiteTestResults.Pass) {
        throw $prerequisiteTestResults.Prerequisites[0].Tests.Reason
    }

    $global:tsmApiConfig = @{
        Server = $Server
        Port = "8850"
        ApiVersion = "$($global:Catalog.Provider.TableauServerTsmApi.Initialization.Api.Version.Minimum)"
        Credentials = Get-Credentials $Credentials -ComputerName $Server
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
            Initialized = $false
        }
    }
    $global:tsmApiConfig.ApiUri = "https://$($global:tsmApiConfig.Server):$($global:tsmApiConfig.Port)/api/$($global:tsmApiConfig.ApiVersion)"
    $global:tsmApiConfig.Method = @{
        Bootstrap = [TsmApiMethod]@{
            Endpoint = "bootstrap"
            HttpMethod = "GET"
            Response = @{Keys = "initialBootstrapSettings"}
        }
        Login = [TsmApiMethod]@{
            Endpoint = "login"
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
        Bootstrap = [TsmApiMethod]@{
            Endpoint = "bootstrap"
            HttpMethod = "GET"
            Response = @{Keys = "initialBootstrapSettings"}
        }
        Login = [TsmApiMethod]@{
            Endpoint = "login"
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
        Logout = [TsmApiMethod]@{
            Endpoint = "logout"
            HttpMethod = "POST"
        }
        TopologiesRequestedVersion = [TsmApiMethod]@{
            Endpoint = "topologies/requested/version"
            HttpMethod = "GET"
            Response = @{Keys = "version"}
        }
        Topology = @{
            Path = "/topologies/<0>"
            HttpMethod = "GET"
            Response = @{Keys = "topologyVersion.nodes"}
        }
        Nodes = [TsmApiMethod]@{
            Endpoint = "nodes"
            HttpMethod = "GET"
            Response = @{Keys = "clusterNodes.nodes"}
        }
        NodeInfo = [TsmApiMethod]@{
            Endpoint = "nodes/<0>"
            HttpMethod = "GET"
            Response = @{Keys = "nodeInfo"}
        }            
        NodeHost = [TsmApiMethod]@{
            Endpoint = "nodes/<0>"
            HttpMethod = "GET"
            Response = @{Keys = "nodeInfo.address"}
        }
        NodeCores = [TsmApiMethod]@{
            Endpoint = "nodes/<0>"
            HttpMethod = "GET"
            Response = @{Keys = "nodeInfo.processorCount"}
        }
        RepositoryNodeInfo = [TsmApiMethod]@{
            Endpoint = "repository/currentMaster"
            HttpMethod = "GET"
            Response = @{Keys = "repositoryNodeInfo"}
        }
        CurrentConfigurationVersion = [TsmApiMethod]@{
            Endpoint = "configurations/requested/version"
            HttpMethod = "GET"
            Response = @{Keys = "version"}
        }
        ConfigurationKeys = [TsmApiMethod]@{
            Endpoint = "configurations/<0>/keys"
            HttpMethod = "GET"
            Response = @{Keys = "configKeys"}
        }
        ConfigurationKey = [TsmApiMethod]@{
            Endpoint = "configurations/<0>/keys/<1>"
            HttpMethod = "GET"
            Response = @{Keys = "configKeys"}
        }
        ExportConfigurationAndTopologySettings = [TsmApiMethod]@{
            Endpoint = "export?includeBinaryVersion=true"
            HttpMethod = "GET"
            Response = @{Keys = ""}
        }
        ClusterStatus = [TsmApiMethod]@{
            Endpoint = "status"
            HttpMethod = "GET"
            Response = @{Keys = "clusterStatus"}
        }
        ProductKeys = [TsmApiMethod]@{
            Endpoint = "licensing/productKeys"
            HttpMethod = "GET"
            Response = @{Keys = "productKeys.items"}
        }
        RebuildSearchIndex = [TsmApiMethod]@{
            Endpoint = "reindex-search"
            HttpMethod = "POST"
            Response = @{Keys = "asyncJob"}
        }
        AsyncJob = [TsmApiMethod]@{
            Endpoint = "asyncJobs/<0>"
            HttpMethod = "GET"
            Response = @{Keys = "asyncJob"}
        }                          
        AsyncJobs = [TsmApiMethod]@{
            Endpoint = "asyncJobs"
            HttpMethod = "GET"
            Response = @{Keys = "asyncJobs"}
        }   
        CancelAsyncJob = [TsmApiMethod]@{
            Endpoint = "asyncJobs/<0>/cancel"
            HttpMethod = "PUT"
            Response = @{Keys = "asyncJob"}
        } 
        Backup = [TsmApiMethod]@{
            Endpoint = "backupFixedFile?writePath=<0>&skipVerification=true"
            HttpMethod = "POST"
            Response = @{Keys = "asyncJob"}
        }
        Cleanup = [TsmApiMethod]@{
            Endpoint = "cleanup?logFilesRetentionSeconds=<0>&deleteLogFiles=<1>&deleteTempFiles=<2>&clearRedisCache=<3>&deleteHttpRequests=<4>&clearSheetImageCache=<5>"
            HttpMethod = "POST"
            Response = @{Keys = "asyncJob"}
        }
        Restore = [TsmApiMethod]@{
            Endpoint = "restoreFixedFile?fixedFile=<0>"
            HttpMethod = "POST"
            Response = @{Keys = "asyncJob"}
        }
        Start = [TsmApiMethod]@{
            Endpoint = "enable"
            HttpMethod = "POST"
            Response = @{Keys = "asyncJob"}
        }
        Stop = [TsmApiMethod]@{
            Endpoint = "disable"
            HttpMethod = "POST"
            Response = @{Keys = "asyncJob"}
        }
    }

    $global:tsmApiConfig.Initialized = $true

    return

}
Set-Alias -Name tsmApiInit -Value Initialize-TsmApiConfiguration -Scope Global

function global:New-TsmApiSession {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][int]$TimeoutSec = 15
    )

    $creds = $global:tsmApiConfig.Credentials
    $headers = $global:tsmApiConfig.Method.Login.Headers
    $body = $global:tsmApiConfig.Method.Login.Body.replace("<0>",$creds.UserName).replace("<1>",$creds.GetNetworkCredential().Password)
    $uri = $global:tsmApiConfig.Method.Login.Uri() 
    $httpMethod = $global:tsmApiConfig.Method.Login.HttpMethod

    # must assign the response from this Invoke-Method to a variable or $session does not get set
    $response = Invoke-RestMethod $uri -Method $httpMethod -Headers $headers -Body $body -TimeoutSec $TimeoutSec -SkipCertificateCheck -SessionVariable session -Verbose:$false
    $response | Out-Null
    return $session

}
Set-Alias -Name tsmApiLogin -Value New-TsmApiSession -Scope Global

function global:Remove-TsmApiSession {

    [CmdletBinding()]
    param()

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

    # if (!(Test-Prerequisites -Type Provider -Id TableauServerTsmApi)) { return }

    # TODO: check method's prerequisites
    try {
        if ($global:tsmApiConfig.Method.$Method.Prerequisites) {
            $global:tsmApiConfig.Method.$Method.Prerequisites.Validate()
        }
    }
    catch {
        Write-Host+ $_.Exception.Message -Foreground Red
        return
    }

    $uri = $global:tsmApiConfig.Method.$Method.Uri()
    $httpMethod = $global:tsmApiConfig.Method.$Method.HttpMethod
    $keys = $global:tsmApiConfig.Method.$Method.Response.Keys

    for ($i = 0; $i -lt $params.Count; $i++) {
        $uri = $uri -replace "<$($i)>",$Params[$i]
        $keys = $keys -replace "<$($i)>",$Params[$i]
    } 
    
    try {
        $response = Invoke-RestMethod $uri -Method $httpMethod -TimeoutSec $TimeoutSec -SkipCertificateCheck -WebSession $global:tsmApiConfig.Session -Verbose:$false
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
            $global:tsmApiConfig.Session = New-TsmApiSession
            $response = Invoke-RestMethod $uri -Method $httpMethod -TimeoutSec $TimeoutSec -SkipCertificateCheck -WebSession $global:tsmApiConfig.Session -Verbose:$false
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

    $tableauServerStatus = $null

    $action = "Read-Cache"
    $target = "clusterstatus"
    $attemptMessage = ""

    if ((Get-Cache clusterstatus).Exists -and !$ResetCache) {
        
        Write-Host+ -IfDebug "$($action) $($target): Pending" -ForegroundColor DarkYellow

        # need to cache for back-to-back calls, but ... MaxAge should be as short as possible
        $tableauServerStatus = Read-Cache clusterstatus -MaxAge $(New-TimeSpan -Seconds 5)

        if ($tableauServerStatus) {
            
            Write-Host+ -IfDebug "$($action) $($target): Success" -ForegroundColor DarkYellow

            return $tableauServerStatus

        }
        else {

            Write-Host+ -IfDebug "$($action) $($target): Cache empty or expired" -ForegroundColor DarkYellow

        }
    }
    
    $attempt = 1
    $maxAttempts = 5
    $sleepSeconds = 5

    $action = "Query"
    $target = "TSM API"
    $attemptMessage = "Attempt #<0>"

    do {
        
        try {

            $tableauServerStatus = Invoke-TsmApiMethod -Method "ClusterStatus"
            if ($tableauServerStatus.RollupStatus -eq "Error") { throw }

        }
        catch {

            if ($attempt -eq $maxAttempts) {
                Write-Log -Action $action -Target $target -EntryType "Error" -Message $attemptMessage.replace("<0>", $attempt) -Status "Failure"
                Write-Log -Action $action -Target $target -Exception $_.Exception
            }
            else {
                Start-Sleep -Seconds $sleepSeconds
            }

        }

        $attempt++
        
    } until (($tableauServerStatus -and $tableauServerStatus.RollupStatus -ne "Error") -or $attempt -gt $maxAttempts)

    $platformJob = Get-PlatformJob | Where-Object {$_.status -eq "Running" -and $_.jobType -in ("StartServerJob","StopServerJob","RestartServerJob")}

    if ($tableauServerStatus) {

        if ($platformJob) {
    
            # Check for running platform jobs
            # modify Tableau Server status if these jobs are running
            $tableauServerStatus.RollupStatus = 
                switch ($platformJob.jobType) {
                    "StartServerJob" {"Starting"}
                    "StopServerJob" {"Stopping"}
                    "RestartServerJob" {"Restarting"}
                    default {$tableauServerStatus.RollupStatus}
                }
    
        }        
        
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
                            "noninteractive" {
                                if ($instance.message -like "Unexpected HTTP error response (503)") {
                                    # added 2024-10-27
                                    # this has apparently been happening for some time.
                                    # however, either TSM didn't report it, or Overwatch's flap detection prevented it from being reported. 
                                    # but as of 2024.2.4, it's now being reported about 8-10 minutes after the start of each hour
                                    # given that it's every hour and that I cannot find a single hit about this issue,
                                    # I'm assuming this is an internal issue or, at least, one that doesn't impact us.
                                    # therefore, i'm ignoring it
                                    $instance.message = "Unknown issue with the noninteractive microcontainer"
                                    $service.rollupStatus = "Running"                                    
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
        [Parameter(Mandatory=$true,Position=0)][string]$Key
    )

    $currentConfigurationVersion = Invoke-TsmApiMethod -Method CurrentConfigurationVersion
    $configurationKey =  Invoke-TsmApiMethod -Method ConfigurationKey -params @($currentConfigurationVersion,$Key)

    return $configurationKey.$Key

}

# function global:Set-TsmConfigurationKey {

#     [CmdletBinding()]
#     param(
#         [Parameter(Mandatory=$true)][string]$Name,
#         [Parameter(Mandatory=$true)][string]$Value
#     )

# }


function global:Get-TsmPendingChanges {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][ValidateSet("config","topology")][string[]]$Type = @("config","topology")
    )

    $Type = $Type | Foreach-Object { $_.ToLower() }

    $pendingChangesText = @("There are no pending configuration changes.","There are no pending topology changes.")
    $restartRequiredText = @("These changes will require a server restart.")

    $pendingChanges = @{}
    $Type | Foreach-Object {
        $pendingChanges += @{
            "$_" = @{ 
                command = ". tsm pending-changes list --$_-only"
            }
        }
        $_changes = [array](Invoke-Expression $pendingChanges.$_.command)
        $pendingChanges.$_ += @{ hasPendingChanges = $false }
        $hasPendingChangesIndex = -1
        if ($_changes[-1] -in $restartRequiredText) {
            $pendingChanges.$_ += @{ restartRequired = $true }
            $pendingChanges += @{ restartRequired = $true }
            $hasPendingChangesIndex = -2
        }
        if ($_changes[$hasPendingChangesIndex] -notin $pendingChangesText) {
            $pendingChanges.$_.hasPendingChanges = $true
            $pendingChanges.$_ += @{ changes = $_changes }
        }
    }

    $_changes = @()
    foreach ($key in $pendingChanges.Keys) {
        if ($pendingChanges.$Key.changes) {
            $_changes += $pendingChanges.$Key.changes
        }
    }
    $pendingChanges += @{ hasPendingChanges = $false }
    if ($_changes) {
        $pendingChanges.hasPendingChanges = $true
        $pendingChanges += @{ changes = $_changes }
    }

    return $pendingChanges

}

function global:Apply-TsmPendingChanges {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param()

    $successfulDeploymentText = @("Successfully deployed nodes with updated configuration and topology version.")

    $pendingChanges = @{}
    $pendingChanges += @{ hasPendingChanges = $false }
    if ((Get-TsmPendingChanges).hasPendingChanges) {
        $pendingChanges.hasPendingChanges = $true
        $pendingChanges += @{ command = ". tsm pending-changes apply --ignore-prompt"}
        $pendingChanges += @{
            changes = [array](Invoke-Expression $pendingChanges.command)
        }
        $pendingChanges += @{
            successfulDeployment = $pendingChanges.changes[-1] -in $successfulDeploymentText
        }
    }

    return $pendingChanges

}

function global:Rebuild-SearchIndex {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param()

    if ($global:Environ.Platform -ne "TableauServer") { return }

    $platformJob = Invoke-TsmApiMethod -Method RebuildSearchIndex

    return $platformJob

}
Set-Alias -Scope Global -Name RebuildSearchIndex -Value Rebuild-SearchIndex