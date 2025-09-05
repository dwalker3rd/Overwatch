
function global:Get-SharePointSite {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Tenant,
        [Parameter(Mandatory=$true,Position=1)][string]$Name
    )

    $siteId = "$Tenant.sharepoint.com:/sites/$($Name):"
    $site = Get-MgSite -SiteId $siteId

    return $site

}

function global:Get-SharePointSiteList {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Site,
        [Parameter(Mandatory=$true,Position=1)][string]$Name
    )

    $list = Get-MgSiteList -SiteId $Site.Id | Where-Object DisplayName -eq $Name

    return $list

}

function global:Get-SharePointSiteListItems {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Site,
        [Parameter(Mandatory=$true,Position=1)][object]$List,
        [Parameter(Mandatory=$false)][string[]]$Column,
        [Parameter(Mandatory=$false)][string[]]$ExcludeColumn
    )   

    if ($Column -and $ExcludeColumn) {
        throw "The parameters -Column and -ExcludeColumn cannot be used together."
    }

    $_columns = Get-MgBetaSiteListColumn -SiteId $Site.Id -ListId $List.Id |
        Where-Object { (-not $_.Hidden -and -not $_.ReadOnly -and $_.ColumnGroup -ne "_Hidden") -or $_.DisplayName -eq "ID" }
    if ($Column) {
        $_columns = $_columns | Where-Object { $_.DisplayName -in $Column }
    }
    if ($ExcludeColumn) {
        $_columns = $_columns | Where-Object { $_.DisplayName -notin $ExcludeColumn }
    }
    $columnDisplayNames = $_columns.DisplayName

    $listItems = Get-MgBetaSiteListItem -SiteId $site.Id -ListId $List.Id -Property 'id, createdDateTime, lastModifiedDateTime, fields' -ExpandProperty 'fields'

    $listItemData = foreach ($listItem in $listItems) {
        $_listItemData = [ordered]@{}
        foreach ($columnDisplayName in $columnDisplayNames) {
            # map displayName -> columnName
            $columnName = ($_columns | Where-Object { $_.DisplayName -eq $columnDisplayName }).Name
            if ($listItem.$columnDisplayName) {
                if ($columnDisplayName -in @("id", "createdDateTime", "lastModifiedDateTime")) {
                    $_listItemData[$columnDisplayName] = [int]$listItem.$columnDisplayName
                }
                else {
                    $_listItemData[$columnDisplayName] = $listItem.$columnDisplayName
                }
            }
            else {
                if ("$($columnName)LookupId" -in $listItem.Fields.AdditionalProperties.Keys) {
                    $columnLookupListId = ($_columns | Where-Object { $_.DisplayName -eq $columnDisplayName }).Lookup.ListId
                    $columnLookupColumnName = ($_columns | Where-Object { $_.DisplayName -eq $columnDisplayName }).Lookup.ColumnName                    
                    $lookupValueListItem = Get-MgBetaSiteListItem -SiteId $Site.Id -ListId $columnLookupListId -ListItemId $listItem.Fields.AdditionalProperties."$($columnName)LookupId"
                    $lookupValue = $lookupValueListItem.Fields.AdditionalProperties.$columnLookupColumnName
                    $_listItemData[$columnDisplayName] = $lookupValue
                    # $_listItemData["$($columnName)LookupId"] = [int]$listItem.Fields.AdditionalProperties["$($columnName)LookupId"]
                }
                else {
                    $_listItemData[$columnDisplayName] = $listItem.Fields.AdditionalProperties[$columnName]
                }
            }
        }
        [pscustomobject]$_listItemData
    }

    return $listItemData

}

function global:Remove-SharePointSiteListItem {


    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Site,
        [Parameter(Mandatory=$true,Position=1)][object]$List,
        [Parameter(Mandatory=$true)][object]$ListItem
    ) 
    
    Remove-MgBetaSiteListItem -SiteId $Site.Id -ListId $List.Id -ListItemId $ListItem.Id

}