function global:Initialize-AzureAD {

    $global:AzureAD = @()
    $global:AzureAD += @{

        Data = "$($global:Location.Root)\data\azureAD"

        myAzureADTenant = @{
            Name = ""
            Prefix = ""
            DisplayName = " "
            Organization = ""
            Subscription = @{
                Id = ""
                Name = ""
            }
            Tenant = @{
                Type = ""
                Id = ""
                Name = ""
                Domain = @("")
            }
            MsGraph = @{
                Scope = "https://graph.microsoft.com/.default"
                Credentials = "" # app id/secret
                AccessToken = $null
            }
            Sync = @{
                Enabled = $true
                Source = ""
            }
        }

        myAzureADB2CTenant = @{
            Name = ""
            Prefix = ""
            DisplayName = ""
            Organization = ""
            Subscription = @{
                Id = ""
                Name = ""
            }
            Tenant = @{
                Type = "Azure AD B2C"
                Id = ""
                Name = ""
                Domain = @("")
            }
            MsGraph = @{
                Scope = "https://graph.microsoft.com/.default"
                Credentials = "" # app id/secret
                AccessToken = $null
            }
            Admin = @{
                Credentials = ""
            }
            Defaults = @{
                Location = ""
                Bastion = @{ Name = @{ Template = "<0><1>bastion" } }
                ResourceGroup = @{Name = @{ Template = "<0>-<1>-rg" } }
                StorageAccount = @{
                    SKU = "Standard_LRS"
                    Name = @{ Template = "<0><1>storage" }
                    SoftDelete = @{
                        Enabled = $true
                        RetentionDays = 7
                    }
                    Permission = "Off"
                }
                VM = @{
                    Name = @{ Template = "<0><1>vm<2>" }
                    Size = "Standard_DS13_v2"
                    OsType = "Windows"
                    Admin = @{ Template = "<0><1>adm" }
                }
                MLWorkspace = @{ Name = @{ Template = "<0><1>mlws<2>" } }
                CosmosDBAccount = @{  Name = @{ Template = "<0><1>cosmos<2>"  } }
                SqlVM = @{ Name = @{ Template = "<0><1>sqlvm<2>" } }
                KeyVault = @{ Name = @{ Template = "<0><1>-kv" } }
                DataFactory = @{ Name = @{ Template = "<0><1>-adf" } }
            }
        }
    }

}
Set-Alias -Name azureADInit -Value Initialize-AzureAD -Scope Global

function global:Connect-AzureAD {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $appCredentials = Get-Credentials $global:AzureAD.$tenantKey.MsGraph.Credentials
    $appId = $appCredentials.UserName
    $appSecret = $appCredentials.GetNetworkCredential().Password
    $scope = $global:AzureAD.$tenantKey.MsGraph.Scope
    $tenantName = $global:AzureAD.$tenantKey.Tenant.Name

    $uri = "https://login.microsoftonline.com/$tenantName/oauth2/v2.0/token"

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
    
    # headers
    $global:AzureAD.$tenantKey.MsGraph.AccessToken = "$($response.token_type) $($response.access_token)"

    return

}

function global:Invoke-AzureADRestMethod {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$params
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    if ([string]::IsNullOrEmpty($params.Headers.Authorization)) {
        Connect-AzureAD -tenant $tenantKey
        $params.Headers.Authorization = $global:AzureAD.$tenantKey.MsGraph.AccessToken
    }

    $retry = $false
    $response = $null
    try {
        $response = Invoke-RestMethod @params
    }
    catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        $errorCode = ((get-error).ErrorDetails | ConvertFrom-Json).error.code
        if ($errorCode -eq "InvalidAuthenticationToken") {
            Connect-AzureAD -tenant $tenantKey
            $params.Headers.Authorization = $global:AzureAD.$tenantKey.MsGraph.AccessToken
            $retry = $true
        }
    }
    if ($retry) {
        $response = Invoke-RestMethod @params
    }

    return $response
    
}

function global:Get-AzureADUser {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UserId","Email","Mail")][string]$User,
        # [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}


    $isUserId = $User -match $global:RegexPattern.Guid
    $isGuestUserPrincipalName = $User -match $global:RegexPattern.AzureAD.UserPrincipalName -and $User -like "*#EXT#*"
    $isEmail = $User -match $global:RegexPattern.Mail
    $isMemberUserPrincipalName = $User -match $global:RegexPattern.AzureAD.UserPrincipalName

    $isValidUser = $isUserId -or $isEmail -or $isMemberUserPrincipalName -or $isGuestUserPrincipalName
    if (!$isValidUser) {
        throw "'$User' is not a valid object id, userPrincipalName or email address."
    }

    $filter = $isEmail ? "mail eq '$User'" : $null
    $filter += $isMemberUserPrincipalName ? "$($filter ? " or " : $null)userPrincipalName eq '$User'" : $null
    $filter = $isGuestUserPrincipalName ? "userPrincipalName eq '$($User.Replace("#","%23"))'" : $filter

    $uri = "https://graph.microsoft.com/$graphApiVersion/users" 
    $uri += $filter ? "?`$filter=$filter" : "/$User"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:AzureAD.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }

    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams # -Uri $uri -Method GET -Headers $headers
    $azureADUser = $filter ? $response.value : $response

    return $azureADUser | Select-Object -Property $($View ? $AzureADView.User.$($View) : $AzureADView.User.Default)
     
}

#
# ISSUE (MSAL.PS): https://github.com/AzureAD/MSAL.PS/issues/32
# MSAL.PS and Az.Accounts use different versions of the Microsoft.Identity.Client
# Az.Accounts requires Microsoft.Identity.Client, Version=4.30.1.0
# MSAL.PS requires Microsoft.Identity.Client, Version=4.21.0 
# if Connect-AzAccount+ is called first, then Reset-AzureADUserPassword will fail
# if Reset-AzureADUserPassword is called first, then Connect-AzAccount+ will fail
# 

function global:Reset-AzureADUserPassword {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("UserPrincipalName","UserId")][string]$User,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    if ($User -notmatch $global:RegexPattern.Guid -and $User -notmatch $global:RegexPattern.AzureAD.UserPrincipalName) {
        throw "'$User' is not a valid AzureAD user id or userPrincipalName."
    }

    $getParams = @{
        Tenant = $tenantKey
        GraphApiVersion = $GraphApiVersion
        User = $User
    }

    $azureADUser = Get-AzureADUser @getParams 
    if (!$azureADUser) {
        throw "User '$User' not found in tenant $($global:AzureAD.$tenantKey.Tenant.Name)"
        return
    }

    #region LIST PASSWORD AUTHENTICATION METHODS

        $uri = "https://graph.microsoft.com/$graphApiVersion/users/$($azureADUser.id)/authentication/passwordMethods"

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type", "application/json")
        $headers.Add("Authorization", $global:AzureAD.$tenantKey.MsGraph.AccessToken)

        $restParams = @{
            ContentType = 'application/x-www-form-urlencoded'
            Headers = $headers
            Method = 'GET'
            Uri = $uri
        }

        $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams # -Uri $uri -Method GET -Headers $headers
        $passwordAuthenticationMethod = $response

        if (!$passwordAuthenticationMethod) {
            throw "Unable to list password authentication methods for user '$User'"
            return
        }

    #endregion LIST PASSWORD AUTHENTICATION METHODS
    #region RESET PASSWORD
    
        # MSAL.PS is required here

        $appCredentials = Get-Credentials $global:AzureAD.$tenantKey.MsGraph.Credentials
        $appId = $appCredentials.UserName
        # $appSecret = $appCredentials.Password
        # $scope = $global:AzureAD.$tenantKey.MsGraph.Scope
        $tenantId = $global:AzureAD.$tenantKey.Tenant.Id

        # opens system default browser for interactive authentication
        $token = Get-MsalToken -TenantId $tenantId -ClientId $appId -Interactive #-ClientSecret $appSecret 

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", $token.CreateAuthorizationHeader())
        $headers.Add("Content-Type", "application/json")
        
        $newPassword = New-RandomPassword

        $body = "{
        `n  `"newPassword`": `"$newPassword`"
        `n}"
        
        $response = Invoke-RestMethod "https://graph.microsoft.com/beta/users/$($azureADUser.userPrincipalName)/authentication/passwordMethods/$($passwordAuthenticationMethod.value.id)/resetPassword" -Method POST -Headers $headers -Body $body

    #endregion RESET PASSWORD

    $creds = Request-Credentials -UserName $azureADUser.UserPrincipalName -Password $newPassword
    Set-Credentials -Name $azureADUser.UserPrincipalName -Credentials $creds

    return
     
}

function global:Get-AzureADUser+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UserId")][string]$User,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    if ($User -notmatch $global:RegexPattern.Guid -and $User -notmatch $global:RegexPattern.AzureAD.UserPrincipalName) {
        throw "'$User' is not a valid AzureAD user id or userPrincipalName."
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
        $azureADUser | Add-Member -NotePropertyName tenant -NotePropertyValue $global:AzureAD.$tenantKey.Tenant
    }

    return $azureADUser | Select-Object -Property $($View ? $AzureADView.User.$($View) : $AzureADView.User.Plus)

}

function global:IsMember {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UserId","Email","Mail")][string]$User,
        [Parameter(Mandatory=$false)][Alias("GroupId","GroupDisplayName","GroupName")][string]$Group,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $azureADGroups, $cacheError = Get-AzureADGroups -Tenant $tenantKey -AsArray
    $azureADUserMembership = $azureADGroups | Where-Object {$_.members -contains $AzureADUser.id}

    return $azureADUserMembership | Select-Object -Property $($View ? $AzureADView.User.Membership.$($View) : $AzureADView.User.Membership.Default)

}


function global:Send-AzureADInvitation {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$false)][string]$Email,
        [Parameter(Mandatory=$false)][string]$DisplayName,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta"
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $uri = "https://graph.microsoft.com/$($graphApiVersion)/invitations"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:AzureAD.$tenantKey.MsGraph.AccessToken)

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
        
    $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams # -Uri $uri -Method POST -Headers $headers -Body $body
    
    return $response

}

function global:Get-AzureADObjects {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type,
        [Parameter(Mandatory=$false)][ValidateSet("v1.0","beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string[]]$Property,
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Delta,
        [switch]$NoCache
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    if ($NoCache) {$Delta = $false}

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $AzureADB2C = $azureAD.$($tenantKey).tenant.type -eq "Azure AD B2C"
    if ($AzureADB2C -and $Delta) {throw "Delta switch is not valid for $($azureAD.$($tenantKey).tenant.type) tenants."}

    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)
    $typeLowerCase = $Type.ToLower()
    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)

    $azureADObjects = @{}
    $Delta = $Id ? $false : $Delta

    $queryParams = @{
        default = @{
            Users = @{
                property = @("id","userPrincipalName","displayName","mail","accountEnabled")
            }
        }
    }
    $queryParams += @{
        Users = @{
            property = $Property ?? $AzureADB2C ? @("id","userPrincipalName","displayName","mail","accountEnabled","identities") : $queryParams.default.Users.property
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
                $Delta = $false
            }
            switch ($Type) {
                "Users" {
                    if ($azureADObjects.GetType().FullName -ne "System.Collections.Hashtable") {
                        $cacheError = @{code = "CORRUPTED"; summary = "$($cache) cache object is not 'System.Collections.Hashtable'";}
                        Write-Log -Action "ReadAzureADCache" -Target $cache -Status $cacheError.code -Message $cacheError.Summary -EntryType "Error"
                        $Delta = $false
                    }
                }
            }


        }

    #endregion AZUREADOBJECTS CACHE
    #region AZUREADOBJECTS UPDATES
        
        [console]::CursorVisible = $false
            
        $message = "$($Delta ? "Processing" : "Getting") $typeLowerCaseSingular updates"
        Write-Host+ -NoTrace -NoNewLine -NoSeparator $message,(Write-Dots -Length 48 -Adjust (-($message.Length))) -ForegroundColor Gray,DarkGray -Prefix "`r"
    
        $uri = $Delta ?  $deltaLink : "https://graph.microsoft.com/$($graphApiVersion)/$typeLowerCase$($Filter ? $null : "/delta")?$($queryParams.$Type.select)$($Filter ? "`&$Filter" : $null)"

        if ($AzureADB2C) {
            $uri = $uri.Replace("/delta","")
        }

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type", "application/json")
        $headers.Add("Authorization", $global:AzureAD.$tenantKey.MsGraph.AccessToken)

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

                        if (!$azureADObject.groupTypes -and $azureADObject.securityEnabled) { # TODO: define the type of group in definitions

                            $newAzureADObject = @{
                                id = $azureADObject.id
                                displayName = $azureADObject.displayName
                                groupType = $azureADObject.groupType
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

        [console]::CursorVisible = $true

        if (!$NoCache -or $AzureADB2C) {

            $message = "Writing $tenantKey $typeLowerCase to cache "
            Write-Host+ -NoTrace -NoSeparator -NoNewLine $message,(Write-Dots -Length 48 -Adjust (-($message.Length))) -ForegroundColor Gray,DarkGray

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    # $AzureADB2C = $azureAD.$($tenantKey).tenant.type -eq "Azure AD B2C"

    $typeLowerCase = $Type.ToLower()
    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)

    $action = "Initialize"; $target = "AzureAD\$tenantKey"
    try {

        $action = "Export"; $target = "AzureAD\$tenantKey\$Type"
        $message = "Exporting $typeLowerCase cache : PENDING"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

        switch ($Type) {
            "Users" {
                $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray

                switch ($azureAD.$tenantKey.tenant.type) {
                    "default" {
                        $azureADUsers | Sort-Object -property userPrincipalName | 
                            Select-Object -property @{name="User Id";expression={$_.id}},@{name="User Principal Name";expression={$_.userPrincipalName}},@{name="User Display Name";expression={$_.displayName}},@{name="User Mail";expression={$_.mail}},@{name="User Account Enabled";expression={$_.accountEnabled}},timestamp | 
                                Export-Csv  "$($azureAD.Data)\$tenantKey-users.csv"
                    }
                    "Azure AD B2C" {
                        $azureADUsers | Sort-Object -property userPrincipalName | 
                            Select-Object -property @{name="User Id";expression={$_.id}},@{name="User Principal Name";expression={$_.userPrincipalName}},@{name="User Display Name";expression={$_.displayName}},@{name="User Mail";expression={($_.identities | where-object {$_.signInType -eq "emailAddress"}).issuerAssignedId}},@{name="User Account Enabled";expression={$_.accountEnabled}},timestamp | 
                                Export-Csv  "$($azureAD.Data)\$tenantKey-users.csv"
                    }
                }

                $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

                Write-Host+
                Copy-Files -Path "$($azureAD.Data)\$tenantKey-$typeLowerCase.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
                Write-Host+

            }
            "Groups" {
                $azureADGroups,$cacheError = Get-AzureADGroups -Tenant $tenantKey -AsArray
                $azureADGroups | Sort-Object -property displayName | 
                    Select-Object -property @{name="Group Id";expression={$_.id}},@{name="Group Display Name";expression={$_.displayName}},@{name="Group Security Enabled";expression={$_.securityEnabled}},@{name="Group Type";expression={$_.groupType}},timestamp  | 
                        Export-Csv  "$($azureAD.Data)\$tenantKey-groups.csv"
                ($azureADGroups | Foreach-Object {$groupId = $_.id; $_.members | Foreach-Object { @{groupId = $groupId; userId=$_} } }) | 
                    Sort-Object -property groupId,userId -unique | 
                        Select-Object -property @{name="Group Id";expression={$_.groupId}}, @{name="User Id";expression={$_.userId}} | 
                            Export-Csv  "$($azureAD.Data)\$tenantKey-groupMembership.csv"

                $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen                             

                Write-Host+
                Copy-Files -Path "$($azureAD.Data)\$tenantKey-groups.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
                Copy-Files -Path "$($azureAD.Data)\$tenantKey-groupMembership.csv" -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Verbose:$true
                Write-Host+
            }
        }
    }
    catch {

        $status = "Error"
        Write-Log -Context "AzureADCache" -Action $action -Target $target -Status $status -EntryType "Error" -Message $_.Exception.Message -Force
        Write-Host+ -NoTrace $Error -ForegroundColor DarkRed

    }
    finally {}
}

function global:Get-DeltaLink {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][ValidateSet("Groups","Users")][string]$Type
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $deltaLinks = @{
        Groups = $null
        Users = $null
    }

    $tenantLowerCase = $Tenant.ToLower()
    $typeLowerCaseSingular = $Type.ToLower().Substring(0,$Type.Length-1)
    # $typeTitleCase = (Get-Culture).TextInfo.ToTitleCase($Type)

    $cache = "$($tenantLowerCase)-deltaLinks"

    $message = "Reading $typeLowerCaseSingular delta link "
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message,(Write-Dots -Length 48 -Adjust (-($message.Length))) -ForegroundColor Gray,DarkGray

    if ((get-cache $cache).Exists()) {
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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message,(Write-Dots -Length 48 -Adjust (-($message.Length))) -ForegroundColor Gray,DarkGray

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantLowerCase = $Tenant.ToLower()
    $typeLowerCase = $Type.ToLower()
    $typeUpperCase = $Type.ToUpper()

    $cache = "$($tenantLowerCase)-$($typeLowerCase)"
    $cacheError = $null

    # $retryDelay = New-Timespan -Seconds 5
    # $retryMaxAttempts = 3
    # $retryAttempts = 0

    $filteredObject = @{}
    if ($(get-cache $cache).Exists()) {

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
                $errorMessage = $_.Exception.Message
                Write-Log -Action "ReadCache" -Target $cache -Status "Error" -Message $errorMessage -EntryType "Error"
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
        $cacheError = @{code = "NOTFOUND"; summary = "$($cache) not found";}
    }

    if (!$azureADObject -and !$After) {
        $cacheError = @{code = "NO$($typeUpperCase)"; summary = "$($cache) contains no $typeLowerCase";}
    }
    # else {
    #     $message = " $($azureADObject.Count)"
    #     Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message -ForegroundColor DarkGreen
    # }

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
        if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}
        
        $InputObject = Invoke-Expression "Get-AzureAD$($obj) -Tenant $tenantKey -AsArray"
        if (!$InputObject) {
            throw "Missing $Types object"
        }
    
    }
    
    if ($Id) {$where = "{`$_.id -$Operator `$Id}"}
    if ($UserPrincipalName) {$where = "{`$_.userPrincipalName -$Operator `$UserPrincipalName}"}
    if ($DisplayName) {$where = "{`$_.displayName -$Operator `$DisplayName}"}
    if ($Mail) {$where = "{`$_.mail -$Operator `$Mail}"}

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
        if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

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
        if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

        $Groups, $cacheError = Get-AzureADGroups -Tenant $Tenant -AsArray

    }
    
    $findParams = @{Operator = $Operator}
    if ($Id) {$findParams += @{Id = $Id}}
    if ($DisplayName) {$findParams += @{DisplayName = $DisplayName}}
    
    return Find-AzureADObject -Tenant $tenantKey -Type "Group" -Groups $Groups @findParams

}