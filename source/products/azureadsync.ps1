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

#region SERVER

    # check for server shutdown/startup events
    $return = $false
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    $return = switch (($serverStatus -split ",")[1]) {
        "InProgress" {$true}
    }
    if ($return) {
        $message = "Exiting due to server status: $serverStatus"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Write-Log -Action "Monitor" -Message $message -EntryType "Warning" -Status "Exiting" -Force
        return
    }

#endregion SERVER
#region PLATFORM

    # check for platform stop/start/restart events
    $return = $false
    $platformStatus = Get-PlatformStatus 
    $return = $platformStatus.RollupStatus -in @("Stopped","Stopping","Starting","Restarting") -or $platformStatus.Event
    if ($return) {
        $message = "Exiting due to platform status: $($platformStatus.RollUpStatus)"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Write-Log -Action "Monitor" -Message $message -EntryType "Warning" -Status "Exiting" -Force
        return
    }

# endregion PLATFORM

$emptyString = ""
$tenantKey = ""

# $locked, $selfLocked, $lock = Test-IsProductLocked -Name @("AzureADSync","AzureADCache") -Silent
# if ($locked) {return}

# Lock-Product "AzureADSync"

# Write-Log -Context "AzureADSync" -Action "Heartbeat" -Status "Start" -Target "AzureAD\$tenantKey" -Force

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
finally {

    # Unlock-Product "AzureADSync" -Status ($status ?? "Aborted")

    # $lock = Read-Cache "AzureADSync"
    # $lockPeriod = $lock.EndTime - $lock.StartTime
    # Write-Log -Context "AzureADSync" -Action "Heartbeat" -Status "Stop" -Target "AzureAD\$tenantKey" -Data $lockPeriod.TotalMilliseconds -Force

}