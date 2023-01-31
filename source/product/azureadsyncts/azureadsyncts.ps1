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

#region PRODUCT FUNCTIONS

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

    function global:Sync-TSGroups {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Tenant,
            [switch]$Delta
        )

        $startTime = Get-Date -AsUTC
        $lastStartTime = (Read-Cache "AzureADSyncGroups").LastStartTime ?? [datetime]::MinValue

        $message = "Getting Azure AD groups and users"
        Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

        $message = "<  Group updates <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $azureADGroupUpdates,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray -After $lastStartTime
        if ($cacheError) { return $cacheError }
        
        $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroupUpdates.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

        $message = "<  Groups <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray
        if ($cacheError) { return $cacheError }

        $message = "$($emptyString.PadLeft(8,"`b")) $($azureADGroups.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        
        $message = "<  Users <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray
        if ($cacheError) {  return $cacheError }

        $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

        Write-Host+
        $message = "<Syncing Tableau Server groups <.>48> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        foreach ($contentUrl in $global:Product.Config.Sites.ContentUrl) {

            Switch-TSSite $contentUrl
            $tsSite = Get-TSSite
            Write-Host+ -NoTrace "  Site: $($tsSite.name)"

            $tsGroups = @()
            $tsGroups += Get-TSGroups | Where-Object {$_.name -in $azureADGroups.displayName -and $_.name -notin $global:tsRestApiConfig.SpecialGroups} | Select-Object -Property *, @{Name="site";Expression={$null}} | Sort-Object -Property name

            $tsGroups += @()
            $tsUsers += Get-TSUsers | Sort-Object -Property name

            foreach ($tsGroup in $tsGroups) {

                Write-Host+ -NoTrace -NoNewLine "    Group: $($tsGroup.name)"

                $azureADGroupToSync = $azureADGroups | Where-Object {$_.displayName -eq $tsGroup.name}
                $tsGroupMembership = Get-TSGroupMembership -Group $tsGroup
                $azureADGroupMembership = $azureADUsers | Where-Object {$_.id -in $azureADGroupToSync.members -and $_.accountEnabled} | Where-Object {![string]::IsNullOrEmpty($_.mail)}

                $tsUsersToAddToGroup = @()
                $tsUsersToAddToGroup += ($tsUsers | Where-Object {$_.name -in $azureADGroupMembership.userPrincipalName -and $_.id -notin $tsGroupMembership.id}) ?? @()

                # remove Tableau Server group members if they do not match any of the Azure AD group members UPN or any of the SMTP proxy addresses
                $tsUsersToRemoveFromGroup = $tsGroupMembership | Where-Object {$_.name -notin $azureADGroupMembership.userPrincipalName} #  -and "smtp:$($_.name)" -notin $azureADGroupMembership.proxyAddresses.ToLower()}

                $newUsers = @()

                # add the Azure AD group member if neither the UPN nor any of the SMTP proxy addresses are a username on Tableau Server
                $azureADUsersToAddToSite = $azureADGroupMembership | 
                    # Where-Object {(Get-AzureADUserProxyAddresses -User $_ -Type SMTP -Domain $global:Azure.$Tenant.Sync.Source -NoUPN) -notin $tsUsers.name} | 
                        Where-Object {$_.userPrincipalName -notin $tsUsers.name} | 
                            Sort-Object -Property userPrincipalName
                            
                foreach ($azureADUser in $azureADUsersToAddToSite) {

                    $params = @{
                        Site = $tsSite
                        Username = $azureADUser.userPrincipalName
                        FullName = $azureADUser.displayName
                        Email = $azureADUser.mail
                        SiteRole = $global:TSSiteRoles.IndexOf($tsGroup.import.siteRole) -ge $global:TSSiteRoles.IndexOf($global:Product.Config.$($contentUrl).SiteRoleMinimum) ? $tsGroup.import.siteRole : $global:Product.Config.$($contentUrl).SiteRoleMinimum
                    }

                    $newUser = Add-TSUserToSite @params
                    $newUsers += $newUser

                }

                if ($azureADUsersToAddToSite) {

                    $rebuildSearchIndex = Get-PlatformJob -Type RebuildSearchIndex | Where-Object {$_.status -eq "Created"}

                    if ($rebuildSearchIndex) {
                        $rebuildSearchIndex = $rebuildSearchIndex[0]
                    }
                    else {
                        # force a reindex after creating users to ensure that group updates work
                        $rebuildSearchIndex = Invoke-TsmApiMethod -Method "RebuildSearchIndex"
                    }

                    $rebuildSearchIndex,$timeout = Wait-Platformjob -id $rebuildSearchIndex.id -IntervalSeconds 5 -TimeoutSeconds 60
                    if ($timeout) {
                        # Watch-PlatformJob -Id $rebuildSearchIndex.id -Callback "Write-PlatformJobStatusToLog" -NoMessaging
                    }
                    # Write-PlatformJobStatusToLog -Id $rebuildSearchIndex.id

                }

                foreach ($newUser in $newUsers) {
                    $tsUser = Find-TSUser -name $newUser.Name
                    $tsUsersToAddToGroup += $tsUser
                    $tsUsers += $tsUser
                }

                if ($tsUsersToAddToGroup) {
                    Write-Host+ -NoTrace -NoNewLine -NoTimeStamp "  +$($tsUsersToAddToGroup.count) users" -ForegroundColor DarkGreen
                    Add-TSUserToGroup -Group $tsGroup -User $tsUsersToAddToGroup
                }
                if ($tsUsersToRemoveFromGroup) {
                    Write-Host+ -NoTrace -NoNewLine -NoTimeStamp "  -$($tsUsersToRemoveFromGroup.count) users" -ForegroundColor Red
                    Remove-TSUserFromGroup -Group $tsGroup -User $tsUsersToRemoveFromGroup
                }

                Write-Host+

            }

        }

        @{LastStartTime = $startTime} | Write-Cache "AzureADSyncGroups"

        $message = "<Syncing Tableau Server groups <.>48> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        Write-Host+

    }

    function global:Sync-TSUsers {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Tenant,
            [switch]$Delta
        )

        $startTime = Get-Date -AsUTC
        $lastStartTime = (Read-Cache "AzureADSyncUsers").LastStartTime ?? [datetime]::MinValue

        $message = "Getting Azure AD users ($($Delta ? "Delta" : "Full"))"
        Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Gray

        $message = "<  User updates <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray -After ($Delta ? $lastStartTime : [datetime]::MinValue)
        if ($cacheError) {
            Write-Log -Action "Get-AzureADUsers" -Target ($Delta ? "Delta" : "Full") -Status $cacheError.code -Message $cacheError.summary -EntryType "Error"
            $message = "  $($emptyString.PadLeft(8,"`b")) ERROR$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor Gray,DarkGray,Red
            $message = "<    Error $($cacheError.code) <.>48> $($($cacheError.summary))"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,Red
            return
        }

        $message = "$($emptyString.PadLeft(8,"`b")) $($azureADUsers.Count)$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

        if ($azureADUsers.Count -le 0) {
            Write-Host+
            $message = "<Syncing Tableau Server users <.>48> $($Delta ? 'SUCCESS' : 'CACHE EMPTY')"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($Delta ? "DarkGreen" : "Red")
            Write-Host+
            return
        }

        if ($Delta) {
            Write-Host+
            Write-Host+ -NoTrace "Orphan detection is unavailable with the Delta switch." -ForegroundColor DarkYellow
            Write-Host+
        }    

        Write-Host+ -MaxBlankLines 1
        $message = "<Syncing Tableau Server users <.>48> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        foreach ($contentUrl in $global:Product.Config.Sites.ContentUrl) {

            Switch-TSSite $contentUrl
            $tsSite = Get-TSSite

            [console]::CursorVisible = $false

            $message = "<    $($tssite.name) <.>48> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            $tsUsers = Get-TSUsers | Where-Object {$_.name.EndsWith($global:Azure.$Tenant.Sync.Source) -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

            # check for Tableau Server user names in the Azure AD users' UPN and SMTP proxy addresses
            # $tsUsers = Get-TSUsers | Where-Object {$_.name -in $azureADUsers.userPrincipalName -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

            # tsUsers whose email has changed:  their tsUser name is not the Azure AD UPN, but it is contained in the Azure AD account's SMTP proxy addresses
            # $tsUsers += Get-TSUsers | Where-Object {$_.name -notin $azureADUsers.userPrincipalName -and $_.name -in $azureADUsersSmtpProxyAddresses -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

            # orphaned tsUsers (those without an Azure AD account) excluded by the filter above 
            # $tsUsers = Get-TSUsers | Where-Object {($_.name -notin $azureADUsers.userPrincipalName -and $_.name -notin $azureADUsersSmtpProxyAddresses) -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts} | Sort-Object -Property name

            Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) $($tsUsers.Count)$($emptyString.PadRight(7-$tsUsers.Count.ToString().Length)," ")" -ForegroundColor DarkGreen
            
            $tsUsers | Foreach-Object {

                $tsUser = Get-TSUser -Id $_.id

                $azureADUserAccountAction = "PROFILE"
                $azureADUserAccountActionResult = ""
                $azureADUserAccountState = $tsUser.siteRole -eq "Unlicensed" ? "Disabled" : "Enabled"
                $azureADUserAccountStateColor = "DarkGray";
                $siteRole = $tsUser.siteRole

                # find the Azure AD account (or not), determine the account state, the appropriate account action and set any tsUser properties
                # Azure AD account match: where the Tableau Server user name equals the UPN or is a SMTP address in the proxyAddresses collection
                $azureADUser = $azureADUsers | Where-Object {$_.userPrincipalName -eq $tsUser.name}

                # typical azureADUser and tsUser account scenarios
                # the tsUser's account state should match the azureADUser's account state
                if ($azureADUser) {
                    
                    # the azureADUser account is enabled; the tsUser account is disabled
                    if ($azureADUser.accountEnabled -and $tsUser.siteRole -eq "Unlicensed") {
                        $azureADUserAccountAction = "ENABLE"; $azureADUserAccountState = "Enabled"; $azureADUserAccountActionResult = "Enabled"; $azureADUserAccountStateColor = "DarkGreen"; $siteRole = $tsUser.siteRole
                    }

                    # the azureADUser account is disabled; the tsUser account is NOT disabled (enabled)
                    elseif (!$azureADUser.accountEnabled -and $tsUser.siteRole -ne "Unlicensed") {
                        $azureADUserAccountAction = "DISABLE"; $azureADUserAccountState = "Disabled"; $azureADUserAccountActionResult = "Disabled"; $azureADUserAccountStateColor = "Red"; $siteRole = "Unlicensed"
                    }

                    # the azureADUser account's state is equivalent to the tsUser account's state 
                    else {
                        $azureADUserAccountAction = "PROFILE"; $azureADUserAccountState = $azureADUser.accountEnabled ? "Enabled" : "Disabled"; $azureADUserAccountActionResult = "";  $azureADUserAccountStateColor = "DarkGray"; $siteRole = $tsUser.siteRole
                    }

                }

                # special azureADUser and tsUser account scenarios
                # email changes requiring a replacement tsUser account and orphaned tsUser accounts
                elseif ($tsUser.siteRole -ne "Unlicensed") {

                    # changes to the email address for an azureADUser account
                    # the tsUser account uses the azureADUser account email for the tsUser name
                    # the tsUser name is a key field and is immutable
                    # thus, the tsUser account where the name is equivalent to the original email
                    # must be replaced with a new tsUser account using the new email address
                    
                    # determining that an azureADUser account's email has changed:
                    # no azureADUser account exists with a UPN that matches the tsUser name, and 
                    # the tsUser name exists in an azureADUser account's smtp proxy addresses
                    
                    $azureADUser = $azureADUsers | Where-Object {$tsUser.name -in (Get-AzureADUserProxyAddresses -User $_ -Type SMTP -Domain $global:Azure.$Tenant.Sync.Source -NoUPN)}
                    if ($azureADUser) {

                        # found the new azureADUser, but don't replace the user until the tsNewUser is created 
                        # Sync-TSUsers will create the new user and leave the old one in place until this point
                        $tsNewUser = Find-TSUser -Name $azureADUser.userPrincipalName

                        # if tsNewUser has been created, proceed with replacing user; otherwise continue to wait
                        $azureADUserAccountAction = "PENDING"; $azureADUserAccountState = "Replaced"; $azureADUserAccountActionResult = "Pending"; $azureADUserAccountStateColor = "DarkBlue"; 
                        if ($tsNewUser) { $azureADUserAccountAction = "REPLACE"; $azureADUserAccountActionResult = "Replaced"}
            
                        $siteRole = $tsUser.siteRole

                    }

                    # orphaned tsUser accounts (no associated azureADUser account)
                    else {

                        # Orphan detection is unavailable when the Delta switch is used.
                        # why? b/c -delta only pulls the latest user updates from the cache and orphan
                        # detection requires the full user cache

                        if (!$Delta) {

                            # if only relying on azureADUsers pulled from AzureADCache then an AzureADCache failure would 
                            # cause Sync-TSUsers to incorrectly categorize tsUsers without Azure AD accounts as false
                            # orphans.  true orphans should [probably] have their tsUser account disabled.  However, 
                            # disabling a tsUser's account (i.e., setting their siteRole to "Unlicensed") requires first 
                            # that the tsUser be removed from all groups.  As there is no persistence of the tsUser's state,
                            # if AzureADCache does fail, then recovery is minimal as disabled false orphans could not be fully
                            # restored without having some record of their previous state (e.g., group membership).

                            # to avoid this, use Get-AzureADUser to query MSGraph directly and confirm whether the tsUser
                            # account has really been orphaned.  NOTE: if AzureADCache does fail, there will be a HUGE list 
                            # of false orphans which would need to be confirmed. calling Get-AzureADUser for every false orphan
                            # would be VERY slow.  there should probably be a governor for this (only X confirmations per pass).

                            $message = ""
                            $azureADUserAccountAction = "ORPHAN?"; $azureADUserAccountState = "Orphaned"; $azureADUserAccountActionResult = "Pending"; $azureADUserAccountStateColor = "DarkGray"; 
                            if ($tsUser.siteRole -ne "Unlicensed") {

                                # query MSGraph directly to confirm orphan
                                $azureADUser = Get-AzureADUser -Tenant $Tenant -User $tsUser.name

                                # found no azureADUser; orphan confirmed
                                # after notification/logging, ORPHAN will be converted into DISABLE
                                if (!$azureADUser) {
                                    $azureADUserAccountAction = "ORPHAN+"; $azureADUserAccountState = "Orphaned"; $azureADUserAccountActionResult = "Confirmed"; $azureADUserAccountStateColor = "DarkYellow"; $siteRole = "Unlicensed"
                                    $message = "$azureADUserAccountActionResult orphan"
                                }

                                # azureADUser found! no specific action; let the AzureADSync suite should sort it out
                                # however, highlight it and log it as a false orphan in case there's a larger AzureADSync suite issue
                                else {
                                    $azureADUserAccountAction = "ORPHAN-"; $azureADUserAccountState = "Orphaned"; $azureADUserAccountActionResult = "Refuted"; $azureADUserAccountStateColor = "DarkYellow"; $siteRole = $tsUser.siteRole
                                    $message = "See the following Azure AD account: $Tenant\$($azureADUser.userPrincipalName)."
                                }

                                Write-Log -Action "IsOrphan" -Target "$($global:tsRestApiConfig.ContentUrl)\$($tsUser.name)" -Status $azureADUserAccountActionResult -Message $message -Force 
                            }

                        }

                    }

                }

                Write-Host+ -NoTrace "      $($azureADUserAccountAction): $($tsSite.contentUrl)\$($tsUser.name) == $($tsUser.fullName ?? "null") | $($tsUser.email ?? "null") | $($tsUser.siteRole) | AzureAD:$($azureADUserAccountState)" -ForegroundColor $azureADUserAccountStateColor

                # after notification/logging, convert ORPHAN+ to DISABLED
                if ($azureADUserAccountAction -eq "ORPHAN+") {
                    $azureADUserAccountAction = "DISABLE"; $azureADUserAccountState = "Disabled"; $azureADUserAccountActionResult = "Disabled"; $azureADUserAccountStateColor = "Red"; $siteRole = "Unlicensed"
                }

                if ($azureADUserAccountAction -eq "REPLACE") {

                    # update group membership of new tsUser
                    Get-TSUserMembership -User $tsUser | Foreach-Object { Add-TSUserToGroup -Group $_ -User $tsNewUser }
                
                    # change content ownership
                    Get-TSWorkbooks -Filter "ownerEmail:eq:$($tsUser.email)" | Foreach-Object {Update-TSWorkbook -Workbook $_ -Owner $tsNewUser | Out-Null }
                    Get-TSDatasources -Filter "ownerEmail:eq:$($tsUser.email)" | Foreach-Object {Update-TSDatasource -Datasource $_ -Owner $tsNewUser | Out-Null }
                    Get-TSFlows -Filter "ownerName:eq:$($tsUser.fullName)" | Foreach-Object {Update-TSFlow -Flow $_ -Owner $tsNewUser | Out-Null }
                    Get-TSMetrics -Filter "ownerEmail:eq:$($tsUser.email)" | Foreach-Object {Update-TSMetric -Metric $_ -Owner $tsNewUser | Out-Null }

                    Write-Log -Action ((Get-Culture).TextInfo.ToTitleCase($azureADUserAccountAction)) -Target "$($global:tsRestApiConfig.ContentUrl)\$($tsUser.name)" -Status $azureADUserAccountActionResult -Force
                    Write-Host+ -NoTrace "      $($azureADUserAccountAction): $($tsSite.contentUrl)\$($tsNewUser.name) << $($tsSite.contentUrl)\$($tsUser.name)" -ForegroundColor DarkBlue

                    # set action/state for tsUser to be disabled below
                    $azureADUserAccountAction = "DISABLE"; $azureADUserAccountState = "Disabled"; $azureADUserAccountActionResult = "Disabled"; $azureADUserAccountStateColor = "Red"; $siteRole = "Unlicensed"

                }

                # set fullName and email
                $fullName = $azureADUser.displayName ?? $tsUser.fullName
                $email = $azureADUser.mail ?? $($tsUser.email ?? $tsUser.name)
                
                # if changes to fullName, email or siteRole, update tsUser
                # Update-TSUser replaces both apostrophe characters ("'" and "’") in fullName and email with "&apos;" (which translates to "'")
                # Replace "’" with "'" in order to correctly compare fullName and email from $tsUser and $azureADUser 
                
                if ($fullName.replace("’","'") -ne $tsUser.fullName -or $email.replace("’","'") -ne $tsUser.email -or $siteRole -ne $tsUser.siteRole) {

                    if ($azureADUserAccountAction -ne "DISABLE") {
                        $azureADUserAccountAction = " UPDATE"; $azureADUserAccountActionResult = "Updated"; $azureADUserAccountStateColor = "DarkGreen"
                    }

                    # update the user
                    $response, $responseError = Update-TSUser -User $tsUser -FullName $fullName -Email $email -SiteRole $siteRole | Out-Null
                    if ($responseError) {
                        Write-Log -Action ((Get-Culture).TextInfo.ToTitleCase($azureADUserAccountAction)) -Target "$($tsSite.contentUrl)\$($tsUser.name)" -Message "$($responseError.detail)" -EntryType "Error" -Status "Error"
                        Write-Host+ "      $($response.error.detail)" -ForegroundColor Red
                    }
                    else {
                        Write-Host+ -NoTrace "      $($azureADUserAccountAction): $($tsSite.contentUrl)\$($tsUser.name) << $fullName | $email | $siteRole" -ForegroundColor $azureADUserAccountStateColor
                        # Write-Log -Action ((Get-Culture).TextInfo.ToTitleCase($azureADUserAccountAction)) -Target "$($global:tsRestApiConfig.ContentUrl)\$($tsUser.name)" -Status $azureADUserAccountActionResult -Force 
                    }
                }

            }
        
        }

        @{LastStartTime = $startTime} | Write-Cache "AzureADSyncUsers"

        $message = "<  Syncing Tableau Server users <.>48> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
        
        Write-Host+

    }

#endregion PRODUCT FUNCTIONS

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

$tenantKey = Get-AzureTenantKeys -AzureAD

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

    # context now uses UID format:  temporarily replace it with just the product id so the tableau server vizs keep working
    $azureADSyncLog = Read-Log -Context $Product.Id,"Product.$($Product.Id)" 
    $azureADSyncLog | ForEach-Object {$_.Context = $Product.Id}
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
    Write-Log -Action $action -Target $target -Status $status -Message $_.Exception.Message -EntryType "Error" -Force
    Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

}
finally {

    Write-Host+ -MaxBlankLines 1
    Remove-PSSession+

}
