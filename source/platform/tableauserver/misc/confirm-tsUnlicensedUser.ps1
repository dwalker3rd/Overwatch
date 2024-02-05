Write-Host+ -Clear
Connect-TableauServer -Server tableau.path.org -Site PathOperations
$tsUsers = Get-TSUsers
$tsLicensedUsers = $tsUsers | Where-object {$_.siterole -ne "Unlicensed" -and $_.name -notin $global:tsRestApiConfig.SpecialAccounts}
Set-CursorInvisible
foreach ($tsLicensedUser in $tsLicensedUsers) {
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $tsLicensedUser.email -ForegroundColor DarkGray
    $azureADUser = Find-AzureADUser -Tenant pathseattle -mail $tsLicensedUser.name
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($emptyString.PadLeft($tsLicensedUser.email.Length,"`b"))$($emptyString.PadLeft($tsLicensedUser.email.Length," "))$($emptyString.PadLeft($tsLicensedUser.email.Length,"`b"))"
    if ($null -ne $azureADUser -and !$azureADUser.accountEnabled) { 
        Write-Host+ -NoTrace -NoTimestamp "$($tsLicensedUser.email) | site role > Unlicensed" -ForegroundColor DarkRed
    }
}
Set-CursorVisible