#Requires -RunAsAdministrator
#Requires -Version 7

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"

$global:Product = @{Id="AzureADSyncTS"}
. $PSScriptRoot\definitions.ps1

$tenantKey = Get-AzureADTenantKeys -AzureAD
$action = $null; $target = $null; $status = $null

function Assert-SyncError {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][object]$Status,
        [Parameter(Mandatory=$true)][object]$ErrorDetail
    )

    Write-Log -Context "AzureADSyncTS" -Action "Sync" -Target $Target -Status $ErrorDetail.code -Message $ErrorDetail.summary -EntryType "Error"
    $message = "$($emptyString.PadLeft(8,"`b")) $($ErrorDetail.summary)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkRed
    
    Send-TaskMessage -Id "AzureADSyncTS" -Status $Status -Message $message -MessageType $PlatformMessageType.Alert

    Write-Host+
    $message = "AzureADSyncTS $($status.ToLower()) because $($ErrorDetail.summary)"
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
        $message = "$($global:Product.Id) $($status.ToLower()) because server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Context $($global:Product.Id) -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($global:Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

    # abort if platform is stopped or if a platform event is in progress
    if ($platformStatus.IsStopped -or ($platformStatus.Event -and !$platformStatus.EventHasCompleted)) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because "
        if ($platformStatus.IsStopped) {
            $message += "$($Platform.Name) is STOPPED"
        }
        else {
            $message += "platform $($platformStatus.Event.ToUpper()) is $($platformStatus.EventStatus.ToUpper()) on $($Platform.Name)"
        }
        Write-Log -Context $($global:Product.Id) -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($global:Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

    # abort if heartbeat indicates status is not ok
    If (!$heartbeat.IsOK) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because $($Platform.Name) status is $($platformStatus.RollupStatus.ToUpper())"
        Write-Log -Context $($global:Product.Id) -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Send-TaskMessage -Id $($global:Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

#endregion SERVER/PLATFORM CHECK

# Send-TaskMessage -Id $($global:Product.Id)

$action = $null; $target = $null; $status = $null
try {

    $action = "Initialize"; $target = "AzureAD\$tenantKey"
    Initialize-AzureAD

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace "Tenant Type",$global:AzureAD.$tenantKey.Tenant.Type -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+ -NoTrace "Tenant Name",$global:AzureAD.$tenantKey.Tenant.Name -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+

    $action = "Connect"; $target = "AzureAD\$tenantKey"
    Connect-AzureAD -Tenant $tenantKey

    $action = "Sync"; $target = "AzureAD\$tenantKey\Groups"
    $syncError = Sync-TSGroups -Tenant $tenantKey
    if ($syncError) {
        Assert-SyncError -Target $target -Status "Aborted" -ErrorDetail $syncError
        return
    }

    $action = "Sync"; $target = "AzureAD\$tenantKey\Users"
    $syncError = Sync-TSUsers -Tenant $tenantKey -Delta
    if ($syncError) {
        Assert-SyncError -Target $target -Status "Aborted" -ErrorDetail $syncError
        return
    }

    $status = "Success"

    $action = "Export"; $target = "AzureAD\$tenantKey\Log"
    $message = "<Exporting sync transactions <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $azureADSyncLog = read-log -context AzureADSyncTS
    if ($azureADSyncLog.Count -gt 0) {
        $azureADSyncLog | export-csv "$($azureAD.Data)\AzureADSyncLog.csv"
    }

    $azureADSyncTransactionCount = $azureADSyncLog.Count -gt 0 ? ($azureADSyncLog.Count).ToString() : "None"
    $message = "$($emptyString.PadLeft(8,"`b")) $($azureADSyncTransactionCount)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($azureADSyncLog.Count -gt 0 ? "Green" : "Yellow") 

    if ($azureADSyncLog.Count -gt 0) {
        Write-Host+
        Copy-Files -Path "$($azureAD.Data)\AzureADSyncLog.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
        Write-Host+   
    }

}
catch {

    $status = "Error"
    Write-Log -Context "AzureADSyncTS" -Action $action -Target $target -Status $status -Message $_.Exception.Message -EntryType "Error" -Force
    Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

}
finally {}