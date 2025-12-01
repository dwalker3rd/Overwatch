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
        Connect-MgGraph+ -tenant $tenantKey
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
            Connect-MgGraph+ -tenant $tenantKey
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
        [Parameter(Mandatory=$false)][string[]]$IncludeColumn,
        [Parameter(Mandatory=$false)][string[]]$ExcludeColumn,
        # [Parameter(Mandatory=$false)][string[]]$Filter,
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View,
        [Parameter(Mandatory=$false)][int]$PageSize = 200
    )

    if ($Column -and $ExcludeColumn) {
        throw "The parameters -Column and -ExcludeColumn cannot be used together."
    }
    if ($Column -and $IncludeColumn) {
        throw "The parameters -Column and -IncludeColumn cannot be used together."
    }

    $tenantKey = $Tenant.Split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) { throw "$tenantKey is not a valid/configured AzureAD tenant." }

    $headers = @{
        "Content-Type"  = "application/json"
        "Authorization" = $global:Azure.$tenantKey.MsGraph.AccessToken
    }

    # get column metadata
    $columnsUri = "https://graph.microsoft.com/$GraphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/columns"
    $restParams = @{
        ContentType = 'application/json'
        Headers     = $headers
        Method      = 'GET'
        Uri         = $columnsUri
    }

    $_columns  = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams
    $columns   = $_columns.Value

    # remove readonly and hidden columns
    $selectColumns = $columns |
        Where-Object {
            (-not $_.readOnly) -and
            (-not $_.hidden) -and
            ($_.columnGroup -ne "_Hidden") -and
            (
                ($ExcludeColumn -and ($_.displayName -notin $ExcludeColumn)) -or
                ($IncludeColumn -and ($_.displayName -in $IncludeColumn)) -or
                (-not $ExcludeColumn -and -not $IncludeColumn)
            )
        }

    # always include ID/Created/Modified
    $requiredCols = @("ID","Created","Modified")
    $columnDisplayNames = ($selectColumns.displayName + $requiredCols) | Select-Object -Unique

    # build fast lookup maps
    #    displayName -> internal column name
    #    displayName -> lookup metadata (if lookup)
    $displayToColumnName = @{}
    $lookupColumnsInfo   = @{} 

    foreach ($col in $columns) {
        $displayToColumnName[$col.displayName] = $col.name
        if ($col.lookup -and $col.lookup.listId -and $col.lookup.columnName) {
            $lookupColumnsInfo[$col.displayName] = @{
                ListId     = $col.lookup.listId
                ColumnName = $col.lookup.columnName
            }
        }
    }

    # preload lookup lists
    #   $lookupCache[displayName][lookupId] = "Actual Text Value"
    $lookupCache = @{}

    foreach ($dispName in $columnDisplayNames) {

        if ($lookupColumnsInfo.ContainsKey($dispName)) {

            $listIdForLookup   = $lookupColumnsInfo[$dispName].ListId
            $colNameForLookup  = $lookupColumnsInfo[$dispName].ColumnName

            $lookupUri = "https://graph.microsoft.com/$GraphApiVersion/sites/$($Site.Id)/lists/$listIdForLookup/items?$top=5000&expand=fields(select=$colNameForLookup)"
            $restParams.Uri = $lookupUri
            $_lookupItems = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams
            $allLookupItems = $_lookupItems.Value

            $map = @{}
            foreach ($li in $allLookupItems) {
                $map[$li.id] = $li.fields.$colNameForLookup
            }

            $lookupCache[$dispName] = $map
        }
    }

    # query graph for the sharepoint list items including:
    #    - the internal columnName for each display column
    #    - plus the "*LookupId" variants, because we might need to resolve them
    $internalFieldNames = @()

    foreach ($dispName in $columnDisplayNames) {
        if ($displayToColumnName.ContainsKey($dispName)) {
            $internalName = $displayToColumnName[$dispName]
            $internalFieldNames += $internalName
            $internalFieldNames += ($internalName + 'LookupId')
        }
    }

    $internalFieldNames = $internalFieldNames | Select-Object -Unique
    $internalFieldSelect = $internalFieldNames -join ","

    $listItemsUri = "https://graph.microsoft.com/$GraphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/items?expand=fields(select=$internalFieldSelect)&`$top=$PageSize"
    # if ($Filter) { $listItemsUri += "&`$filter=$Filter" }

    $restParams.Uri = $listItemsUri

    # loop on #odata.nextLink to get all listItems
    $listItems = @()
    do {
        $response = Invoke-AzureADRestMethod -tenant $tenantKey -params $restParams 
        $listItems += $response.value | Select-Object -ExcludeProperty "@odata.type"
        $restParams.Uri = $response."@odata.nextLink"
    } until (!$restParams.Uri)

    # build output object
    $result = foreach ($listItem in $listItems) {

        $row = [ordered]@{}

        foreach ($dispName in $columnDisplayNames) {

            $internalName = $displayToColumnName[$dispName]

            $rawValue     = $listItem.fields.$internalName
            $lookupIdVal  = $listItem.fields."$($internalName)LookupId"

            if ($null -ne $rawValue -and $rawValue -ne "") {

                if ($dispName -eq 'ID') {
                    $row[$dispName] = [int]$rawValue
                }
                elseif ($dispName -in @('Created','Modified')) {
                    $row[$dispName] = [datetime]$rawValue
                }
                else {
                    $row[$dispName] = $rawValue
                }

            } elseif ($lookupIdVal -and $lookupCache.ContainsKey($dispName)) {
                # Resolve lookup using the cache
                $resolved = $lookupCache[$dispName][$lookupIdVal]
                $row[$dispName] = $resolved
            }
            else {
                $row[$dispName] = $null
            }
        }

        [pscustomobject]$row
    }

    return $result
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
        # [Parameter(Mandatory=$false)][string[]]$Filter,
        [Parameter(Mandatory=$false)][ValidateSet("beta","v1.0")][string]$GraphApiVersion = "beta",
        [Parameter(Mandatory=$false)][string]$View
    ) 

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."} 

    # $_site = Get-SharePointSite -Tenant $tenantKey -Site $Site
    # $_list = Get-SharePointSiteList -Tenant $tenantKey -Site $Site -List $List    

    $uri = "https://graph.microsoft.com/$graphApiVersion/sites/$($Site.Id)/lists/$($List.Id)/items/$($ListItem.Id)"
    # if (![string]::IsNullOrEmpty($Filter)) {
    #     $uri += "?filter=$Filter"
    # }    
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", $global:Azure.$tenantKey.MsGraph.AccessToken)

    $restParams = @{
        ContentType = 'application/json'
        Headers = $headers
        Method = 'Delete'
        Uri = $uri
    }    

    $response = Invoke-SharePointRestMethod -tenant $tenantKey -params $restParams   

    return $response

}

function global:Remove-SharepointSiteListItems {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'        
    )]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][object]$Site,
        [Parameter(Mandatory=$true,Position=2)][object]$List,
        [Parameter(Mandatory=$false,Position=3)][object]$ListItems,
        [switch]$ShowProgress
    )     

    if (!$ListItems) {
        $ListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $List
    }

    if ($ListItems.count -eq 0) {
        return
    }

    if ($PSCmdlet.ShouldProcess("$($List.Name)", "Remove $($ListItems.count) list items")) {

        Write-Host+ -Iff $($ShowProgress.IsPresent -and $ConfirmPreference -notin ("None", "SilentlyContinue"))

        $i = $ListItems.count 
        $iStr = $i.ToString()  
        $iLen = $iStr.Length 
        $iMax = $iLen + 1
        $iStr = "$($emptyString.PadLeft($iMax - $iLen, " "))$iStr" 

        Set-CursorInvisible

        $message = "List items remaining to be deleted:"
        Write-Host+ -Iff $($ShowProgress.IsPresent) -NoTimestamp -NoTrace -NoNewLine -NoSeparator $message, $iStr -ForegroundColor DarkGray, DarkBlue
     
        foreach ($listItem in $ListItems) {        
            $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $list -ListItem $listItem
            if ($i % 10 -eq 0) {
                $iStr = $i.ToString()  
                $iLen = $iStr.Length 
                $iStr = "$($emptyString.PadLeft($iMax - $iLen, " "))$iStr"                 
                Write-Host+ -Iff $($ShowProgress.IsPresent) -NoTimestamp -NoTrace -NoNewLine -NoSeparator "`e[$($iMax)D$iStr" -ForegroundColor DarkBlue
            }  
            $i--
        } 

        $iStr = $i.ToString()  
        $iLen = $iStr.Length 
        $iStr = "$($emptyString.PadLeft($iMax - $iLen, " "))$iStr"  
        Write-Host+ -Iff $($ShowProgress.IsPresent) -NoTimestamp -NoTrace -NoSeparator -NoNewLine "`e[$($iMax)D$iStr" -ForegroundColor DarkBlue
        Write-Host+ -Iff $($ShowProgress.IsPresent)

        Set-CursorVisible

    }

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