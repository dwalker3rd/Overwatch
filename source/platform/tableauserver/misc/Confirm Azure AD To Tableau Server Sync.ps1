Write-Host+ -Clear

$tsServer = "tableau.path.org"
$tsSyncedSitesContentUrl = (Get-Product -Id azureadsyncts).config.Sites.ContentUrl
# $tsSites = Find-TSSite -ContentUrl $tsSyncedSitesContentUrl

$message = "<$tsServer <.>48> CONNECTING"
Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor DarkBlue, DarkGray
Connect-TableauServer -Server $tsServer
$message = "$($emptyString.PadLeft(11,"`b"))$($emptyString.PadLeft(11," "))$($emptyString.PadLeft(11,"`b")) CONNECTED"
Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen
Write-host+

$tsServerUsers = @()
$tsServerGroups = @()

$message = "<Sites <.>48> Users/Groups"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray, DarkGray, Gray

foreach ($tsSite in (Get-TSSites)) {

    Switch-TSSite -ContentUrl $tsSite.contentUrl

    $message = "<  $($tsSite.name) <.>48> PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor DarkGray

    $tsSiteUsers = Get-TSUsers
    $tsSiteUsers | Add-Member -NotePropertyName site -NotePropertyValue ($tsSite | Select-Object -Property id,name,contentUrl) -Force

    $tsSiteGroups = Get-TSGroups+
    $tsSiteGroups | Add-Member -NotePropertyName site -NotePropertyValue ($tsSite | Select-Object -Property id,name,contentUrl) -Force

    $message = "$($emptyString.PadLeft(8,"`b"))$($emptyString.PadLeft(8," "))$($emptyString.PadLeft(8,"`b")) $($tsSiteUsers.count)/$($tsSiteGroups.count)"
    Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

    $tsServerUsers += $tsSiteUsers
    $tsServerGroups += $tsSiteGroups

}

Write-Host+

$tsServerUsers = $tsServerUsers | Where-Object {$_.name -notin $global:tsRestApiConfig.SpecialAccounts}
$tsServerUsersName = $tsServerUsers.Name.Trim().ToLower() | Sort-Object -Unique
$message = "<Tableau Server Users <.>48> $($tsServerUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$tsServerUsersSiteRole = @()
$tsServerUsers.siteRole | 
    Group-Object | 
        Select-Object -Property Name, Count | Sort-Object -Property Count -Descending | 
            Foreach-Object {
                $tsServerUsersSiteRole += $_ | Select-Object -Property Name, Count
            }
for ($i = 0; $i -le $tsServerUsersSiteRole.count/5; $i++) {
    if ($i -gt 0) { Write-Host+ }
    $siteRoleRow = @()
    for ($j = $i*5; $j -le ($i+1)*5-1; $j++) {
        if ($j -lt $tsServerUsersSiteRole.count) {
            $siteRoleRow += "$($tsServerUsersSiteRole[$j].Name) ($($tsServerUsersSiteRole[$j].Count))"
        }
    }
    $message = "  $($siteRoleRow -join ", ")"
    if ($j -lt $tsServerUsersSiteRole.count) { $message += "," }
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
}
if ($j -lt $tsServerUsersSiteRole.count) { 
    Write-Host+ -NoTrace -NoTimestamp " ..." -ForegroundColor DarkGray
}
else {
    Write-Host+
}

$tsServerGroups = $tsServerGroups | Where-Object {$_.name -notin $global:tsRestApiConfig.SpecialGroups}
$message = "<Tableau Server Groups <.>48> $($tsServerGroups.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

# $tsServerUsersCount = "$($emptyString.PadLeft(4-$tsServerUsers.Count.ToString().Length," "))$($tsServerUsers.Count.ToString())"
# $tsServerGroupsCount = "$($emptyString.PadLeft(4-$tsServerGroups.Count.ToString().Length," "))$($tsServerGroups.Count.ToString())"
# $message = "<Total <.>48> $tsServerUsersCount users $tsServerGroupsCount groups"
# Write-Host+ -NoTrace -NoTimestamp -Parse $message

# $tsPathUsers = $tsServerUsers | Where-Object {($_.name -split "@")[1] -eq "path.org"}
# $tsPathUsersName = $tsPathUsers.name.Trim().ToLower() | Sort-Object -Unique

$tsPathGroups = $tsServerGroups | Where-Object {$_.site.contentUrl -in $tsSyncedSitesContentUrl -and $_.name -in ("All PATH Staff","NonStaff","All PATH Consultants")}
$message = "Tableau Server PATH groups"
Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor Gray,DarkGray,Gray

for ($i = 0; $i -le $tsPathGroups.count/5; $i++) {
    if ($i -gt 0) { Write-Host+ }
    $summaryRow = @()
    for ($j = $i*5; $j -le ($i+1)*5-1; $j++) {
        if ($j -lt $tsPathGroups.count) {
            $summaryRow += "$($tsPathGroups[$j].Name) ($($tsPathGroups[$j].membership.Count))"
        }
    }
    $message = "  $($summaryRow -join ", ")"
    if ($j -lt $tsPathGroups.count) { $message += "," }
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
}
if ($j -lt $tsPathGroups.count) { 
    Write-Host+ -NoTrace -NoTimestamp " ..." -ForegroundColor DarkGray
}
else {
    Write-Host+
}

$tsPathUsers = $tsPathGroups.membership #| Where-Object {$_.siteRole -ne "Unlicensed"}
$tsPathUsersName = $tsPathUsers.name.Trim().ToLower() | Sort-Object -Unique
$message = "<Tableau Server users (from PATH groups) <.>48> $($tsPathUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

Write-Host+

$azureADUsers,$cacheError = Get-AzureADUsers -Tenant pathseattle -AsArray
$azureADUsers = $azureADUsers | Where-Object {!$_."@removed"}
$azUsersName = $azureADUsers.userPrincipalName | Select-Object -Unique
$message = "<Azure AD users <.>48> $($azUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$azureADGroups, $cacheError = Get-AzureADGroups -tenant pathseattle -AsArray
$message = "<Azure AD groups <.>48> $($azureADGroups.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

# $azPathUsers = $azureADUsers | Where-Object {$_.onPremisesDistinguishedName -like "*OU=Users*"}
# $azPathUsersName = $azPathUsers.userPrincipalName.Trim().ToLower() | Sort-Object -Unique

$azPathGroups = $azureADGroups | Where-Object {$_.displayName -in ("All PATH Staff","NonStaff","All PATH Consultants")}
$message = "Azure AD PATH groups"
Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor Gray,DarkGray,Gray

$summaryRow = @()
foreach ($azPathGroup in $azPathGroups) {
    $summaryRow += "$($azPathGroup.displayName) ($($azPathGroup.members.Count))"
}
$message = "  $($summaryRow -join ", ")"
Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

$azPathUsers = $azureADUsers | Where-Object {$_.id -in $azPathGroups.members} # -and $_.accountEnabled}
$azPathUsersName = $azPathUsers.userPrincipalName.Trim().ToLower() | Sort-Object -Unique
$message = "<Azure AD users (from PATH groups) <.>48> $($azPathUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$azEnabledPathUsers = $azPathUsers | Where-Object {$_.userPrincipalName -in $azPathUsersName -and $_.accountEnabled}
$azDisabledPathUsers = $azPathUsers | Where-Object {$_.userPrincipalName -in $azPathUsersName -and !$_.accountEnabled}
$message = "  Enabled ($($azEnabledPathUsers.count)), Disabled ($($azDisabledPathUsers.count))"
Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGray

Write-Host+

$tsUnsyncedUsers = ($tsServerUsers | Where-Object {$_.name -notin $azUsersName})
$tsUnsyncedUsersName = $tsUnsyncedUsers.Name.Trim().ToLower() | Select-Object -Unique
$message = "<Tableau Server Unsynced users <.>48> $($tsUnsyncedUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$tsUnsyncedUsersDomain = @()
$tsUnsyncedUsersName | 
    Foreach-Object { ($_ -split "@")[1] } | Group-Object | 
        Select-Object -Property Name, Count | Sort-Object -Property Count -Descending | 
            Foreach-Object {
                $tsUnsyncedUsersDomain += $_ | Select-Object -Property Name, Count
            }
for ($i = 0; $i -le [math]::Min($tsUnsyncedUsersDomain.count/5,10); $i++) {
    if ($i -gt 0) { Write-Host+ }
    $domainRow = @()
    for ($j = $i*5; $j -le ($i+1)*5-1; $j++) {
        if ($j -lt $tsUnsyncedUsersDomain.count) {
            $domainRow += "$($tsUnsyncedUsersDomain[$j].Name) ($($tsUnsyncedUsersDomain[$j].Count))"
        }
    }
    $message = "  $($domainRow -join ", ")"
    if ($j -lt $tsUnsyncedUsersDomain.count) { $message += "," }
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
}
if ($j -lt $tsUnsyncedUsersDomain.count) { 
    Write-Host+ -NoTrace -NoTimestamp " ..." -ForegroundColor DarkGray
}
else {
    Write-Host+
}
Write-Host+

$tsSyncedPathUsersName = $null
$tsSyncedPathUsers = ($tsPathUsers | Where-object {$_.name -in $azPathUsersName})
if ($tsSyncedPathUsers) {
    $tsSyncedPathUsersName = $tsSyncedPathUsers.Name.Trim().ToLower() | Select-Object -Unique
}
$message = "<Tableau Server Synced PATH users <.>48> $($tsSyncedPathUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$tsUnsyncedPathUsersName = $null
$tsUnsyncedPathUsers = ($tsPathUsers | Where-object {$_.name -notin $azPathUsersName})
if ($tsUnsyncedPathUsers) {
    $tsUnsyncedPathUsersName = $tsUnsyncedPathUsers.Name.Trim().ToLower() | Select-Object -Unique
    $tsUnsyncedPathUsers | Add-Member -NotePropertyName groups -NotePropertyValue @() -Force
    foreach ($tsUnsyncedPathUser in $tsUnsyncedPathUsers) {
        $tsUnsyncedPathUser.groups = @()
        foreach ($tsServerGroup in $tsServerGroups) {
            if ($tsServerGroup.membership.id -contains $tsUnsyncedPathUser.id) {
                $tsUnsyncedPathUser.groups += [PSCustomObject]@{
                    id = $tsServerGroup.id
                    name = $tsServerGroup.name
                }
            }
        }
    }
}
$message = "<Tableau Server Unsynced PATH users <.>48> $($tsUnsyncedPathUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$azSyncedPathUsers = $azPathUsers | Where-Object {$_.accountEnabled -and $_.userPrincipalName.Trim().ToLower() -in $tsPathUsersName}
$azSyncedPathUsersName = $azSyncedPathUsers.userPrincipalName.Trim().ToLower() | Select-Object -Unique
$azSyncedPathUsers | Add-Member -NotePropertyName groups -NotePropertyValue @() -Force
$message = "<Azure AD Synced PATH users <.>48> $($azSyncedPathUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

$azUnsyncedUsersName = $null
$azUnsyncedUsers = $azPathUsers | Where-Object {$_.accountEnabled -and $_.userPrincipalName.Trim().ToLower() -notin $tsPathUsersName}
if ($azUnsyncedUsers) {
    $azUnsyncedUsersName = $azUnsyncedUsers.userPrincipalName.Trim().ToLower() | Select-Object -Unique
    $azUnsyncedUsers | Add-Member -NotePropertyName groups -NotePropertyValue @() -Force
    foreach ($azUnsyncedUser in $azUnsyncedUsers) {
        $azUnsyncedUser.groups = @()
        foreach ($azureADGroup in $azureADGroups) {
            if ($azureADGroup.displayName -in ("All PATH Staff","NonStaff")) {
                if ($azureADGroup.members -contains $azUnsyncedUser.id) {
                    $azUnsyncedUser.groups += [PSCustomObject]@{
                        id = $azureADGroup.id
                        displayName = $azureADGroup.displayName
                    }
                }
            }
        }
    }
}
$message = "<Azure AD Unsynced PATH users <.>48> $($azUnsyncedUsersName.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

Write-Host+

$syncStatus = $tsSyncedPathUsersName.count -eq $azSyncedPathUsersName.count -and $tsUnsyncedPathUsersName.Count -eq 0 -and $azUnsyncedPathUsersName.Count -eq 0 ? "SYNCED" : "UNSYNCED"
$message = "<Azure AD to Tableau Server Sync Status <.>48> $syncStatus"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($syncStatus -eq "SYNCED" ? "DarkGreen" : "DarkRed")

Write-Host+