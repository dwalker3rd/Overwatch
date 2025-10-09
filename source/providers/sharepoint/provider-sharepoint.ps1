function global:Connect-SharePoint {

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
            ContentType = 'application/json'
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

function global:Invoke-SharePointRestMethod {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true, Position=1)][object]$params
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
function global:Get-SharePointSite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][string]$Site,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $siteId = "$tenantKey.sharepoint.com:/sites/$($Site):"    

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$siteId"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/json'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }

    $_site = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams 

    return $_site

}

function global:Get-SharePointSiteList {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Site,
        [Parameter(Mandatory=$true,Position=2)][string]$List,
        [Parameter(Mandatory=$false)][ValidateSet("beta")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    # $_site = Get-SharePointSite -Tenant $Tenant -Site $Site

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List)"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/json'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }

    $_list = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams 

    return $_list

}

function global:Get-SharePointSiteListColumns {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=0)][object]$Site,
        [Parameter(Mandatory=$true,Position=1)][object]$List,
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    ) 

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}   

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/columns"
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/json'
        Headers = $headers
        Method = 'GET'
        Uri = $uri
    }    

    $_listItem = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams    

    return !$_listItem.error ? $_listItem.Value : $_listItem.error

}

function global:Get-SharePointSiteListItems {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Site,
        [Parameter(Mandatory=$true,Position=2)][object]$List,
        [Parameter(Mandatory=$false)][string[]]$Column,        
        [Parameter(Mandatory=$false)][string[]]$IncludeColumn = @(),
        [Parameter(Mandatory=$false)][string[]]$ExcludeColumn = @("Title", "Attachments"),
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    )   

    if ($Column -and $ExcludeColumn) {
        throw "The parameters -Column and -ExcludeColumn cannot be used together."
    }
    if ($Column -and $IncludeColumn) {
        throw "The parameters -Column and -IncludeColumn cannot be used together."
    }

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."} 

    # $_site = Get-SharePointSite -Tenant $tenantKey -Site $Site
    # $_list = Get-SharePointSiteList -Tenant $tenantKey -Site $Site -List $List    

    $columnsUri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/columns"
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/json'
        Headers = $headers
        Method = 'GET'
        Uri = $columnsUri
    }    

    $_columns = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams
    $columns = $_columns.Value
    $selectColumns = $columns | 
        Where-Object {-not $_.readonly -and -not $_.hidden -and $_.columnGroup -ne "_Hidden" -and $_.displayName -notin $ExcludeColumn -or $_displayName -in $IncludeColumn}
    $columnDisplayNames = $selectColumns.displayName
    $columnDisplayNames += @("ID", "Created", "Modified")
    # $columnDisplayNamesString = $columnDisplayNames -join ","

    $listItemsUri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/items?expand=fields" #(select=$($columnDisplayNamesString))"
    $restParams.uri = $listItemsUri

    $_listItems = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams  
    $listItems = $_listItems.Value  

    $listItemData = foreach ($listItem in $listItems) {
        $_listItemData = [ordered]@{}
        foreach ($columnDisplayName in $columnDisplayNames) {
            # map displayName -> columnName
            $columnName = ($columns | Where-Object { $_.DisplayName -eq $columnDisplayName }).Name            
            if ($listItem.fields.$columnName) {
                if ($columnDisplayName -in @("ID")) {
                    $_listItemData[$columnDisplayName] = [int]$listItem.fields.$columnName
                }
                elseif ($columnDisplayName -in @("Created", "Modified")) {
                    $_listItemData[$columnDisplayName] = [datetime]$listItem.fields.$columnName
                }
                else {
                    $_listItemData[$columnDisplayName] = $listItem.fields.$columnName
                }                
            }
            else {
                if ($listItem.Fields."$($columnName)LookupId") {
                    $columnLookupListId = ($columns | Where-Object { $_.DisplayName -eq $columnDisplayName }).Lookup.ListId
                    $columnLookupColumnName = ($columns | Where-Object { $_.DisplayName -eq $columnDisplayName }).Lookup.ColumnName    
                    $listItemsUri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($columnLookupListId)/items?expand=fields(select=$columnLookupColumnName)"
                    $restParams.uri = $listItemsUri
                    $lookupValueListItem = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams
                    $lookupValueListItem = $lookupValueListItem.Value 
                    $lookupValueListItem = $lookupValueListItem | Where-Object { $_.id -eq $listItem.Fields."$($columnName)LookupId"}
                    $lookupValue = $lookupValueListItem.Fields.$columnLookupColumnName
                    $_listItemData[$columnDisplayName] = $lookupValue
                    # $_listItemData["$($columnName)LookupId"] = [int]$listItem.Fields.AdditionalProperties["$($columnName)LookupId"]
                }
                else {
                    $_listItemData[$columnDisplayName] = $listItem.Fields.$columnName
                }
            }
        }
        [pscustomobject]$_listItemData
    }

    return $listItemData

}

function global:New-SharePointSiteListItem {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Site,
        [Parameter(Mandatory=$true,Position=2)][object]$List,
        [Parameter(Mandatory=$true,Position=3)][object]$ListItemBody,
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    ) 

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."} 

    # $_site = Get-SharePointSite -Tenant $tenantKey -Site $Site
    # $_list = Get-SharePointSiteList -Tenant $tenantKey -Site $Site -List $List    

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/items"
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        Body = $ListItemBody | ConvertTo-Json -Compress
        ContentType = 'application/json'
        Headers = $headers
        Method = 'POST'
        Uri = $uri
    }    

    $_listItem = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams    

    return $_listItem

}

function global:Remove-SharePointSiteListItem {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Site,
        [Parameter(Mandatory=$true,Position=2)][object]$List,
        [Parameter(Mandatory=$true,Position=3)][object]$ListItem,
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    ) 

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."} 

    # $_site = Get-SharePointSite -Tenant $tenantKey -Site $Site
    # $_list = Get-SharePointSiteList -Tenant $tenantKey -Site $Site -List $List    

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/items/$($ListItem.Id)"
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/json'
        Headers = $headers
        Method = 'Delete'
        Uri = $uri
    }    

    $_noListItem = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams   
    $_noListItem | Out-Null 

    return

}

function global:Update-SharePointSiteListItem {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Site,
        [Parameter(Mandatory=$true,Position=2)][object]$List,
        [Parameter(Mandatory=$true,Position=3)][object]$ListItem,
        [Parameter(Mandatory=$true,Position=4)][object]$FieldValueSet,
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    ) 

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."} 

    # $_site = Get-SharePointSite -Tenant $tenantKey -Site $Site
    # $_list = Get-SharePointSiteList -Tenant $tenantKey -Site $Site -List $List    

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/items/$($ListItem.Id)/fields"
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        Body = $FieldValueSet | ConvertTo-Json -Compress
        ContentType = 'application/json'
        Headers = $headers
        Method = 'Patch'
        Uri = $uri
    }    

    $_listItem = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams    

    return $_listItem

}