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

function global:Get-AzureADApplication {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][string]$ApplicationId,
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $response = Get-MgApplication -Filter "AppId eq '$ApplicationId'"

    return $response

}

function global:Get-AzureADGroup {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$Id,
        # [Parameter(Mandatory=$false)][string[]]$Properties,
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $azureADGroup = Get-MgGroup -GroupId $Id
    $azureADGroup.members = Get-MgGroupMemberAsUser -GroupId $Id -All -ConsistencyLevel Eventual -CountVariable memberCount

    return $azureADGroup
     
}

function global:Get-AzureADUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UPN","Id","UserId","Email","Mail")][string]$User,
        # [Parameter(Mandatory=$false)][string[]]$Properties,
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

    $azureADUser = Get-MgUser -Filter $filter

    return $azureADUser | Select-Object -Property $($View ? $AzureADView.User.$($View) : $AzureADView.User.Default)
     
}

function global:Remove-AzureADUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$Id
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $response = Remove-MgUser -UserId $Id
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
        [Parameter(Mandatory=$true)][string]$Value
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $params = @{
        $Property = $Value
    }

    return = Update-MgUser -UserId $User.Id @params

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
        # [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
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
        User = $User
    }

    $azureADUser = Get-AzureADUser @getParams 

    if ($azureADUser) {
        $azureADUserGroupMembership = Get-AzureADUserMembership -Tenant $tenantKey -User $AzureADUser
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
        [Parameter(Mandatory=$false)][Alias("GroupId","GroupDisplayName","GroupName")][string]$Group
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $getParams = @{
        Tenant = $tenantKey
        User = $User
    }

    $azureADUser = Get-AzureADUser @getParams 

    $isMemberOfGroup = $false
    if ($azureADUser) {
        $azureADUserGroupMembership = Get-AzureADUserMembership -Tenant $tenantKey -User $AzureADUser
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

    $params = @{
        invitedUserDisplayName = $DisplayName
        invitedUserEmailAddress = $Email
        invitedUserMessageInfo = @{
            messageLanguage = "en-US"
            customizedMessageBody = $Message
        }
        sendInvitationMessage = $true
        inviteRedirectUrl = "https://portal.azure.com" 
    }

    if ($PSCmdlet.ShouldProcess($Email, "Send invitation to '{0}'")) {
        New-MgInvitation -BodyParameter $params
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

    try{
        Update-AzureADUserProperty -Tenant $tenantKey -User $User -Property "mail" -Value $mail
        Update-AzureADUserProperty -Tenant $tenantKey -User $User -Property "identities" -Value $mailIdentitiesJson

        $response = Get-AzureADUser -Tenant $tenantKey -User $User.id
        $status = $response.mail -eq $mail ? "Success" : "Failure"
        $message = "$mailOriginal > $($response.mail)"
        $entryType = $status -eq "Success" ? "Information" : "Error"
    }
    catch {
        $status = "Failure"
        $entryType = "Error"
        $responseError = Get-Error
        if ($responseError.details.code -contains "ObjectConflict") {
            $status = "ProxyAddressConflict"
            $message = ($responseError.details | Where-Object {$_.code -eq "ObjectConflict"}).message
            $entryType = "Warning"
        }
    }
    Write-Log -Action "UpdateAzureADUserEmail" -Target "$tenantKey\Users\$($User.id)" -Message $message -Status $status -EntryType $entryType -Force

    return $response

}

function global:Update-AzureADUserNames{

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][Alias("FirstName")][string]$GivenName,
        [Parameter(Mandatory=$true)][Alias("LastName","FamilyName")][string]$SurName,
        [Parameter(Mandatory=$true)][string]$DisplayName
    )

    $givenNameOriginal = $User.givenName ?? "None"
    $surNameOriginal = $User.surName ?? "None"
    $displayNameOriginal = $User.displayName ?? "None"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $params = @{
        givenName = $givenName
        surName = $surName
        displayName = $displayName
    }

    $response = Update-AzureADUserProperty -User $User -Tenant $tenantKey @params

    $status = $null
    $message = $null
    if ($response.error) { 
        $status = "Failure"
        $entryType = "Error"
    }
    else {
        $response = Get-AzureADUser -Tenant $tenantKey -User $User.id
        $status = $response.givenName -eq $GivenName -and $response.surName -eq $SurName -and $response.displayName -eq $DisplayName ? "Success" : "Failure"
        $message = "$givenNameOriginal > $($response.givenName), $surNameOriginal > $($response.surName), $displayNameOriginal > $($response.displayName)"
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
        # [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string[]]$Property,
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Delta,
        [switch]$NoCache
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
            $deltaLink = Get-DeltaLink -Tenant $tenantKey -Type $Type
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

            # i think this issue was part of passing multiple values back from Read-AzureADCache incorrectly
            # switch ($Type) {
            #     "Users" {
            #         if ($azureADObjects.GetType().FullName -ne "System.Collections.Hashtable") {
            #             $cacheError = @{code = "CORRUPTED"; summary = "$($cache) cache object is not 'System.Collections.Hashtable'";}
            #             Write-Log -Action "ReadAzureADCache" -Target $cache -Status $cacheError.code -Message $cacheError.Summary -EntryType "Error"
            #             $Delta = $false
            #         }
            #     }
            # }

        }

    #endregion AZUREADOBJECTS CACHE
    #region AZUREADOBJECTS UPDATES
        
        Set-CursorInvisible
            
        $message = "$($Delta ? "Processing" : "Getting") $typeLowerCaseSingular updates"
        Write-Host+ -NoTrace -NoNewLine -NoSeparator $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray # -Prefix "`r"
    
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
                            ($azureADObject.groupTypes -eq "DynamicMembership")) {#} -and $azureADObject.displayName -notin $global:Azure.SpecialGroups)) {

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

            Write-Host+ -NoTrace -NoTimeStamp -NoNewLine " $($emptyString.PadLeft($updateCountLength + $totalCountLength,"`b"))$($updateCount)/$($totalCount)" -ForegroundColor DarkGreen
            $updateCountLength = $updateCount.ToString().Length + 1
            $totalCountLength = $totalCount.ToString().Length + 1

            $restParams.Uri = $response."@odata.nextLink"

        } until ($Delta ? $response."@odata.deltaLink" : !$restParams.Uri)

        $deltaLink = $response."@odata.deltalink" ? $response."@odata.deltaLink" : $null

        Write-Host+

        Set-CursorVisible

        if (!$NoCache -or $AzureADB2C) {

            $message = "Writing $tenantKey $typeLowerCase to cache "
            Write-Host+ -NoTrace -NoSeparator -NoNewLine $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray

            $azureADObjects | Write-AzureADCache -Tenant $tenantKey -Type $Type
            
            $message = " SUCCESS"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen

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

            Set-DeltaLink -Tenant $tenantKey -Type $Type -Value $deltaLink

        }

    #region DELTALINKS UPDATES

    Write-Host+

    return ($NoCache ? $AzureADObjects : $null)

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
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type
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
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray

    if ((Get-Cache $cache).Exists) {
        $deltaLinks = read-cache $cache
    }
    if (!$deltaLinks.$Type) {
        $message = " FAILED"
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkRed
    }
    else {
        $message = " SUCCESS"
        Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen
    }

    return $deltaLinks.$Type

}
    
function global:Set-DeltaLink {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Groups","Users")][string]$Type,
        [Parameter(Mandatory=$true,Position=1)][string]$Value,
        [switch]$AllowNull
    )

    $tenantLowerCase = $Tenant.ToLower()
    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)
    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)

    $cache = "$($tenantLowerCase)-deltaLinks"

    if (!$Value -and !$AllowNull) {throw "AllowNull must be specified when Value is null"}

    $deltaLinks = @{
        Groups = Get-DeltaLink -Tenant $Tenant -Type Groups
        Users = Get-DeltaLink -Tenant $Tenant -Type Users
    }
    $deltaLinks.$Type = $Value

    $message = "Writing $typeLowerCaseSingular delta link "
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message,(Format-Leader -Length 48 -Adjust $message.Length) -ForegroundColor Gray,DarkGray

    $deltaLinks | Write-Cache $cache

    $message = " SUCCESS"
    Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen

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