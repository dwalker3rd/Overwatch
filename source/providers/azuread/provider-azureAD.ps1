function global:Connect-AzureAD {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $appCredentials = Get-Credentials $global:Azure.$tenantKey.MsGraph.Credentials
    if (!$appCredentials) {
        throw "Unable to find the MSGraph credentials `"$($global:Azure.$tenantKey.MsGraph.Credentials)`""
    }

    #region HTTP

        $appId = $appCredentials.UserName
        $appSecret = $appCredentials.GetNetworkCredential().Password
        $scope = $global:Azure.$tenantKey.MsGraph.Scope
        $tenantDomain = $global:Azure.$tenantKey.Tenant.Domain

        $uri = "https://login.microsoftonline.com/$tenantDomain/oauth2/v2.0/token"

        # Add-Type -AssemblyName System.Web

        $body = @{
            client_id = $appId
            client_secret = $appSecret
            scope = $scope
            grant_type = 'client_credentials'
        }

        $restParams = @{
            ContentType = 'application/x-www-form-urlencoded'
            Method = 'POST'
            Body = $body
            Uri = $uri
        }

        # request token
        $response = Invoke-RestMethod @restParams

        #TODO: try/catch for expired secret with critical messaging
        
        # headers
        $global:Azure.$tenantKey.MsGraph.AccessToken = "$($response.token_type) $($response.access_token)"

    #endregion HTTP
    #region MGGRAPH
    
        Connect-MgGraph -NoWelcome -TenantId $global:Azure.$tenantKey.Tenant.Id -ClientSecretCredential $appCredentials

        $global:Azure.$tenantKey.MsGraph.Context = Get-MgContext

    #endregion MGGRAPH

    return

}
Set-Alias -Name Connect-MgGraph+ -Value Connect-AzureAD -Scope Global

function global:Invoke-AzureADRestMethod {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$params
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    if ([string]::IsNullOrEmpty($params.Headers.Authorization)) {
        Connect-AzureAD -tenant $tenantKey
        $params.Headers.Authorization = $global:Azure.$tenantKey.MsGraph.AccessToken
    }

    $retry = $false
    $response = @{ error = @{} }
    try {
        $response = Invoke-RestMethod @params
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        $response.error = ((get-error).ErrorDetails | ConvertFrom-Json).error
        if ($response.error.code -eq "InvalidAuthenticationToken") {
            Connect-AzureAD -tenant $tenantKey
            $params.Headers.Authorization = $global:Azure.$tenantKey.MsGraph.AccessToken
            $retry = $true
        }
    }
    if ($retry) {
        $response = @{ error = @{} }
        try {
            $response = Invoke-RestMethod @params
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            $response.error = ((get-error).ErrorDetails | ConvertFrom-Json).error
        }
    }

    return $response
    
}

function global:Get-AzureADGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$false)][string[]]$Properties,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "v1.0",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $AzureADB2C = $global:Azure.$($tenantKey).tenant.type -eq "Azure AD B2C"

    $queryParams = @{
        default = @{
            Users = @{
                property = @("id","userPrincipalName","displayName","mail","accountEnabled","proxyAddresses")
            }
        }
    }
    $queryParams += @{
        Users = @{
            property = $Properties ?? ($AzureADB2C ? @("id","userPrincipalName","userType","displayName","mail","accountEnabled","proxyAddresses","identities") : $queryParams.default.Users.property)
            select = ""
            # filter = $Filter
        }
        Groups = @{
            property = $Properties ?? @("id","displayName","groupTypes","securityEnabled","members")
            select = ""
            # filter = $Filter
        }
    }
    $queryParams.Users.select = "`$select=$($queryParams.Users.property -join ",")"
    $queryParams.Groups.select = "`$select=$($queryParams.Groups.property -join ",")"

    $uri = "https://graph.microsoft.com/$graphApiVersion/groups/$($Id)?$($queryParams.Groups.select)"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams 
    $azureADGroup = $filter ? $response.value : $response
    # $azureADGroup = $azureADGroup | Where-Object {((!$_.groupTypes -and $_.securityEnabled) -or ($_.groupTypes -eq "DynamicMembership"))}
    $azureADGroup | Add-Member -NotePropertyName members -NotePropertyValue @()

    $uri = "https://graph.microsoft.com/$graphApiVersion/groups/$Id/members?$($queryParams.Users.select)" 

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }   

    do {
        $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams 
        $azureADGroup.members += $response.value | Select-Object -ExcludeProperty "@odata.type"
        # $message = "$($response.value.count)/$($azureADGroup.Members.count)"
        # Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($emptyString.PadLeft($messageLength,"`b"))$($emptyString.PadLeft($messageLength," "))$($emptyString.PadLeft($messageLength,"`b"))$message"
        # $messageLength = $message.Length
        $restParams.Uri = $response."@odata.nextLink"
    } until (!$restParams.Uri)

    # Write-Host+

    return $azureADGroup
     
}

function global:Get-AzureADUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UPN","Id","UserId","Email","Mail")][string]$User,
        [Parameter(Mandatory=$false)][string[]]$Properties,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $isUserId = $User -match $global:RegexPattern.Guid
    $isGuestUserPrincipalName = $User -match $global:RegexPattern.Username.AzureAD -and $User -like "*#EXT#*"
    $isEmail = $User -match $global:RegexPattern.Mail
    $isMemberUserPrincipalName = $User -match $global:RegexPattern.Username.AzureAD

    $isValidUser = $isUserId -or $isEmail -or $isMemberUserPrincipalName -or $isGuestUserPrincipalName
    if (!$isValidUser) {
        if ($global:ErrorActionPreference -eq 'Continue') {
            throw "'$User' is not a valid object id, userPrincipalName or email address."
        }
        return
    }

    $filter = $isUserId ? "id eq '$User'" : $null
    $filter = $isEmail ? "mail eq '$User'" : $filter
    $filter += $isMemberUserPrincipalName ? "$($filter ? " or " : $null)userPrincipalName eq '$User'" : $null
    $filter = $isGuestUserPrincipalName ? "userPrincipalName eq '$($User.Replace("#","%23"))'" : $filter

    $uri = "https://graph.microsoft.com/$graphApiVersion/users" 
    $uri += $filter ? "?`$filter=$filter" : "/$User"
    $uri += ($Properties ? "&select=$($Properties -join ",")" : "")

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams 
    $azureADUser = $filter ? $response.value : $response

    # if $User can't be found in the mail or userPrincipalName properties, check the Identities collection
    if (!$azureADUser) {
        $filter = "identities/any(c:c/issuerAssignedId eq '$User' and c/issuer eq '$($global:Azure.$tenantKey.Tenant.Name)')"
        $restParams.Uri = "https://graph.microsoft.com/$graphApiVersion/users?`$filter=$filter"
        $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams # -Uri $uri -Method GET -Headers $headers
        $azureADUser = $response.value
        # $azureADB2CUserIdentity = $azureADUser.identities | where-object {$_.issuer -eq $global:Azure.$tenantKey.Tenant.Name -and $_.signInType -eq "emailAddress"}
        # $azureADUser | Add-Member -NotePropertyName issuer -NotePropertyValue $azureADB2CUserIdentity.issuer
        # $azureADUser | Add-Member -NotePropertyName issuerAssignedId -NotePropertyValue $azureADB2CUserIdentity.issuerAssignedId
    }

    return $azureADUser | Select-Object -Property $($View ? $AzureADView.User.$($View) : $AzureADView.User.Default)
     
}

function global:Remove-AzureADUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta"
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$graphApiVersion/users/$Id" 

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        Headers = $headers
        Method = 'DELETE'
        Uri = $uri
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams
    $response | Out-Null

    return
     
}

function global:Reset-AzureADUserPassword {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("UserPrincipalName","UserId")][string]$User,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    if ($User -notmatch $global:RegexPattern.Guid -and $User -notmatch $global:RegexPattern.Username.AzureAD) {
        throw "'$User' is not a valid AzureAD user id or userPrincipalName."
    }

    $getParams = @{
        Tenant = $tenantKey
        User = $User
    }

    $azureADUser = Get-AzureADUser @getParams 
    if (!$azureADUser) {
        throw "User '$User' not found in tenant $($global:Azure.$tenantKey.Tenant.Name)"
        return
    }

    #region RESET PASSWORD
        
        try {
            $response = Update-MgUserPassword -UserId $User.Id -NewPassword (New-RandomPassword) 
            $response | Out-Null
        }
        catch {
            $resetPasswordError = Get-Error
            $resetPasswordErrorMessage = (($resetPasswordError | ConvertFrom-Json).error.message | ConvertFrom-Json).error.message
            Write-Host+ $resetPasswordErrorMessage -ForegroundColor DarkRed
            return
        }

        #TODO: try/catch for expired secret with critical messaging

    #endregion RESET PASSWORD

    # $creds = Request-Credentials -UserName $azureADUser.UserPrincipalName -Password $newPassword
    # Set-Credentials -Id $azureADUser.UserPrincipalName -Credentials $creds

    return
     
}

function global:Get-AzureADUserProxyAddresses {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$User,
        [Parameter(Mandatory=$false)][ValidateSet("SMTP","X500")][string]$Type,
        [Parameter(Mandatory=$false)][Alias("Organization")][string]$Domain,
        [switch]$NoUPN

    )

    if (!$Type -and $Domain) {
        throw "`$Type must be specified with the -Domain switch"
    }

    $typeIdentifierRegex = switch ($Type) {
        default { "^$($Type):" }
        "" { "^" }
    }

    $proxyAddresses = @()
    foreach ($azureADUser in $User) {
        foreach ($azureADProxyAddress in $azureADUser.proxyAddresses) {
            if ($azureADProxyAddress -match $typeIdentifierRegex) {
                $addProxyAddress = $true
                $proxyAddress = $azureADProxyAddress -replace $typeIdentifierRegex,""
                if ($NoUPN -and $proxyAddress -eq $azureADUser.userPrincipalName) { $addProxyAddress = $false }
                if ($Domain) {
                    switch ($Type) {
                        "SMTP" { if ($proxyAddress -notmatch ("$Domain$")) { $addProxyAddress = $false } }
                        "X500" { if (!$proxyAddress -notmatch ("^/o=$Domain")) { $addProxyAddress = $false } }
                    }
                }
                if ($addProxyAddress) { $proxyAddresses += $proxyAddress }
            }
        }
    }

    return $proxyAddresses | Sort-Object

}

function global:Update-AzureADUserProperty {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][string]$Property,
        [Parameter(Mandatory=$true)][string]$Value,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$graphApiVersion/users/$($User.id)"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        Headers = $headers
        Method = 'PATCH'
        Uri = $uri
        body = "{
            `n    `"$Property`" : $Value
            `n}"
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams
    $response | Out-Null

    return

}

function global:Disable-AzureADUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    Update-AzureADUserProperty -Tenant $Tenant -User $User -Property accountEnabled -Value false

    return
}

function global:Enable-AzureADUser {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    Update-AzureADUserProperty -Tenant $Tenant -User $User -Property accountEnabled -Value true

    return
}

function global:Get-AzureADUser+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UserId")][string]$User,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    if ($User -notmatch $global:RegexPattern.Guid -and $User -notmatch $global:RegexPattern.Username.AzureAD) {
        if ($global:ErrorActionPreference -eq 'Continue') {
            throw "'$User' is not a valid object id, userPrincipalName or email address."
        }
        return
    }

    $getParams = @{
        Tenant = $tenantKey
        GraphApiVersion = $GraphApiVersion
        User = $User
    }

    $azureADUser = Get-AzureADUser @getParams 

    if ($azureADUser) {
        $azureADUserGroupMembership = Get-AzureADUserMembership -Tenant $tenantKey -AzureADUser $AzureADUser
        $azureADUser | Add-Member -NotePropertyName groupMembership -NotePropertyValue $azureADUserGroupMembership
        $azureADUser | Add-Member -NotePropertyName tenant -NotePropertyValue $global:Azure.$tenantKey.Tenant
    }

    $defaultView = ![string]::IsNullOrEmpty($azureADUser.issuer) ? $AzureADView.User.PlusWithIdentities : $AzureADView.User.Plus

    return $azureADUser | Select-Object -Property $($View ? $AzureADView.User.$($View) : $defaultView)

}

function global:IsMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UPN","Id","UserId","Email","Mail")][string]$User,
        [Parameter(Mandatory=$false)][Alias("GroupId","GroupDisplayName","GroupName")][string]$Group,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $getParams = @{
        Tenant = $tenantKey
        GraphApiVersion = $GraphApiVersion
        User = $User
    }

    $azureADUser = Get-AzureADUser @getParams 

    $isMemberOfGroup = $false
    if ($azureADUser) {
        $azureADUserGroupMembership = Get-AzureADUserMembership -Tenant $tenantKey -AzureADUser $AzureADUser
        $isMemberOfGroup = $azureADUserGroupMembership.id -contains $Group -or $azureADUserGroupMembership.displayName -contains $Group
    }

    return $isMemberOfGroup

}

function global:Get-AzureADUserMembership {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("User")][object]$AzureADUser,
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $azureADGroups, $cacheError = Get-AzureADGroups -Tenant $tenantKey -AsArray
    $azureADUserMembership = $azureADGroups | Where-Object {$_.members -contains $AzureADUser.id}

    return $azureADUserMembership | Select-Object -Property $($View ? $AzureADView.User.Membership.$($View) : $AzureADView.User.Membership.Default)

}

function global:New-AzureADGroupMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][string]$UserId,
        [Parameter(Mandatory=$false)][string]$GroupId,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}   

    $params = @{
        "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$UserId"
    }

    return New-MgBetaGroupMemberByRef -GroupId $groupId -BodyParameter $params

}

function global:Send-AzureADInvitation {

    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$DisplayName,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$($graphApiVersion)/invitations"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $body = @{
        invitedUserDisplayName = $DisplayName
        invitedUserEmailAddress = $Email
        invitedUserMessageInfo = @{
            messageLanguage = "en-US"
            customizedMessageBody = $Message
        }
        sendInvitationMessage = $true
        inviteRedirectUrl = "https://portal.azure.com" 
    } | ConvertTo-Json

    $restParams = @{
        Body = $body
        ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers
        Method = 'POST'
        Uri = $uri
    }

    if ($PSCmdlet.ShouldProcess($Email, "Send invitation")) {
        $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams # -Uri $uri -Method POST -Headers $headers -Body $body
        return $response
    }
    else {
        return
    }

}

function global:Update-AzureADUserEmail {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][Alias("Email")][string]$Mail,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    $mailOriginal = $User.mail ?? "None"
    $originalMailIdentities = $user.identities | Where-Object {$_.signInType -eq "emailAddress"}
    $mailIdentitiesJson = ($user.identities | ConvertTo-Json).Replace($mailOriginal,$mail)

    # User has multiple identities in the source AD domain
    # No current rules dictate which should be used
    # Throw an error so this can be addressed
    if ($originalMailIdentities.Count -gt 1) {
        throw "User $($User.userPrincipalName) has multiple identities with multiple email addresses."
        return $User
    }

    # User has a null property from the source AD domain
    if ($originalMailIdentities.Count -eq 0) {
        return $User
    }

    # Update user in Azure AD B2C

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$graphApiVersion/users/$($User.id)"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        Headers = $headers
        Method = 'PATCH'
        Uri = $uri
        body = "{`"mail`" : `"$mail`", `"identities`" : $mailIdentitiesJson}"
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams

    $status = $null
    $message = $null
    if ($response.error) { 
        $status = "Failure"
        $entryType = "Error"
        if ($response.error.details.code -contains "ObjectConflict") {
            $status = "ProxyAddressConflict"
            $message = ($response.error.details | Where-Object {$_.code -eq "ObjectConflict"}).message
            $entryType = "Warning"
        }
    }
    else {
        $response = Get-AzureADUser -Tenant $tenantKey -User $User.id
        $status = $response.mail -eq $mail ? "Success" : "Failure"
        $message = "$mailOriginal > $($response.mail)"
        $entryType = $status -eq "Success" ? "Information" : "Error"
    }
    Write-Log -Action "UpdateAzureADUserEmail" -Target "$tenantKey\Users\$($User.id)" -Message $message -Status $status -EntryType $entryType -Force

    return $response

}

function global:Update-AzureADUserNames{

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$false)][Alias("FirstName")][string]$GivenName,
        [Parameter(Mandatory=$false)][Alias("LastName","FamilyName")][string]$SurName,
        [Parameter(Mandatory=$false)][string]$DisplayName,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    # if ([string]::IsNullOrEmpty($GivenName) -and
    #     [string]::IsNullOrEmpty($GivenName) -and
    #     [string]::IsNullOrEmpty($GivenName)) {
    #         Write-Host+ -NoTimestamp -NoTrace -NoSeparator "No names were specified." -ForegroundColor DarkYellow
    #         return $User
    #     }

    $givenNameOriginal = $User.givenName ?? "None"
    $surNameOriginal = $User.surName ?? "None"
    $displayNameOriginal = $User.displayName ?? "None"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$graphApiVersion/users/$($User.id)"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $body = @{}
    if (![string]::IsNullOrEmpty($GivenName)) { $body += @{ givenName = $givenName } }
    if (![string]::IsNullOrEmpty($surName)) { $body += @{ surName = $surName } }
    if (![string]::IsNullOrEmpty($displayName)) { $body += @{ displayName = $displayName } }
    $body = $body | ConvertTo-Json

    $restParams = @{
        Headers = $headers
        Method = 'PATCH'
        Uri = $uri
        body = $body
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams

    $status = $null
    $message = $null
    if ($response.error) { 
        $status = "Failure"
        $entryType = "Error"
    }
    else {
        $response = Get-AzureADUser -Tenant $tenantKey -User $User.id
        $givenNameMatch = ![string]::IsNullOrEmpty($GivenName) ? $response.givenName -eq $GivenName : $true
        $surNameMatch = ![string]::IsNullOrEmpty($SurName) ? $response.surName -eq $SurName : $true
        $displayNameMatch = ![string]::IsNullOrEmpty($DisplayName) ? $response.displayName -eq $DisplayName : $true
        $status = $givenNameMatch -and $surNameMatch -and $displayNameMatch ? "Success" : "Failure"
        $messageBits = @()
        if (![string]::IsNullOrEmpty($GivenName)) { $messageBits +=  "$givenNameOriginal > $($response.givenName)"}
        if (![string]::IsNullOrEmpty($SurName)) { $messageBits +=  "$surNameOriginal > $($response.surName)"}
        if (![string]::IsNullOrEmpty($DisplayName)) { $messageBits +=  "$displayNameOriginal > $($response.displayName)"}
        $message = $messageBits -join ", "
        $entryType = $status -eq "Success" ? "Information" : "Error"
    }
    Write-Log -Action "AzureADUserNames" -Target "$tenantKey\Users\$($User.id)" -Message $message -Status $status -EntryType $entryType -Force

    return $response

}

function global:Get-AzureADObjects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string[]]$Property,
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Delta,
        [switch]$NoCache,
        [switch]$Quiet
    )

    if ($NoCache) {$Delta = $false}

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $AzureADB2C = $global:Azure.$($tenantKey).tenant.type -eq "Azure AD B2C"
    if ($AzureADB2C -and $Delta) {$Delta = $false} # Delta switch not valid for Azure AD B2C tenants

    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)
    $typeLowerCase = $Type.ToLower()
    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)

    $azureADObjects = @{}
    $Delta = $Id ? $false : $Delta

    $queryParams = @{
        default = @{
            Users = @{
                property = @("id","userPrincipalName","displayName","mail","accountEnabled","proxyAddresses")
            }
        }
    }
    $queryParams += @{
        Users = @{
            property = $Property ?? ($AzureADB2C ? @("id","userPrincipalName","userType","displayName","mail","accountEnabled","proxyAddresses","identities") : $queryParams.default.Users.property)
            select = ""
            # filter = $Filter
        }
        Groups = @{
            property = $Property ?? @("id","displayName","groupTypes","securityEnabled","members")
            select = ""
            # filter = $Filter
        }
    }
    $queryParams.Users.select = "`$select=$($queryParams.Users.property -join ",")"
    $queryParams.Groups.select = "`$select=$($queryParams.Groups.property -join ",")"

    #region DELTALINK

        if ($Delta) {
            $deltaLink = Get-DeltaLink -Tenant $tenantKey -Type $Type -Quiet:$Quiet.IsPresent
            if (!$deltaLink) {
                $Delta = $false
            }
        }

    #endregion DELTALINK
    #region AZUREADOBJECTS CACHE

        if ($Delta) {

            $azureADObjects,$cacheError = Read-AzureADCache -Tenant $tenantKey -Type $Type
            if (!$azureADObjects) {

                # cache is empty, clear delta flag to get all/full data
                $Delta = $false

                # azureADObjects is empty, but it may be an empty string (hack in Read-AzureADCache)
                # reinit azureADObjects to be an empty hashtable
                $azureADObjects = @{}

            }

        }

    #endregion AZUREADOBJECTS CACHE
    #region AZUREADOBJECTS UPDATES
        
        Set-CursorInvisible
            
        $message = "$($Delta ? "Processing" : "Getting") $typeLowerCaseSingular updates"
        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoNewLine -NoSeparator $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray # -Prefix "`r"
    
        $uri = $Delta ?  $deltaLink : "https://graph.microsoft.com/$($graphApiVersion)/$typeLowerCase$($Filter ? $null : "/delta")?$($queryParams.$Type.select)$($Filter ? "`&$Filter" : $null)"

        if ($AzureADB2C) {
            $uri = $uri.Replace("/delta","")
        }

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type", "application/json")
        $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

        $restParams = @{
            ContentType = 'application/x-www-form-urlencoded'
            Headers = $headers
            Method = 'GET'
            Uri = $uri
        }

        $emptyString = ""
        $updateCount = 0
        $totalCount = 0
        $updateCountLength = 0
        $totalCountLength = 0

        do {
            $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams # -Uri $uri -Headers $headers -Method Get -ContentType "application/json"
            $totalCount += $response.value.Count

            foreach ($value in $response.value) {

                $azureADObject = $value | Select-Object -Property *,@{Name="timestamp"; Expression={Get-Date}}

                if ($azureADObject.'@removed') {
                    if ($azureADObjects.($azureADObject.id)) {
                        $azureADObjects.remove($azureADObject.id)
                    }
                }
                else {

                    switch ($Type) {

                        "Users" {

                            if ($azureADObjects.($azureADObject.id)) {
                                $azureADObjects.($azureADObject.id) = $azureADObject
                            }
                            else {
                                $azureADObjects += @{$azureADObject.id = $azureADObject}
                            }

                            $updateCount += 1

                        }
                        "Groups" {

                            if ((!$azureADObject.groupTypes -and $azureADObject.securityEnabled) -or 
                                ($azureADObject.groupTypes -eq "DynamicMembership")) {   #} -and $azureADObject.displayName -notin $global:Azure.SpecialGroups)) {

                                $newAzureADObject = @{
                                    id = $azureADObject.id
                                    displayName = $azureADObject.displayName
                                    groupTypes = $azureADObject.groupTypes
                                    securityEnabled = $azureADObject.securityEnabled
                                    timestamp = $azureADObject.timestamp
                                    # nestedGroups = @()
                                    # membersDelta = @()
                                    # membersToRemove = @()
                                    # membersToAdd = @()
                                    members = New-Object System.Collections.ArrayList
                                }
                                # $nestedGroups = [array]($azureADObject."members@delta" | Where-Object {$_."@odata.type" -eq "#microsoft.graph.group"})
                                $membersDelta = [array]($azureADObject."members@delta" | Where-Object {$_."@odata.type" -eq "#microsoft.graph.user"})
                                $membersToRemove = [array](($membersDelta | Where-Object {$_."@removed"}).id)
                                $membersToAdd = [array](($membersDelta | Where-Object {!$_."@removed"}).id)

                                if (!$azureADObjects.($azureADObject.id)) {
                                    $newAzureADObject.members = $membersToAdd
                                    $azureADObjects += @{$azureADObject.id = $newAzureADObject}
                                }
                                else {
                                    $updatedMembers = New-Object System.Collections.ArrayList
                                    foreach ($member in $azureADObjects.($azureADObject.id).members) {
                                        $updatedMembers.Add($member) | Out-Null
                                    }
                                    foreach ($member in $membersToAdd) {
                                        $updatedMembers.Add($member) | Out-Null
                                    }
                                    foreach ($member in $membersToRemove) {
                                        $updatedMembers.Remove($member) | Out-Null
                                    }

                                    # deltas can both add and update a user, so remove dupes
                                    $azureADObjects.($azureADObject.id).members = $updatedMembers | Sort-Object -Unique
                                    
                                    # if ($nestedGroups) {$azureADObjects.($azureADObject.id).nestedGroups += $nestedGroups}
                                    # if ($membersDelta) {$azureADObjects.($azureADObject.id).membersDelta += $membersDelta}
                                    # if ($membersToRemove) {$azureADObjects.($azureADObject.id).membersToRemove += $membersToRemove}
                                    # if ($membersToAdd) {$azureADObjects.($azureADObject.id).membersToAdd += $membersToAdd}

                                    $azureADObjects.($azureADObject.id).timestamp = (Get-Date)
                                }

                                $updateCount += 1

                            }
                        }
                    }
                }

            }

            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoNewLine " $($emptyString.PadLeft($updateCountLength + $totalCountLength,"`b"))$($updateCount)/$($totalCount)" -ForegroundColor DarkGreen
            $updateCountLength = $updateCount.ToString().Length + 1
            $totalCountLength = $totalCount.ToString().Length + 1

            $restParams.Uri = $response."@odata.nextLink"

        } until ($Delta ? $response."@odata.deltaLink" : !$restParams.Uri)

        $deltaLink = $response."@odata.deltalink" ? $response."@odata.deltaLink" : $null

        Write-Host+ -Iff $(!$Quiet)

        Set-CursorVisible

        if (!$NoCache -or $AzureADB2C) {

            $message = "Writing $tenantKey $typeLowerCase to cache "
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoSeparator -NoNewLine $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray

            $azureADObjects | Write-AzureADCache -Tenant $tenantKey -Type $Type
            
            $message = " SUCCESS"
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen

        }
        
    #endregion AZUREADOBJECTS UPDATES
    #region DELTALINKS UPDATES

        if (!$NoCache -and !$AzureADB2C) {
            
            if (!$Delta) {
                $uri = "https://graph.microsoft.com/$($graphApiVersion)/$typeLowerCase/delta?$($queryParams.$Type.select)&`$deltaToken=latest"
                $restParams.Uri = $uri
                $response = Invoke-RestMethod @restParams # -Uri $uri -Headers $headers -Method Get -ContentType "application/json"
                $deltaLink = $response."@odata.deltaLink"
            }

            Set-DeltaLink -Tenant $tenantKey -Type $Type -Value $deltaLink -Quiet:$Quiet.IsPresent

        }

    #region DELTALINKS UPDATES

    Write-Host+ -Iff $(!$Quiet)

    return ($NoCache ? $AzureADObjects : $null)

}

function global:Update-AzureADObjects {

    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type,
        [Parameter(Mandatory=$false)][string]$CacheProductID = "AzureADCache",
        [Parameter(Mandatory=$false)][int]$Timeout = 60,
        [switch]$Delta,
        [switch]$Quiet
    )

    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}   
    
    Set-CursorInvisible

    $message = "<Updating $typeLowerCaseSingular cache <.>49> PENDING"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray, DarkGray, DarkGray   

    $platformTask = Get-PlatformTask -Id $CacheProductID
    $platformTaskStatusLength = $platformTask.Status.Length

    $message = "<$CacheProductID platform task <.>49> $($platformTask.Status.ToUpper())"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray, DarkGray, $($platformTask.Status -eq "Ready" ? "DarkGreen" : "DarkYellow")

    # if ($platformTask.Status -eq "Running") {
    
        $prevPlatformTaskStatusLength = $platformTaskStatusLength

        $platformTask = Disable-PlatformTask -Id $CacheProductID -OutputType PlatformTask -Timeout (New-TimeSpan -Seconds $Timeout) 
        $platformTaskStatusLength = $platformTask.Status.Length

        if ($platformTask.Status -eq "Running") {
            $message = "<$($MyInvocation.MyCommand) <.>49> FAILED"
            Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray, DarkGray, DarkRed
            Set-CursorVisible
            return
        }        
    
        $padStatus = $prevPlatformTaskStatusLength - $platformTaskStatusLength + 1
        $padStatus = $padStatus -gt 0 ? $padStatus : 0  
        Write-Host+ -Iff $(!$Quiet) -NoTimestamp -NoTrace -NoNewLine "`e[$($prevPlatformTaskStatusLength)D$($emptyString.PadLeft($padStatus," "))" 
        Write-Host+ -Iff $(!$Quiet) -NoTimestamp -NoTrace -NoNewLine "$($platformTask.Status.ToUpper())" -ForegroundColor $($platformTask.Status -eq "Ready" ? "DarkGreen" : "DarkRed")

    # }

    # $message = "<Azure AD $Type <.>49> PENDING"
    # Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray, DarkGray, DarkGray 

    Get-AzureADObjects -Tenant $tenantKey -Type $Type -Delta:$Delta.IsPresent -Quiet
 
    # Write-Host+ -NoTimestamp -NoTrace -NoNewLine "`e[7D$($emptyString.PadLeft(7," "))`e[7D" 
    # Write-Host+ -NoTimestamp -NoTrace "SUCCESS" -ForegroundColor DarkGreen

    $prevPlatformTaskStatusLength = $platformTaskStatusLength
    
    $platformTaskStatus = Enable-PlatformTask -Id $CacheProductID -OutputType "PlatformTask.Status"
    $platformTaskStatusLength = $platformTaskStatus.Length

    Write-Host+ -Iff $(!$Quiet) -NoTimestamp -NoTrace -NoNewLine "`e[$($prevPlatformTaskStatusLength)D$($emptyString.PadLeft($prevPlatformTaskStatusLength," "))`e[$($prevPlatformTaskStatusLength)D" 
    Write-Host+ -Iff $(!$Quiet) -NoTimestamp -NoTrace "$($platformTaskStatus.ToUpper())" -ForegroundColor $($platformTaskStatus -eq "Ready" ? "DarkGreen" : "DarkRed")    

    $message = "<Updating $typeLowerCaseSingular cache <.>49> SUCCESS"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray, DarkGray, DarkGreen  

    Set-CursorVisible
    
    return

}

function global:Export-AzureADObjects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type
    )
    
    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    # $AzureADB2C = $global:Azure.$($tenantKey).tenant.type -eq "Azure AD B2C"

    $typeLowerCase = $Type.ToLower()
    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)

    $action = "Initialize"; $target = "AzureAD\$tenantKey"
    try {

        $action = "Export"; $target = "AzureAD\$tenantKey\$Type"
        $message = "<Exporting $typeLowerCase cache <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        switch ($Type) {
            "Users" {
                $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray

                switch ($global:Azure.$tenantKey.tenant.type) {
                    "default" {
                        $azureADUsers | Sort-Object -property userPrincipalName | 
                            Select-Object -property @{name="User Id";expression={$_.id}},@{name="User Principal Name";expression={$_.userPrincipalName}},@{name="User Display Name";expression={$_.displayName}},@{name="User Mail";expression={$_.mail}},@{name="User Account Enabled";expression={$_.accountEnabled}},timestamp | 
                                Export-Csv  "$($global:Azure.Location.Data)\$tenantKey-users.csv"
                    }
                    "Azure AD B2C" {
                        $azureADUsers | Sort-Object -property userPrincipalName | 
                            Select-Object -property @{name="User Id";expression={$_.id}},@{name="User Principal Name";expression={$_.userPrincipalName}},@{name="User Display Name";expression={$_.displayName}},@{name="User Mail";expression={($_.identities | where-object {$_.signInType -eq "emailAddress"}).issuerAssignedId}},@{name="User Account Enabled";expression={$_.accountEnabled}},timestamp | 
                                Export-Csv  "$($global:Azure.Location.Data)\$tenantKey-users.csv"
                    }
                }

                $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

                Write-Host+
                Copy-Files -Path "$($global:Azure.Location.Data)\$tenantKey-$typeLowerCase.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
                Write-Host+

            }
            "Groups" {
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
        }
    }
    catch {

        Write-Log -Action $action -Target $target -Exception $_.Exception
        Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkRed

    }
    finally {}
}

function global:Get-DeltaLink {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type,
        [switch]$Quiet
    )

    $deltaLinks = @{
        Groups = $null
        Users = $null
    }

    $tenantLowerCase = $Tenant.ToLower()
    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)
    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)

    $cache = "$($tenantLowerCase)-deltaLinks"

    $message = "Reading $typeLowerCaseSingular delta link "
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoSeparator -NoNewLine $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray

    if ((Get-Cache $cache).Exists) {
        $deltaLinks = read-cache $cache
    }
    if (!$deltaLinks.$Type) {
        $message = " FAILED"
        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp $message -ForegroundColor DarkRed
    }
    else {
        $message = " SUCCESS"
        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen
    }

    return $deltaLinks.$Type

}
    
function global:Set-DeltaLink {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Groups","Users")][string]$Type,
        [Parameter(Mandatory=$true,Position=1)][string]$Value,
        [switch]$AllowNull,
        [switch]$Quiet
    )

    $tenantLowerCase = $Tenant.ToLower()
    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)
    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)

    $cache = "$($tenantLowerCase)-deltaLinks"

    if (!$Value -and !$AllowNull) {throw "AllowNull must be specified when Value is null"}

    $deltaLinks = @{
        Groups = Get-DeltaLink -Tenant $Tenant -Type Groups -Quiet:$Quiet.IsPresent
        Users = Get-DeltaLink -Tenant $Tenant -Type Users -Quiet:$Quiet.IsPresent
    }
    $deltaLinks.$Type = $Value

    $message = "Writing $typeLowerCaseSingular delta link "
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoSeparator -NoNewLine $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray

    $deltaLinks | Write-Cache $cache

    $message = " SUCCESS"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen

    return

}

function global:Read-AzureADCache {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Groups","Users")][string]$Type,
        [Parameter(Mandatory=$false)][Alias("Since")][DateTime]$After,
        [switch]$AsArray
    )

    $tenantLowerCase = $Tenant.ToLower()
    $typeLowerCase = $Type.ToLower()
    $typeUpperCase = $Type.ToUpper()

    $cache = "$($tenantLowerCase)-$($typeLowerCase)"
    $cacheError = $null

    # $retryDelay = New-Timespan -Seconds 5
    # $retryMaxAttempts = 3
    # $retryAttempts = 0

    $filteredObject = @{}
    if ($(Get-Cache $cache).Exists) {

        do {
            try {
                # if ($retryAttempts -gt $retryMaxAttempts) {
                #     throw $Error[0]
                # }
                # $retryAttempts++
                $azureADObject = Read-Cache $cache 
            }
            # catch [System.Xml.XmlException] {
            #     $errorMessage = $_.Exception.Message
            #     Write-Log -Action "ReadCache" -Target $cache -Status "Error" -Message $errorMessage -EntryType "Error" -Force
            #     Write-Log -Action "ReadCache" -Target $cache -Status "Error" -Message "Attempt #$($retryAttempts): ERROR" -Data $retryAttempts -EntryType "Error" -Force
            #     Start-Sleep -Milliseconds $retryDelay.TotalMilliseconds
            # }
            catch {
                Write-Log -Action "ReadCache" -Target $cache -Exception $_.Exception
                throw $Error[0]
            }
        } while (!$azureADObject)

        # if ($retryAttempts -gt 1) {
        #     Write-Log -Action "ReadCache" -Target $cache -Status "Success" -Message "Attempt #$($retryAttempts): SUCCESS" -Data $retryAttempts -Force
        # }

        if ($After) {
            $filteredObject = $azureADObject.GetEnumerator() | Where-Object {($_.Value).timestamp -gt $After}
            $azureADObject = @{}
            $filteredObject | ForEach-Object {$azureADObject.Add($_.Key, $_.Value)}
        }

    }
    else {
        $cacheError = @{code = "CACHE.NOTFOUND"; summary = "Cache $cache was not found."; target = $cache; traceback = $MyInvocation.MyCommand; }
        return $null, $cacheError
    }

    if (!$azureADObject -and !$After) {
        $cacheError = @{code = "NO$typeUpperCase"; summary = "Results contain no $typeLowerCase"; target = $cache; traceback = $MyInvocation.MyCommand; }
    }
    # else {
    #     $message = " $($azureADObject.Count)"
    #     Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen
    # }

    # returning multiple values from function
    # if azureADObject is empty/null, then cache error is returned in the first instead of second slot
    # if azureADObject is empty/null, stuff something in it to keep the cache error in the second slot
    if (!$azureADObject) {
        $azureADObject = $emptyString
        $AsArray = $false
    }
    return ($AsArray ? ($azureADObject.values | Select-Object -Property *) : $azureADObject), $cacheError

}

function global:Write-AzureADCache {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][Object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Groups","Users")][string]$Type
    )

    begin{
        $tenantLowerCase = $Tenant.ToLower()
        $typeLowerCase = $Type.ToLower()
        $cache = "$($tenantLowerCase)-$($typeLowerCase)"
        $outputObject = @()
    }
    process{
        $outputObject += $InputObject
    }
    end{
        $outputObject | Write-Cache $cache
    }

}

function global:Get-AzureADGroups {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("Since")][DateTime]$After,
        [switch]$AsArray
    )

    $cacheParams = @{
        Tenant = $Tenant
        Type = "Groups"
    }
    if ($After) {$cacheParams += @{After = $After}}
    if ($AsArray) {$cacheParams += @{AsArray = $AsArray}}

    $azureADGroups,$cacheError = Read-AzureADCache @cacheParams

    if ($cacheError) {
        Write-Log -Action "GetAzureADGroups" -Target "$($cacheParams.Tenant)\$($cacheParams.Type)" -Status $cacheError.code -Message $cacheError.Summary -EntryType "Error"
    }

    return $azureADGroups, $cacheError

}

function global:Get-AzureADUsers {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("Since")][DateTime]$After,
        [switch]$AsArray
    )

    $cacheParams = @{
        Tenant = $Tenant
        Type = "Users"
    }
    if ($After) {$cacheParams += @{After = $After}}
    if ($AsArray) {$cacheParams += @{AsArray = $AsArray}}

    $azureADUsers,$cacheError = Read-AzureADCache @cacheParams

    if ($cacheError) {
        Write-Log -Action "GetAzureADUsers" -Target "$($cacheParams.Tenant)\$($cacheParams.Type)" -Status $cacheError.code -Message $cacheError.Summary -EntryType "Error"
    }

    return $azureADUsers, $cacheError

}

function global:Find-AzureADObject {

    param(

        [Parameter(Mandatory=$false,ParameterSetName="ById")]
        [Parameter(Mandatory=$false,ParameterSetName="ByUserPrincipalName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByDisplayName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByMail")]
        [string]
        $Tenant,

        [Parameter(Mandatory=$true,ParameterSetName="ById")]
        [Parameter(Mandatory=$true,ParameterSetName="ByUserPrincipalName")]
        [Parameter(Mandatory=$true,ParameterSetName="ByDisplayName")]
        [Parameter(Mandatory=$true,ParameterSetName="ByMail")]
        [ValidateSet("Group","User")]
        [string]
        $Type,

        [Parameter(Mandatory=$false,ParameterSetName="ById")]
        [Parameter(Mandatory=$false,ParameterSetName="ByUserPrincipalName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByDisplayName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByMail")]
        [Alias("Groups","Users")]
        [object[]]
        $InputObject,

        [Parameter(Mandatory=$true,ParameterSetName="ById")]
        [string]
        $Id,

        [Parameter(Mandatory=$true,ParameterSetName="ByUserPrincipalName")]
        [string]
        $UserPrincipalName,

        [Parameter(Mandatory=$true,ParameterSetName="ByDisplayName")]
        [string]
        $DisplayName,

        [Parameter(Mandatory=$true,ParameterSetName="ByMail")]
        [string]
        $Mail,

        [Parameter(Mandatory=$false,ParameterSetName="ById")]
        [Parameter(Mandatory=$false,ParameterSetName="ByUserPrincipalName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByDisplayName")]
        [Parameter(Mandatory=$false,ParameterSetName="ByMail")]
        [string]
        $Operator="eq"
    )

    $obj = "$($Type.ToLower())s"
    
    if (!(Invoke-Expression "`$$obj")) {

        if (!$Tenant) {
            throw "Tenant is required when $obj object is not supplied."
        }
        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}
        
        $InputObject, $cacheError = Invoke-Expression "Get-AzureAD$($obj) -Tenant $tenantKey -AsArray"
        if (!$InputObject) {
            throw "Missing $Types object"
        }
    
    }
    
    if ($Id) {$where = "{`$_.id -$Operator `$Id}"}
    if ($UserPrincipalName) {$where = "{`$_.userPrincipalName -$Operator `$UserPrincipalName}"}
    if ($DisplayName) {$where = "{`$_.displayName -$Operator `$DisplayName}"}
    if ($Mail) {
        # search both the mail property and the issuerAssignedId identity where signInType is emailAddress
        $where = "{`$_.mail -$Operator `$Mail -or (`$_.identities | Where-Object {`$_.signInType -eq 'emailAddress'}).issuerAssignedId -$Operator `$Mail}"
    }

    $search = "`$InputObject | Where-Object $where"
    
    $result = Invoke-Expression $search

    return $result
}    

function global:Find-AzureADUser {
    param(
        [Parameter(Mandatory=$false)][string]$Tenant,
        [Parameter(Mandatory=$false)][object]$Users,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$UserPrincipalName,
        [Parameter(Mandatory=$false)][string]$DisplayName,
        [Parameter(Mandatory=$false)][string]$Mail,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )

    if (!$Users) {
        
        if (!$Tenant) {
            throw "Tenant is required when Users object is not supplied."
        }
        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

        $Users, $cacheError = Get-AzureADUsers -Tenant $Tenant -AsArray

    }

    $findParams = @{Operator = $Operator}
    if ($Id) {$findParams += @{Id = $Id}}
    if ($UserPrincipalName) {$findParams += @{UserPrincipalName = $UserPrincipalName}}
    if ($DisplayName) {$findParams += @{DisplayName = $DisplayName}}
    if ($Mail) {$findParams += @{Mail = $Mail}}

    return Find-AzureADObject -Tenant $tenantKey -Type "User" -Users $Users @findParams

}

function global:Find-AzureADGroup {
    param(
        [Parameter(Mandatory=$false)][string]$Tenant,
        [Parameter(Mandatory=$false)][object]$Groups,
        [Parameter(Mandatory=$false)][string]$Id,
        [Parameter(Mandatory=$false)][string]$DisplayName,
        [Parameter(Mandatory=$false)][string]$Operator="eq"
    )

    if (!$Groups) {

        if (!$Tenant) {
            throw "Tenant is required when Groups object is not supplied."
        }
        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

        $Groups, $cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray

    }
    
    $findParams = @{Operator = $Operator}
    if ($Id) {$findParams += @{Id = $Id}}
    if ($DisplayName) {$findParams += @{DisplayName = $DisplayName}}
    
    return Find-AzureADObject -Tenant $tenantKey -Type "Group" -Groups $Groups @findParams

}

function global:Get-AzureADApplication {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][string]$AppId,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$graphApiVersion/applications(appId='{$AppId}')" 

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams 

    return $response

}