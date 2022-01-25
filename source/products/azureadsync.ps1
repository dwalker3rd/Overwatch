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

$global:Product = @{Id="AzureADSync"}
. $PSScriptRoot\definitions.ps1

$emptyString = ""
$tenantKey = "pathseattle"

#region SERVER/PLATFORM CHECK

    # Do NOT continue if ...
    #   1. the host server is starting up or shutting down
    #   2. the platform is not running or is not ok

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)

    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $status = "Aborted"
        $message = "$($Product.Id) $($status.ToLower()) because server $(($serverStatus -split ".")[0].ToUpper()) is $(($serverStatus -split ".")[1].ToUpper())"
        Write-Log -Context $($Product.Id) -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

    $platformStatus = Get-PlatformStatus 

    # abort if platform is stopped or if a platform event is in progress
    if ($platformStatus.IsStopped -or ($platformStatus.Event -and !$platformStatus.EventHasCompleted)) {
        $status = "Aborted"
        $message = "$($Product.Id) $($status.ToLower()) because platform $($Platform.Event.ToUpper()) is $($Platform.EventStatus.ToUpper()) on $($Platform.Name)"
        Write-Log -Context $($Product.Id) -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

    # abort if platform status is not ok
    If (!$platformStatus.IsOK) {
        $status = "Aborted"
        $message = "$($Product.Id) $($status.ToLower()) because $($Platform.Name) status is $($platformStatus.RollupStatus.ToUpper())"
        Write-Log -Context $($Product.Id) -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Send-TaskMessage -Id $($Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

#endregion SERVER/PLATFORM CHECK

Initialize-TSRestApiConfiguration

$action = $null; $target = $null; $status = $null
try {

    $action = "Initialize"; $target = "AzureAD\$tenantKey"
    Initialize-AzureAD

    Write-Host+
    Write-Host+ -NoTrace "Tenant Type",$global:AzureAD.$tenantKey.Tenant.Type -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+ -NoTrace "Tenant Name",$global:AzureAD.$tenantKey.Tenant.Name -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+

    $action = "Connect"; $target = "AzureAD\$tenantKey"
    Connect-AzureAD -Tenant $tenantKey

    $action = "Sync"; $target = "AzureAD\$tenantKey\Groups"
    Sync-TSGroups -Tenant $tenantKey
    $action = "Sync"; $target = "AzureAD\$tenantKey\Users"
    Sync-TSUsers -Tenant $tenantKey -Delta
    $status = "Success"

    $action = "Export"; $target = "AzureAD\$tenantKey\Log"
    $message = "Exporting sync transactions : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADSyncLog = read-log -context AzureADSync
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
    Write-Log -Context "AzureADSync" -Action $action -Target $target -Status $status -Message $_.Exception.Message -EntryType "Error" -Force
    Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

}
finally {}