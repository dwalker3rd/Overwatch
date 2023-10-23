function global:Import-TSGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ContentUrl
    )

    # get the AzureAD tenant key
    $tenantKey = Get-AzureTenantKeys -AzureAD

    # import the group membership CSV file
    # one of the following columns MUST be supplied
    # if supplied, the users's full name must be in a column labeled "FULLNAME"
    # if supplied, the users' email must be in a column labeled "EMAIL"
    $groupMembershipList = Import-Csv -Path $Path

    # match group membership list to azure AD users
    $_azureADUsers,$cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray
    $azureADUsers = @()
    foreach ($groupMember in $groupMembershipList) {
        foreach ($azureADUser in $_azureADUsers) {
            if ((![string]::IsNullOrEmpty($groupMember.email) -and $azureADUser.userPrincipalName -eq $groupMember.email) -or 
                ($azureADUser.displayName -like "$($groupMember.fullName)*")) {
                    if ($azureADUser.userPrincipalName -like "*@path.org") {
                        if ($azureADUser.accountEnabled) {
                            $azureADUsers += $azureADUser | Select-Object -Property displayName, userPrincipalName, accountEnabled
                            continue
                        }
                    }
            }
        }
    }

    # switch to specified tableau server site
    Switch-TSSite $ContentUrl
    $tsSite = Get-TSSite

    # get all tableau server users on this site
    $tsUsers = Get-TSUsers | 
        Select-Object -Property id, name, fullName, siteRole | 
            Where-Object {$_.name -in $azureADUsers.userPrincipalName} | 
                Sort-Object -Property fullName

    # find or create the specified group
    $tsGroup = Find-TSGroup -Name $Name
    if (!$tsGroup) {
        $tsGroup = New-TSGroup -Site $tssite -Name $Name
        Write-Host+ -NoTrace -NoTimeStamp "      NEW GROUP: $($tsSite.contentUrl)\$($tsGroup.name)" -ForegroundColor DarkGreen
    }
    else {
        Write-Host+ -NoTrace -NoTimeStamp "      PROFILE: $($tsSite.contentUrl)\$($tsGroup.name)" -ForegroundColor DarkGreen
    }

    # if found, get the current group membership and determine members to add
    $groupMembership = Get-TSGroupMembership -Group $tsGroup
    $groupMembersToAdd = $tsUsers | Where-Object {$_.name -notin $groupMembership.name}

    Write-Host+

    # add the tableau server use to the group
    foreach ($tsUser in $groupMembersToAdd) {
        $isNewGroupMember = $tsUser.name -in $groupMembersToAdd.name
        if ($isNewGroupMember) { Add-TSUserToGroup -Group $tsGroup -User $tsUser }
    }

    return

}