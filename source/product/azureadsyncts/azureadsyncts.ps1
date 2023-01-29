#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id="AzureADSyncTS"}
. $PSScriptRoot\definitions.ps1

$tenantKey = Get-AzureTenantKeys -AzureAD
$action = $null; $target = $null; $status = $null

function Assert-SyncError {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][object]$Status,
        [Parameter(Mandatory=$true)][object]$ErrorDetail
    )

    Write-Log -Action "Sync" -Target $Target -Status $ErrorDetail.code -Message $ErrorDetail.summary -EntryType "Error"
    $message = "$($emptyString.PadLeft(8,"`b")) $($ErrorDetail.summary)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkRed
    
    if ($ErrorDetail.Code -notin ("CACHE.NOTFOUND")) {
        Send-TaskMessage -Id $Product.Id -Status $Status -Message $ErrorDetail.summary -MessageType $PlatformMessageType.Alert | Out-Null
    }

    Write-Host+
    $message = "$($global:Product.Id)$($Status.ToLower()) because $($ErrorDetail.summary)"
    Write-Host+ -NoTrace $message -ForegroundColor DarkRed
    $message = "AzureADCache should correct this issue on its next run."
    Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
    Write-Host+

    return

}

#region SERVER/PLATFORM CHECK

    # Do NOT continue if ...
    #   1. the host server is starting up or shutting down
    #   2. the platform is not running or is not ok

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

    # abort if a platform event is in progress
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = $platformStatus.IsStopped ? "Platform is STOPPED" : "Platform $($platformStatus.Event.ToUpper()) $($platformStatus.EventStatus.ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

    # abort if heartbeat indicates status is not ok
    If (!$heartbeat.IsOK) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = "$($Platform.Name) status is $($platformStatus.RollupStatus.ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

#endregion SERVER/PLATFORM CHECK



$action = $null; $target = $null; $status = $null
try {

    $action = "Initialize"; $target = "AzureAD\$tenantKey"
    Initialize-AzureConfig

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace "Tenant Type",$global:Azure.$tenantKey.Tenant.Type -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+ -NoTrace "Tenant Name",$global:Azure.$tenantKey.Tenant.Name -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+

    $action = "Connect"; $target = "AzureAD\$tenantKey"
    Connect-AzureAD -Tenant $tenantKey

    $action = "Sync"; $target = "AzureAD\$tenantKey\Groups"
    $syncError = Sync-TSGroups -Tenant $tenantKey
    if ($syncError) {
        Assert-SyncError -Target $target -Status "Aborted" -ErrorDetail $syncError
        return
    }

    # Delta: default for all runs
    # Full: schedule per config
    $now = Get-Date -AsUTC
    $fullSchedule = $global:Product.Config.Schedule.Full
    $Delta = !($now.DayOfWeek -eq $fullSchedule.DayOfWeek -and $now.Hour -eq $fullSchedule.Hour -and $now.Minute -in $fullSchedule.Minute)

    $action = "Sync"; $target = "AzureAD\$tenantKey\Users"
    $syncError = Sync-TSUsers -Tenant $tenantKey -Delta:$Delta
    if ($syncError) {
        Assert-SyncError -Target $target -Status "Aborted" -ErrorDetail $syncError
        return
    }

    $status = "Success"

    $action = "Export"; $target = "AzureAD\$tenantKey\Log"
    $message = "<Exporting sync transactions <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $azureADSyncLog = read-log -context $global:Product.Id
    if ($azureADSyncLog.Count -gt 0) {
        $azureADSyncLog | Export-Log "$($global:Azure.Location.Data)\AzureADSyncLog.csv"
    }

    $azureADSyncTransactionCount = $azureADSyncLog.Count -gt 0 ? ($azureADSyncLog.Count).ToString() : "None"
    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADSyncTransactionCount)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($azureADSyncLog.Count -gt 0 ? "Green" : "Yellow") 

    if ($azureADSyncLog.Count -gt 0) {
        Write-Host+
        Copy-Files -Path "$($global:Azure.Location.Data)\AzureADSyncLog.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
        Write-Host+   
    }

}
catch {

    $status = "Error"
    Write-Log-Action $action -Target $target -Status $status -Message $_.Exception.Message -EntryType "Error" -Force
    Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

}
finally {

    Write-Host+ -MaxBlankLines 1
    Remove-PSSession+

}
