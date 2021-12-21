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

$global:Product = @{Id="AzureADCache"}
. $PSScriptRoot\definitions.ps1

#region SERVER/PLATFORM CHECK

    # Do NOT continue if ...
    #   1. the host server is starting up or shutting down
    #   2. the platform is not running or is not ok

    # check for server shutdown/startup events
    $serverStatus = Confirm-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    
    switch ($serverStatus) {
        "Startup.InProgress" {return}
        "Shutdown.InProgress" {return}
        default {}
    }

    # check that the monitor product has confirmed that the platform is running and ok
    If (!(Get-Heartbeat).IsOk) {return}

#endregion SERVER/PLATFORM CHECK

$emptyString = ""
$tenantKey = ""

# $locked, $selfLocked = Test-IsProductLocked -Name @("AzureADCache", "AzureADSync") -Silent
# if ($locked) {return}

# Lock-Product "AzureADCache"

# Write-Log -Context "AzureADCache" -Action "Heartbeat" -Status "Start" -Target "AzureAD\$tenantKey" -Force

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

    $action = "Get"; $target = "AzureAD\$tenantKey\Groups"
    Get-AzureADObjects -Tenant $tenantKey -Type Groups -Delta
    $action = "Get"; $target = "AzureAD\$tenantKey\Users"
    Get-AzureADObjects -Tenant $tenantKey -Type Users -Delta
    $status = "Success"

    $action = "Export"; $target = "AzureAD\$tenantKey\Users"
    $message = "Exporting user cache : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray
    $azureADUsers | Sort-Object -property userPrincipalName | 
        Select-Object -property @{name="User Id";expression={$_.id}},@{name="User Principal Name";expression={$_.userPrincipalName}},@{name="User Display Name";expression={$_.displayName}},@{name="User Mail";expression={$_.mail}},@{name="User Account Enabled";expression={$_.accountEnabled}},timestamp | 
            Export-Csv  "$($azureAD.Data)\$tenantKey-users.csv"

    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

    Write-Host+
    Copy-Files -Path "$($azureAD.Data)\$tenantKey-users.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
    Write-Host+

    $action = "Export"; $target = "AzureAD\$tenantKey\Groups"
    $message = "Exporting group cache : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $tenantKey -AsArray
    $azureADGroups | Sort-Object -property displayName | 
        Select-Object -property @{name="Group Id";expression={$_.id}},@{name="Group Display Name";expression={$_.displayName}},@{name="Group Security Enabled";expression={$_.securityEnabled}},@{name="Group Type";expression={$_.groupTypes}},timestamp  | 
            Export-Csv  "$($azureAD.Data)\$tenantKey-groups.csv"
    ($azureADGroups | Foreach-Object {$groupId = $_.id; $_.members | Foreach-Object { @{groupId = $groupId; userId=$_} } }) | 
        Sort-Object -property groupId,userId -unique | 
            Select-Object -property @{name="Group Id";expression={$_.groupId}}, @{name="User Id";expression={$_.userId}} | 
                Export-Csv  "$($azureAD.Data)\$tenantKey-groupMembership.csv"

    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

    Write-Host+
    Copy-Files -Path "$($azureAD.Data)\$tenantKey-groups.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
    Copy-Files -Path "$($azureAD.Data)\$tenantKey-groupMembership.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
    Write-Host+

}
catch {

    $status = "Error"
    Write-Log -Context "AzureADCache" -Action $action -Target $target -Status $status -EntryType "Error" -Message $_.Exception.Message -Force
    Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

}
finally {

    # Unlock-Product "AzureADCache" -Status ($status ?? "Aborted")

    # $lock = Read-Cache "AzureADCache"
    # $lockPeriod = $lock.EndTime - $lock.StartTime
    # Write-Log -Context "AzureADCache" -Action "Heartbeat" -Status "Stop" -Target "AzureAD\$tenantKey" -Data $lockPeriod.TotalMilliseconds -Force

}