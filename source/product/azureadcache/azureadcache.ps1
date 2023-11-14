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

$global:Product = @{Id="AzureADCache"}
. $PSScriptRoot\definitions.ps1

$tenantKeys = Get-AzureTenantKeys
$action = $null; $target = $null; $status = $null

#region SERVER/PLATFORM CHECK

    # Do NOT continue if ...
    #   1. the host server is starting up or shutting down
    #   2. the platform is not running or is not ok

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $action = "Cache"; $target = "AzureAD\$($tenantKeys[0])"; $status = "Aborted"
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

    # abort if a platform event is in progress
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $action = "Cache"; $target = "AzureAD\$($tenantKeys[0])"; $status = "Aborted"
        $message = $platformStatus.IsStopped ? "Platform is STOPPED" : "Platform $($platformStatus.Event.ToUpper()) $($platformStatus.EventStatus.ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

    # abort if heartbeat indicates status is not ok
    If (!$heartbeat.IsOK) {
        $action = "Cache"; $target = "AzureAD\$($tenantKeys[0])"; $status = "Aborted"
        $message = "$($Platform.Name) status is $($platformStatus.RollupStatus.ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

#endregion SERVER/PLATFORM CHECK

foreach ($tenantKey in $tenantKeys) {

    

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

        if ($global:Azure.$tenantKey.Tenant.Type -eq "Azure AD B2C") {
            Write-Host+ -NoTrace "Delta switch ignored for Azure AD B2C tenants." -ForegroundColor DarkYellow
            Write-Host+
        }

        $action = "Get"; $target = "AzureAD\$tenantKey\Groups"
        Get-AzureADObjects -Tenant $tenantKey -Type Groups -Delta
        $action = "Get"; $target = "AzureAD\$tenantKey\Users"
        Get-AzureADObjects -Tenant $tenantKey -Type Users -Delta

        $action = "Export"; $target = "AzureAD\$tenantKey\Users"
        $message = "<Exporting user cache <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray
        $azureADUsers | Sort-Object -property userPrincipalName | 
            Select-Object -property @{name="User Id";expression={$_.id}},@{name="User Principal Name";expression={$_.userPrincipalName}},@{name="User Display Name";expression={$_.displayName}},@{name="User Mail";expression={$_.mail}},@{name="User Account Enabled";expression={$_.accountEnabled}},timestamp | 
                Export-Csv  "$($global:Azure.Location.Data)\$tenantKey-users.csv"

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

        Write-Host+
        Copy-Files -Path "$($global:Azure.Location.Data)\$tenantKey-users.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
        Write-Host+

        $action = "Export"; $target = "AzureAD\$tenantKey\Groups"
        $message = "<Exporting group cache <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $tenantKey -AsArray
        $azureADGroups | Sort-Object -property displayName | 
            Select-Object -property @{name="Group Id";expression={$_.id}},@{name="Group Display Name";expression={$_.displayName}},@{name="Group Security Enabled";expression={$_.securityEnabled}},@{name="Group Type";expression={$_.groupTypes}},timestamp  | 
                Export-Csv  "$($global:Azure.Location.Data)\$tenantKey-groups.csv"
        ($azureADGroups | Foreach-Object {$groupId = $_.id; $_.members | Foreach-Object { @{groupId = $groupId; userId=$_} } }) | 
            Sort-Object -property groupId,userId -unique | 
                Select-Object -property @{name="Group Id";expression={$_.groupId}}, @{name="User Id";expression={$_.userId}} | 
                    Export-Csv  "$($global:Azure.Location.Data)\$tenantKey-groupMembership.csv"

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

        Write-Host+
        Copy-Files -Path "$($global:Azure.Location.Data)\$tenantKey-groups.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
        Copy-Files -Path "$($global:Azure.Location.Data)\$tenantKey-groupMembership.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
        Write-Host+

    }
    catch {

        Write-Log -Exception $_.Exception
        Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkRed

    }
    finally {

        Write-Host+ -MaxBlankLines 1
        Remove-PSSession+

    }
}