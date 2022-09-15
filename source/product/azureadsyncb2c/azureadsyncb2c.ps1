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

$global:Product = @{Id="AzureADSyncB2C"}
. $PSScriptRoot\definitions.ps1

$sourceTenantKey = Get-AzureADTenantKeys -AzureAD
$identityIssuer = $global:AzureAD.$sourceTenantKey.IdentityIssuer
$targetTenantKey = Get-AzureADTenantKeys -AzureADB2C

$source = "$(($global:AzureAD.$sourceTenantKey.Tenant.Type).Replace(" ",$null))\$sourceTenantKey"
$target = "$(($global:AzureAD.$targetTenantKey.Tenant.Type).Replace(" ",$null))\$targetTenantKey"

$action = $null; $target = $null; $status = $null

function Assert-SyncError {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][object]$Status,
        [Parameter(Mandatory=$true)][object]$ErrorDetail
    )

    Write-Log -Context $Product.Id -Action "Sync" -Target $Target -Status $ErrorDetail.code -Message $ErrorDetail.summary -EntryType "Error"
    $message = "$($emptyString.PadLeft(8,"`b")) $($ErrorDetail.summary)$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkRed
    
    if ($ErrorDetail.Code -notin ("CACHE.NOTFOUND")) {
        Send-TaskMessage -Id $Product.Id -Status $Status -Message $ErrorDetail.summary -MessageType $PlatformMessageType.Alert   
    }

    Write-Host+
    $message = "AzureADSyncTS $($Status.ToLower()) because $($ErrorDetail.summary)"
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
        $action = "Sync"; $target = "AzureAD\$($targetTenantKey)"; $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Context $($global:Product.Id) -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($global:Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

    # abort if a platform event is in progress
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $action = "Sync"; $target = "AzureAD\$($targetTenantKey)"; $status = "Aborted"
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
        $action = "Sync"; $target = "AzureAD\$($targetTenantKey)"; $status = "Aborted"
        $message = "$($global:Product.Id) $($status.ToLower()) because $($Platform.Name) status is $($platformStatus.RollupStatus.ToUpper())"
        Write-Log -Context $($global:Product.Id) -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        # Send-TaskMessage -Id $($global:Product.Id) -Status $status -MessageType $PlatformMessageType.Warning -Message $message
        return
    }

#endregion SERVER/PLATFORM CHECK

# Send-TaskMessage -Id $($global:Product.Id)

$action = $null; $target = $null; $status = $null
try {

    $action = "Initialize"; $target = "AzureAD\$($targetTenantKey)"
    Initialize-AzureAD

    #region CONNECT SOURCE

        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace "Source", $source -ForegroundColor Gray,DarkBlue -Separator ":  "

        $action = "Connect"; $target = $source
        Connect-AzureAD -Tenant $sourceTenantKey

    #endregion CONNECT SOURCE        
    #region CONNECT TARGET
        
        Write-Host+ -NoTrace "Target", $target -ForegroundColor Gray,DarkBlue -Separator ":  "

        $action = "Connect"; $target = $target
        Connect-AzureAD -Tenant $targetTenantKey

    #endregion CONNECT TARGET    

    Write-Host+ -NoTrace "Issuer", $identityIssuer -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+

    #region GET SOURCE USERS

        $action = "Get"; $target = "$source\Users"
        $message = "<$source users <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $sourceUsers, $cacheError = Get-AzureADusers -Tenant $sourceTenantKey -AsArray
        if ($cacheError) {
            Assert-SyncError -Target $target -Status "Aborted" -ErrorDetail $cacheError
            return
        }

        $message = "$($emptyString.PadLeft(8,"`b")) $($sourceUsers.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    #endregion GET SOURCE USERS
    #region GET TARGET USERS

        $action = "Get"; $target = "$target\Users"
        $message = "<$target users <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        # $global:WriteHostPlusPreference = "SilentlyContinue"
        # Get-AzureADObjects -Tenant $targetTenantKey -Type Users
        # $global:WriteHostPlusPreference = "Continue"

        $targetUsers, $cacheError = Get-AzureADUsers -Tenant $targetTenantKey -AsArray
        if ($cacheError) {
            Assert-SyncError -Target $target -Status "Aborted" -ErrorDetail $cacheError
            return
        }

        $targetUsersFromIdentityIssuer = $targetUsers | Where-Object {$_.identities.issuer -eq $identityIssuer} 

        $message = "$($emptyString.PadLeft(8,"`b")) $($targetUsers.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        $message = "<$target\$identityIssuer users <.>60> $($targetUsersFromIdentityIssuer.Count)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        Write-Host+

    #endregion GET TARGET USERS
    #region TARGET USERS TO DISABLE

        $action = "Disabled"; $target = "$target\Users"
        $message = "<$target users to disable <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $targetUsersEnabledFromIdentityIssuer = $targetUsersFromIdentityIssuer | Where-Object {$_.accountEnabled}
        $targetSignInNames = ($targetUsersEnabledFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
        $sourceUsersDisabled = $sourceUsers | Where-Object {!$_.accountEnabled} | Where-Object {$_.userPrincipalName -in $targetSignInNames}

        $targetUsersToDisable = @()
        foreach ($targetUserEnabledFromIdentityIssuer in $targetUsersEnabledFromIdentityIssuer) {
            $targetSignInName = ($targetUserEnabledFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
            if ($targetSignInName -in $sourceUsersDisabled.userPrincipalName) {
                $targetUsersToDisable += $targetUserEnabledFromIdentityIssuer
            }
        }

        $message = "$($emptyString.PadLeft(8,"`b")) $($targetUsersToDisable.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($targetUsersToDisable.Count -gt 0 ? "DarkRed" : "DarkGray")

    #endregion TARGET USERS TO DISABLE
    #region TARGET USERS TO ENABLE

        $action = "Enabled"; $target = "$target\Users"
        $message = "<$target users to enable <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $targetUsersDisabledFromIdentityIssuer = $targetUsersFromIdentityIssuer | Where-Object {!$_.accountEnabled}
        $targetSignInNames = ($targetUsersDisabledFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
        $sourceUsersEnabled = $sourceUsers | Where-Object {$_.accountEnabled} | Where-Object {$_.userPrincipalName -in $targetSignInNames}

        $targetUsersToEnable = @()
        foreach ($targetUserDisabledFromIdentityIssuer in $targetUsersDisabledFromIdentityIssuer) {
            $targetSignInName = ($targetUserDisabledFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
            if ($targetSignInName -in $sourceUsersEnabled.userPrincipalName) {
                $targetUsersToEnable += $targetUserDisabledFromIdentityIssuer
            }
        }

        $disableAzureADUserOverrideFile = "$($global:Location.Data)\DisableAzureADUserOverride.csv"
        if (Test-Path $disableAzureADUserOverrideFile) {
            $disableAzureADUserOverrides = Import-CSV $disableAzureADUserOverrideFile
            $targetUsersToEnable = $targetUsersToEnable | Where-Object {$_.id -notin $disableAzureADUserOverrides.id}
        }

        $message = "$($emptyString.PadLeft(8,"`b")) $($targetUsersToEnable.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($targetUsersToEnable.Count -gt 0 ? "DarkGreen" : "DarkGray")

    #endregion TARGET USERS TO ENABLE    
    #endregion FIND EMAIL UPDATES

        $targetUsersUpdateEmailConflicts = [array](read-cache "$targetTenantKey-objectconflict-proxyaddress")
        if (!$targetUsersUpdateEmailConflicts) { $targetUsersUpdateEmailConflicts = @() }

        $targetUsersUpdateEmail = $targetUsers | Where-Object {$_.accountEnabled -and [string]::IsNullOrEmpty($_.mail) -and ![string]::IsNullOrEmpty(($_.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId)}
        $targetUsersUpdateEmail = $targetUsersUpdateEmail | Where-Object {$_.id -notin $targetUsersUpdateEmailConflicts.id}

        $message = "<$target user emails to update <.>60> $($targetUsersUpdateEmail.Count)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($targetUsersToEnable.Count -gt 0 ? "DarkGreen" : "DarkGray")

    #endregion FIND EMAIL UPDATES
    #region DISABLE TARGET USERS

        if ($targetUsersToDisable.Count -gt 0) {

            Write-Host+ -MaxBlankLines 1

            $action = "DisableUser"; $target = "$target\Users"
            $message = "<Disabling $target users <.>60> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            if ($targetUsersToDisable.Count -gt 0) {
                Write-Host+
                Write-Host+
            }

            foreach ($targetUserToDisable in $targetUsersToDisable) {

                $targetSignInName = ($targetUserToDisable.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId

                $message = "<  $targetSignInName <.>50> PENDING"
                Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray

                Disable-AzureADUser -Tenant $targetTenantKey -User $targetUserToDisable
                Write-Log -Context "AzureADSyncB2C" -Action $action -Target "$target\$targetSignInName" -Status "Disabled" -Force

                $message = "$($emptyString.PadLeft(8,"`b")) DISABLED$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
                
            }

            if ($targetUsersToDisable.Count -gt 0) {
                Write-Host+
                $message = "<Disabling $target users <.>60> SUCCESS"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
            }
            else {
                $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
            }

        }

    #endregion DISABLE TARGET USERS
    #region ENABLE TARGET USERS

        if ($targetUsersToEnable.Count -gt 0) {

            Write-Host+ -MaxBlankLines 1

            $action = "EnableUser"; $target = "$target\Users"
            $message = "<Enabling $target users <.>60> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            if ($targetUsersToEnable.Count -gt 0) {
                Write-Host+
                Write-Host+
            }

            foreach ($targetUserToEnable in $targetUsersToEnable) {

                $targetSignInName = ($targetUserToEnable.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId

                $message = "<  $targetSignInName <.>50> PENDING"
                Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray

                Enable-AzureADUser -Tenant $targetTenantKey -User $targetUserToEnable
                Write-Log -Context "AzureADSyncB2C" -Action $action -Target "$target\$targetSignInName" -Status "Enabled" -Force

                $message = "$($emptyString.PadLeft(8,"`b")) ENABLED$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                
            }

            if ($targetUsersToEnable.Count -gt 0) {
                Write-Host+
                $message = "Enabling $target users : SUCCESS"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
            }
            else {
                $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
            }

        }

    #endregion ENABLE TARGET USERS    
    #region UPDATE EMAIL

        if ($targetUsersUpdateEmail.Count -gt 0) {

            Write-Host+

            $action = "UpdateEmail"; $target = "$target\Users"
            $message = "<Updating $target user emails <.>60> PENDING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            Write-Host+

            foreach ($targetUserUpdateEmail in $targetUsersUpdateEmail) {

                $targetSignInName = ($targetUserUpdateEmail.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId

                $message = "<  $targetSignInName ($($targetUserUpdateEmail.id)) <.>80> PENDING"
                Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray

                $status = "SUCCESS"
                $response = Update-AzureADUserEmail -Tenant $targetTenantKey -User $targetUserUpdateEmail
                if ($response.error) {
                    $status = "FAILURE"
                    if ($response.error.details.code -contains "ObjectConflict") {
                        $targetUsersUpdateEmailConflicts += $targetUserUpdateEmail
                        $status = "CONFLICT"
                    }
                }

                $statusColor = switch ($status) {
                    "SUCCESS" { "DarkGreen" }
                    "FAILURE" { "Red" }
                    "CONFLICT" { "DarkYellow" }
                }

                $message = "$($emptyString.PadLeft(8,"`b")) $status$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor $statusColor
                
            }

            $targetUsersUpdateEmailConflicts | Write-Cache "$targetTenantKey-objectconflict-proxyaddress"

            Write-Host+

            $message = "<Updating $target user emails <.>60> SUCCESS"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

        }

    #endregion UPDATE EMAIL    

}
catch {

    $status = "Error"
    Write-Log -Context "AzureADSyncB2C" -Action $action -Target $target -Status $status -Message $_.Exception.Message -EntryType "Error" -Force
    Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

}
finally {

    Write-Host+ -MaxBlankLines 1

}