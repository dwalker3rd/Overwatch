#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id="AzureADSyncB2C"}
. $PSScriptRoot\definitions.ps1

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
        $action = "Sync"; $target = "$($targetTenantKey)"; $status = "Aborted"
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

    $platformStatus = Get-PlatformStatus 
    $heartbeat = Get-Heartbeat

    # abort if a platform event is in progress
    if (![string]::IsNullOrEmpty($platformStatus.Event) -and !$platformStatus.EventHasCompleted) {
        $action = "Sync"; $target = "$($targetTenantKey)"; $status = "Aborted"
        $message = $platformStatus.IsStopped ? "Platform is STOPPED" : "Platform $($platformStatus.Event.ToUpper()) $($platformStatus.EventStatus.ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

    # abort if heartbeat indicates status is not ok
    If (!$heartbeat.IsOK) {
        $action = "Sync"; $target = "$($targetTenantKey)"; $status = "Aborted"
        $message = "$($Platform.Name) status is $($platformStatus.RollupStatus.ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

#endregion SERVER/PLATFORM CHECK

$targetTenantKey = Get-AzureTenantKeys -AzureADB2C
$sourceTenantKey = $global:Azure.$targetTenantKey.Sync.Source
$identityIssuer = $global:Azure.$sourceTenantKey.Sync.IdentityIssuer

$action = $null; $target = $null; $status = $null
try {

    $action = "Initialize"; $target = "$($targetTenantKey)"
    Initialize-AzureConfig

    #region CONNECT SOURCE

        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace "Source", "$($sourceTenantKey)" -ForegroundColor Gray,DarkBlue -Separator ":  "

        $action = "Connect"; $target = "$($sourceTenantKey)"
        Connect-AzureAD -Tenant $sourceTenantKey

    #endregion CONNECT SOURCE        
    #region CONNECT TARGET
        
        Write-Host+ -NoTrace "Target", "$($targetTenantKey)" -ForegroundColor Gray,DarkBlue -Separator ":  "

        $action = "Connect"; $target = "$($targetTenantKey)"
        Connect-AzureAD -Tenant $targetTenantKey

    #endregion CONNECT TARGET    

    Write-Host+ -NoTrace "Issuer", $identityIssuer -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+

    #region GET SOURCE USERS

        $action = "Get"; $target = "$($sourceTenantKey)\Users"
        $message = "<$target <.>60> PENDING"
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

        $action = "Get"; $target = "$($targetTenantKey)\Users"
        $message = "<$target <.>60> PENDING"
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

        $action = "Disabled"; $target = "$($targetTenantKey)\Users"
        $message = "<$target\Disable <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        # users from the identity issuer
        $targetUsersEnabledFromIdentityIssuer = $targetUsersFromIdentityIssuer | Where-Object {$_.accountEnabled}
        $targetSignInNames = ($targetUsersEnabledFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
        $sourceUsersDisabled = $sourceUsers | Where-Object {!$_.accountEnabled} | Where-Object {$_.userPrincipalName -in $targetSignInNames}

        $targetUsersToDisable = @()
        foreach ($targetUserEnabledFromIdentityIssuer in $targetUsersEnabledFromIdentityIssuer) {
            $targetSignInName = ($targetUserEnabledFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
            if ($targetSignInName -in $sourceUsersDisabled.userPrincipalName) {
                # $targetUserEnabledFromIdentityIssuer is from the $targetUsers cache
                # get user info directly from AD to get latest value of accountEnabled
                $targetAzureADUser = Get-AzureADUser -Tenant $targetTenantKey -Id $targetUserEnabledFromIdentityIssuer.id
                if ($targetAzureADUser.accountEnabled) {
                    $targetUsersToDisable += $targetUserEnabledFromIdentityIssuer
                }
            }
        }

        # local/guest accounts with the same email as the one from the identity issuer (just above)
        $targetUsersFromIdentityIssuerEmails = ($targetUsersFromIdentityIssuer.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
        $targetUsersAssociatedWithIdentityIssuer = $targetUsers | Where-Object {$_.mail -in $targetUsersFromIdentityIssuerEmails}

        $targetUsersEnabledFromIdentityIssuer = $targetUsersAssociatedWithIdentityIssuer | Where-Object {$_.accountEnabled}
        $targetSignInNames = ($targetUsersEnabledFromIdentityIssuer | Where-Object {$null -ne $_.mail}).mail
        $sourceUsersDisabled = $sourceUsers | Where-Object {!$_.accountEnabled} | Where-Object {$_.userPrincipalName -in $targetSignInNames}

        foreach ($targetUserEnabledFromIdentityIssuer in $targetUsersEnabledFromIdentityIssuer) {
            $targetSignInName = ($targetUserEnabledFromIdentityIssuer | Where-Object {$null -ne $_.mail}).mail
            if ($targetSignInName -in $sourceUsersDisabled.userPrincipalName -and $targetSignInName -notin $targetUsersToDisable.mail) {
                # $targetUserEnabledFromIdentityIssuer is from the $targetUsers cache
                # get user info directly from AD to get latest value of accountEnabled
                $targetAzureADUser = Get-AzureADUser -Tenant $targetTenantKey -Id $targetUserEnabledFromIdentityIssuer.id
                if ($targetAzureADUser.accountEnabled) {
                    $targetUsersToDisable += $targetUserEnabledFromIdentityIssuer
                }
            }
        }
        

        $message = "$($emptyString.PadLeft(8,"`b")) $($targetUsersToDisable.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($targetUsersToDisable.Count -gt 0 ? "DarkRed" : "DarkGray")

    #endregion TARGET USERS TO DISABLE
    #region TARGET USERS TO ENABLE

        $action = "Enabled"; $target = "$($targetTenantKey)\Users"
        $message = "<$target\Enable <.>60> PENDING"
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

        $proxyAddressConflictCache = "$targetTenantKey-objectconflict-proxyaddress"
        $proxyAddressConflicts = [array](read-cache $proxyAddressConflictCache)
        if (!$proxyAddressConflicts) { $proxyAddressConflicts = @() }

        # Azure AD B2C users with a null mail property where the emailaddress 
        # identity's issuerAssignedId ends with the Azure AD tenant's source AD domain
        $targetUsersUpdateEmail = $targetUsers | 
            Where-Object {$_.accountEnabled -and [string]::IsNullOrEmpty($_.mail) -and 
                ![string]::IsNullOrEmpty(($_.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId) -and 
                ($_.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId.endswith($global:Azure.$sourceTenantKey.Sync.Source)} | 
                    Where-Object {$_.id -notin $proxyAddressConflicts.id}

        $message = "<$target\Email\Update <.>60> $($targetUsersUpdateEmail.Count)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($targetUsersUpdateEmail.Count -gt 0 ? "DarkGreen" : "DarkGray")

    #endregion FIND EMAIL UPDATES
    #endregion FIND NAME UPDATES

        # All Azure AD users' SMTP proxyAddresses which are not equal to the Azure AD user's 
        # UPN and end with the Azure AD tenant's source AD domain
        $sourceUsersSmtpProxyAddresses = (Get-AzureADUserProxyAddresses -User $sourceUsers -Type SMTP -Domain $global:Azure.$sourceTenantKey.Sync.Source -NoUPN)

        # Azure AD B2C users whose mail is in an Azure AD user's proxyAddresses (and is not the UPN)
        $targetUsersUpdateIdentity = $targetUsers | 
            Where-Object {$_.accountEnabled -and 
                ![string]::IsNullOrEmpty(($_.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId) -and 
                $_.mail -in $sourceUsersSmtpProxyAddresses}

        $message = "<$target\Name\Update <.>60> $($targetUsersUpdateIdentity.Count)"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($targetUsersUpdateIdentity.Count -gt 0 ? "DarkGreen" : "DarkGray")
        
    #endregion FIND NAME UPDATES
    #region DISABLE TARGET USERS

        if ($targetUsersToDisable.Count -gt 0) {

            Write-Host+ -MaxBlankLines 1

            $action = "DisableUser"; $target = "$($targetTenantKey)\Users"
            $message = "<Disabling $target users <.>60> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            if ($targetUsersToDisable.Count -gt 0) {
                Write-Host+
                Write-Host+
            }

            foreach ($targetUserToDisable in $targetUsersToDisable) {

                $targetSignInName = ($targetUserToDisable.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
                if ([string]::IsNullOrEmpty($targetSignInName)) {
                    $targetSignInName = $targetUserToDisable.mail
                }

                $message = "<  $targetSignInName <.>50> PENDING"
                Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray

                Disable-AzureADUser -Tenant $targetTenantKey -User $targetUserToDisable
                Write-Log -Action $action -Target "$target\$targetSignInName" -Status "Disabled" -Force

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

            $action = "EnableUser"; $target = "$($targetTenantKey)\Users"
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
                Write-Log -Action $action -Target "$target\$targetSignInName" -Status "Enabled" -Force

                $message = "$($emptyString.PadLeft(8,"`b")) ENABLED$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                
            }

            if ($targetUsersToEnable.Count -gt 0) {
                Write-Host+
                $message = "<Enabling $target users <.>60> SUCCESS"
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

            $action = "UpdateEmail"; $target = "$($targetTenantKey)\Users"
            $message = "<Updating $target email <.>60> PENDING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            Write-Host+

            foreach ($targetUserUpdateEmail in $targetUsersUpdateEmail) {

                $targetSignInName = ($targetUserUpdateEmail.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId

                $message = "<  $targetSignInName ($($targetUserUpdateEmail.id)) <.>80> PENDING"
                Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray

                $status = "SUCCESS"
                $response = Update-AzureADUserEmail -Tenant $targetTenantKey -User $targetUserUpdateEmail -mail $targetSignInName
                if ($response.error) {
                    $status = "FAILURE"
                    if ($response.error.details.code -contains "ObjectConflict") {
                        $status = "ProxyAddressConflict"; $entryType = "Warning"
                        $proxyAddressConflicts += $targetUserUpdateEmail
                        Write-Log -Action "Resolve" -Target "$tenantKey\Users\$($User.id)" -Message "$targetSignInName added as exclusion to ProxyAddressConflict list." -Status "Mitigated" -EntryType $entryType -Force
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

            $proxyAddressConflicts | Write-Cache $proxyAddressConflictCache

            Write-Host+

            $message = "<Updating $target email <.>60> SUCCESS"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

        }

    #endregion UPDATE EMAIL    
    #region UPDATE NAMES

    if ($targetUsersUpdateIdentity.Count -gt 0) {

        Write-Host+

        $action = "UpdateIdentity"; $target = "$($targetTenantKey)\Users"
        $message = "<Updating $target user names <.>60> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        foreach ($targetUserUpdateIdentity in $targetUsersUpdateIdentity) {

            $sourceUser = Get-AzureADUser -Tenant $sourceTenantKey -UserPrincipalName ($sourceUsers | Where-Object {$_.proxyAddresses -and $targetUserUpdateIdentity.mail -in (Get-AzureADUserProxyAddresses -User $_ -Type SMTP -Domain $global:Azure.$sourceTenantKey.Sync.Source -NoUPN)}).userPrincipalName
            $targetSignInName = $sourceUser.mail

            $message = "<  $targetSignInName ($($targetUserUpdateIdentity.id)) <.>80> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,DarkGray,DarkGray

            $status = "SUCCESS"
            $response = Update-AzureADUserEmail -Tenant $targetTenantKey -User $targetUserUpdateIdentity -mail $targetSignInName
            if (!$response.error) {
                $response = Update-AzureADUserNames -Tenant $targetTenantKey -User $targetUserUpdateIdentity -SurName $sourceUser.surName -GivenName $sourceUser.givenName -DisplayName $sourceUser.displayName
            }
            if ($response.error) {
                $status = "FAILURE"
            }

            $statusColor = switch ($status) {
                "SUCCESS" { "DarkGreen" }
                "FAILURE" { "Red" }
            }

            $message = "$($emptyString.PadLeft(8,"`b")) $status$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor $statusColor
            
        }

        Write-Host+

        $message = "<Updating $target user names <.>60> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    }

#endregion UPDATE NAMES        

}
catch {

    Write-Log -Exception $_.Exception
    Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkRed

}
finally {

    Write-Host+ -MaxBlankLines 1
    Remove-PSSession+

}