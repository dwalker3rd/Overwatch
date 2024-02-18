$allPathStaffDisplayName = "All PATH Staff"
$azureADAllPathStaffId = "0e3156cd-2ac4-4fa1-b35c-53a2d7ee434c"
$tsServer = "tableau.path.org"
$oktaPathDomain = "path.okta.com"
$oktaAllPathStaffId = "00g3ozoupVPCLLWIXXVZ"

Write-Host+ -Clear

#region Azure

    Initialize-AzureConfig

    #region AzureADB2CUsers

        $tenantKey = Get-AzureTenantKeys -AzureADB2C
        Write-Host+ -NoTrace -NoTimestamp "$tenantKey (AzureADB2C)" -ForegroundColor DarkGray
        Connect-AzureAD -Tenant $tenantKey
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "  Users " -ForegroundColor DarkGray
        $azureADB2CUsers, $cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "($($azureADB2CUsers.count))" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine " Groups " -ForegroundColor DarkGray
        $azureADB2CGroups, $cacheError = Get-AzureADGroups -Tenant $tenantkey -AsArray
        Write-Host+ -NoTrace -NoTimestamp "($($azureADB2CGroups.count))" -ForegroundColor DarkGray
        Write-Host+

    #endregion AzureADB2CUsers

    #region AzureADUsers and AzureADGroups

        $tenantKey = Get-AzureTenantKeys -AzureAD
        Write-Host+ -NoTrace -NoTimestamp "$tenantKey (AzureAD)" -ForegroundColor DarkGray
        Connect-AzureAD -Tenant $tenantKey
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "  Users " -ForegroundColor DarkGray
        $azureADUsers, $cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "($($azureADUsers.count))" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine " Groups " -ForegroundColor DarkGray
        $azureADGroups, $cacheError = Get-AzureADGroups -Tenant $tenantKey -AsArray
        Write-Host+ -NoTrace -NoTimestamp "($($azureADGroups.count))" -ForegroundColor DarkGray
        Write-Host+

    #endregion AzureADUsers and AzureADGroups

#endregion Azure

#region OktaUsers and OktaGroups

    Initialize-OktaRestApiConfiguration -Domain $oktaPathDomain
    Write-Host+ -NoTrace -NoTimestamp "$oktaPathDomain (Okta)" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine "  Users " -ForegroundColor DarkGray
    $oktaUsers = (Read-Cache oktaUsers) ?? (Invoke-OktaRestApiMethod -Method GetUsers)
    $oktaUsers | Write-Cache oktaUsers
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine "($($oktaUsers.count))" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine " Groups " -ForegroundColor DarkGray
    $oktaGroups = (Read-Cache oktaGroups) ?? (Invoke-OktaRestApiMethod -Method GetGroups)
    $oktaGroups | Write-Cache oktaGroups
    Write-Host+ -NoTrace -NoTimestamp "($($oktaGroups.count))" -ForegroundColor DarkGray
    Write-Host+

    # $i=1; $messageLength = 0
    # Set-CursorInvisible
    # foreach ($oktaGroup in $oktaGroups) {
    #     $message = "$($emptyString.PadLeft($messageLength,"`b"))$($emptyString.PadLeft($messageLength," "))$($emptyString.PadLeft($messageLength,"`b"))"
    #     Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
    #     $message = "#$($i): $($oktaGroup.profile.name)"
    #     Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
    #     $messageLength = $message.Length
    #     $oktaGroup | Add-Member -NotePropertyName members -NotePropertyValue @() -Force 
    #     $oktaGroup.members = Invoke-OktaRestApiMethod -Method GetGroupMembership -Params @($oktaGroup.id)
    #     if ($oktaGroup.members.count -gt 0) { 
    #         Write-Host+ -NoTrace -NoTimestamp " ($($oktaGroup.members.count) members)" -ForegroundColor DarkGray
    #         Write-Host+ -ReverseLineFeed 2
    #         $messageLength = 0
    #     }
    #     $i++
    # }
    # Set-CursorVisible

#endregion OktaUsers and OktaGroups

#region Tableau Server 

    Initialize-TSRestApiConfiguration
    Connect-TableauServer -Server $tsServer
    Write-Host+ -NoTrace -NoTimestamp "Tableau Server: ",$tsServer -ForegroundColor DarkGray,DarkBlue
    
    $tsServerUsers = @()
    $tsServerGroups = @()
    $azureADGroupsToSync = @()

    $tsServerUsers = Read-Cache "$($tsServer -replace "\.","-")-users"
    $tsServerGroups = Read-Cache "$($tsServer -replace "\.","-")-groups"

    if ($tsServerUsers.count -eq 0 -or $tsServerGroups.count -eq 0) {
    
        $i=1; $messageLength = 0
        Set-CursorInvisible
        foreach ($tsSite in (Get-TSSites)) {

            $message = "$($emptyString.PadLeft($messageLength,"`b"))$($emptyString.PadLeft($messageLength," "))$($emptyString.PadLeft($messageLength,"`b"))"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
            $message = "  Site #$($i): $($tsSite.name)"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine ($message -split ":")[0], ($message -split ":")[1] -ForegroundColor DarkGray,Gray
            $messageLength = $message.Length
        
            Switch-TSSite -ContentUrl $tsSite.contentUrl
        
            $tsSiteUsers = Get-TSUsers+
            $tsSiteGroups = Get-TSGroups+

            $message = " ($($tsSiteUsers.count)/$($tsSiteGroups.count))"
            Write-Host+ -NoTrace -NoTimestamp ($message -split ":")[0], ($message -split ":")[1] -ForegroundColor DarkGray,Gray
            $messageLength += $message.Length

            $tsServerUsers += $tsSiteUsers
            $tsServerGroups += $tsSiteGroups

            $i++

        }

        Write-Host+

    }

    $tsServerUsers = $tsServerUsers | Where-Object {$_.name -notin $global:tsRestApiConfig.SpecialAccounts}
    $tsServerUsers | Write-Cache "$($tsServer -replace "\.","-")-users"
    $tsServerUsersName = $tsServerUsers.Name.Trim().ToLower() | Sort-Object -Unique
    $message = "  Tableau Server Users ($($tsServerUsersName.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    $tsServerGroups = $tsServerGroups | Where-Object {$_.name -notin $global:tsRestApiConfig.SpecialGroups}
    $tsServerGroups | Write-Cache "$($tsServer -replace "\.","-")-groups"
    $message = "  Tableau Server Groups ($($tsServerGroups.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    $tsSyncSites = (Get-Product azureadsyncts).Config.Sites.ContentUrl
    $message = "  Tableau Server Sync Sites ($($tsSyncSites.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray
    $tsGroupsToSync = ($tsServerGroups | Where-Object {$_.site.contentUrl -in $tsSyncSites}) | Where-Object {$_.name -in $azureADGroups.displayName}
    $message = "  Tableau Server Sync Groups ($($tsGroupsToSync.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray    
    $azureADGroupsToSync = $azureADGroups | Where-Object {$_.displayName -in $tsGroupsToSync.name}
    $message = "  AzureAD Sync Groups ($($azureADGroupsToSync.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    $message = "  AzureADGroupsToSync ($($azureADGroupsToSync.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    Write-Host+

#endregion Tableau Server

#region AllPathStaff Group

    $azureAllPathStaff = Get-AzureADGroup -Tenant $tenantKey -Id $azureADAllPathStaffId
    $azureAllPathStaffName = ($azureAllPathStaff.members | Where-Object {$_.accountEnabled}).userPrincipalName | Sort-Object -Unique
    $message = "  Azure All Path Staff Group and Membership ($($azureAllPathStaffName.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    $oktaAllPathStaff = Invoke-OktaRestApiMethod -Method GetGroup -Params @($oktaAllPathStaffId)
    $oktaAllPathStaff | Add-Member -NotePropertyName members -NotePropertyValue @()
    $oktaAllPathStaff.members = Invoke-OktaRestApiMethod -Method GetGroupMembership -Params @($oktaAllPathStaffId)
    $oktaAllPathStaffName = ($oktaAllPathStaff.members | Where-Object {$_.status -eq "ACTIVE"}).profile.login | Sort-Object -Unique
    $message = "  Okta All Path Staff Group and Membership ($($oktaAllPathStaffName.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    $tsAllPathStaff = $tsServerGroups | Where-Object {$_.name -eq $allPathStaffDisplayName}
    $tsAllPathStaffName = $tsAllPathStaff.membership.name | Sort-Object -Unique
    $message = "  Tableau Server All Path Staff Group and Membership ($($tsAllPathStaffName.count))"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

#endregion AllPathStaff Group

#region AllPathStaff Differences Between Okta and Azure

    $diffsAzureAndOkta = Compare-Object -ReferenceObject $oktaAllPathStaffName -DifferenceObject $azureAllPathStaffName

    if ($diffsAzureAndOkta.cournt -gt 0) {

        $azureAllPathStaffMembersNotInOktaGroup = $azureAllPathStaff.members | Where-Object {$_.userPrincipalName -in $diffsazureandokta.inputObject -and $_.userPrincipalName -notin $oktaAllPathStaff.members.profile.login}
        $azureAllPathStaffMembersNotInOktaGroup | select-Object -excludeproperty proxyAddresses | Format-Table 

        $oktaAllPathStaffMembersNotInAzureAllPathStaffGroup = $oktaAllPathStaff.members | Where-Object {$_.profile.login -in $diffsazureandokta.inputObject -and $_.profile.login -notin $azureAllPathStaff.members.usePrincipalName}
        $oktaAllPathStaffMembersNotInAzureAllPathStaffGroup | Add-Member -NotePropertyName okta -NotePropertyValue @{} -ErrorAction SilentlyContinue
        $oktaAllPathStaffMembersNotInAzureAllPathStaffGroup | Add-Member -NotePropertyName azure -NotePropertyValue @{} -ErrorAction SilentlyContinue
        $oktaAllPathStaffMembersNotInAzureAllPathStaffGroup | Foreach-Object {
            $_.okta = [PSCustomObject]@{
                okta_id = $_.id
                okta_login = $_.profile.login 
                okta_displayName = $_.profile.displayName
                okta_status = $_.status
                okta_lastLogin = $_.lastLogin
                okta_lastUpdated = $_.lastUpdated
            }
            $azureADUser = Get-AzureADUser -Tenant $tenantKey -UserPrincipalName $_.profile.login
            $_.azure = [PSCustomObject]@{
                az_id = $azureADUser.id
                az_userPrincipalName = $azureADUser.userPrincipalName
                az_accountEnabled = $azureADUser.accountEnabled
            }
        }

        Write-Host+ -NoTrace -NoTimestamp "Okta All Path Staff Members Not in Okta All Path Staff Group"
        Write-Host+ -NoTrace -NoTimestamp "------------------------------------------------------------"
        $oktaAllPathStaffMembersNotInAzureAllPathStaffGroup | 
            Select-Object -Property okta, azure |
                Select-Object -Property okta -ExpandProperty azure -ErrorAction SilentlyContinue | 
                    Select-Object -Property az_id, az_userPrincipalName, az_accountEnabled -ExpandProperty okta |
                        Sort-Object -Property login |
                            Format-Table

        $oktaUsersNotInAllPathStaffGroup = $oktaUsers | Where-Object {$_.profile.login -in $diffsAzureAndOkta.InputObject}
        $oktaUsersNotInAllPathStaffGroup | Add-Member -NotePropertyName okta -NotePropertyValue @{} -ErrorAction SilentlyContinue
        $oktaUsersNotInAllPathStaffGroup | Add-Member -NotePropertyName azure -NotePropertyValue @{} -ErrorAction SilentlyContinue
        $oktaUsersNotInAllPathStaffGroup | Foreach-Object {
            $_.okta = [PSCustomObject]@{
                okta_id = $_.id
                okta_login = $_.profile.login 
                okta_displayName = $_.profile.displayName
                okta_status = $_.status
                okta_lastLogin = $_.lastLogin
                okta_lastUpdated = $_.lastUpdated
            }
            $azureADUser = Get-AzureADUser -Tenant $tenantKey -UserPrincipalName $_.profile.login
            $_.azure = [PSCustomObject]@{
                az_id = $azureADUser.id
                az_userPrincipalName = $azureADUser.userPrincipalName
                az_displayName = $_.profile.displayName
                az_accountEnabled = $azureADUser.accountEnabled
            }
        }

        Write-Host+ -NoTrace -NoTimestamp "Okta Users Not in Okta All Path Staff Group"
        Write-Host+ -NoTrace -NoTimestamp "-------------------------------------------"
        $oktaUsersNotInAllPathStaffGroup | 
            Select-Object -Property okta, azure |
                Select-Object -Property okta -ExpandProperty azure -ErrorAction SilentlyContinue | 
                    Select-Object -Property az_id, az_userPrincipalName, az_accountEnabled -ExpandProperty okta |
                        Sort-Object -Property login |
                            Format-Table   

    }
                        
#endregion AllPathStaff Differences Between Okta and Azure

#region AllPathStaff Differences Between Azure and Tableau Server

    $diffsTableauServerAndAzure = Compare-Object -ReferenceObject $azureAllPathStaffName -DifferenceObject $tsAllPathStaffName

    if ($diffsTableauServerAndAzure.count -gt 0) {
    
        $azureAllPathStaffMembersNotInTableauServerUsers = $azureADUsers | Where-Object {$_.userPrincipalName -in $diffsTableauServerAndAzure.InputObject}
        $azureAllPathStaffMembersNotInTableauServerUsers | Add-Member -NotePropertyName tableauserver -NotePropertyValue @{} -Force
        foreach ($azureAllPathStaffMembersNotInTableauServerUser in $azureAllPathStaffMembersNotInTableauServerUsers) {
            $tsServerUser = $tsServerUsers | Where-Object {$_.name -eq $azureAllPathStaffMembersNotInTableauServerUser.userPrincipalName}
            if ($tsServerUser) {
                $azureAllPathStaffMembersNotInTableauServerUser.tableauServer = 
                    [PSCustomObject]@{
                        ts_id = $tsServerUser.id
                        ts_name = $tsServerUser.name
                        ts_fullName = $tsServerUser.fullName
                        ts_siteRole = $tsServerUser.siterole
                        ts_lastLogin = $tsServerUser.lostLogin
                    }
            }
        }

        Write-Host+ -NoTrace -NoTimestamp "Azure AD All Path Staff Members Not in Tableau Server All Path Staff Group"
        Write-Host+ -NoTrace -NoTimestamp "--------------------------------------------------------------------------"
        $azureAllPathStaffMembersNotInTableauServerUsers | 
            Select-Object -Property id, userPrincipalName, displayName, accountEnabled -ExpandProperty tableauserver |
                Sort-Object -Property az_userPrincipalName |
                    Format-Table 

    }

#endregion AllPathStaff Differences Between Azure and Tableau Server