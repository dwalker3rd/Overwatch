Write-Host+ -Clear

$tsServer = "tableau.path.org"

$message = "<$tsServer <.>48> CONNECTING"
Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor DarkBlue, DarkGray
Connect-TableauServer -Server $tsServer
$message = "$($emptyString.PadLeft(11,"`b"))$($emptyString.PadLeft(11," "))$($emptyString.PadLeft(11,"`b")) CONNECTED"
Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen
Write-host+

Set-CursorInvisible

$tsServerUsers = @()
$tsServerGroups = @()

$message = "<Site Users/Groups <.>48> $($tsServerUsers.count)/$($tsServerGroups.count)"
Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor DarkGray
$messageLength = "$($tsServerUsers.count)/$($tsServerGroups.count)".Length + 1

foreach ($tsSite in (Get-TSSites)) {

    Switch-TSSite -ContentUrl $tsSite.contentUrl

    # $message = "<  $($tsSite.name) <.>48> PENDING"
    # Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor DarkGray

    $tsSiteUsers = Get-TSUsers
    $tsSiteUsers | Add-Member -NotePropertyName site -NotePropertyValue ($tsSite | Select-Object -Property id,name,contentUrl) -Force

    $tsSiteGroups = Get-TSGroups+
    $tsSiteGroups | Add-Member -NotePropertyName site -NotePropertyValue ($tsSite | Select-Object -Property id,name,contentUrl) -Force

    $message = "$($emptyString.PadLeft($messageLength,"`b"))$($emptyString.PadLeft($messageLength," "))$($emptyString.PadLeft($messageLength,"`b")) $($tsServerUsers.count)/$($tsServerGroups.count)"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray

    $messageLength = "$($tsServerUsers.count)/$($tsServerGroups.count)".Length + 1

    $tsServerUsers += $tsSiteUsers
    $tsServerGroups += $tsSiteGroups

}

Write-Host+

Set-CursorVisible

$tsServerUsers = $tsServerUsers | Where-Object {$_.name -notin $global:tsRestApiConfig.SpecialAccounts}
$tsServerUsersName = $tsServerUsers.Name.Trim().ToLower() | Sort-Object -Unique
$tsServerGroups = $tsServerGroups | Where-Object {$_.name -notin $global:tsRestApiConfig.SpecialGroups}
$message = "<Unique Server Users/Groups <.>48> $($tsServerUsersName.count)/$($tsServerGroups.count)"
Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,Gray

Write-Host+

$tableauCreators = Import-CSV -Path "$($global:Location.Data)\tableau\Tableau Creators.csv"
$tableauCreatorsNonPath = $tableauCreators | Where-Object {$_.domain -ne "path.org"}

$tableauCreatorsNonPath | Add-Member -NotePropertyName site -NotePropertyValue "" -Force
# $tableauCreatorsNonPath | Add-Member -NotePropertyName activateWithServer -NotePropertyValue $false -Force
foreach ($tableauCreatorNonPath in $tableauCreatorsNonPath) {
    $tsUser = [array](Find-TSUser -Name $tableauCreatorNonPath.email -Users $tsServerUsers)
    if ($tsUser) {
        $siteInfo = @()
        for ($i = 0; $i -lt $tsUser.site.Count; $i++) {
            $siteInfo += "$($tsUser[$i].site.name) ($($tsUser[$i].siteRole))"
        }
        $tableauCreatorNonPath.site = $siteInfo -join ", "
        # $tableauCreatorNonPath.activateWithServer = $true
    }
}
$tableauCreatorsNonPath | Select-Object -Property product_name,product_version,last_installed,period_end,expired,user_name,email,domain,site | Sort-Object -Property last_installed -Descending | Format-Table

# $tableauCreatorsNonPathWithSite = $tableauCreatorsNonPath | Where-Object {$_.site}
# $tableauCreatorsNonPathWithSite | Select-Object -Property product_name,product_version,last_installed,period_end,expired,user_name,email,domain,site | Sort-Object -Property last_installed -Descending | Format-Table

# $tableauCreatorsNonPathNoSite = $tableauCreatorsNonPath | Where-Object {!$_.site}
# $tableauCreatorsNonPathNoSite | Select-Object -Property product_name,product_version,last_installed,period_end,expired,user_name,email,domain | Sort-Object -Property last_installed -Descending | Format-Table