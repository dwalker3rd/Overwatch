
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
        [Parameter(Mandatory=$true,Position=1)][object]$List
    )   

    $columns = Get-MgBetaSiteListColumn -SiteId $Site.Id -ListId $List.Id |
        Where-Object { -not $_.Hidden -and -not $_.ReadOnly -and $_.ColumnGroup -ne "_Hidden"}
    $columnDisplayNames = $columns.DisplayName

    $listItems = Get-MgBetaSiteListItem -SiteId $site.Id -ListId $List.Id -Property 'id,fields' -ExpandProperty 'fields'

    $listItemData = foreach ($listItem in $listItems) {
        $_listItemData = [ordered]@{}
        foreach ($columnDisplayName in $columnDisplayNames) {
            # map displayName -> columnName
            $columnName = ($columns | Where-Object DisplayName -eq $columnDisplayName).Name
            $_listItemData[$columnDisplayName] = $listItem.Fields.AdditionalProperties[$columnName]
        }
        [pscustomobject]$_listItemData
    }

    return $listItemData

}    

# Connect-AzureAD -Tenant $Tenant
# $site = Get-SharePointSite -Tenant $Tenant -Name "rhsupplies"
# $list = Get-SharePointSiteList -Site $site -Name "ref - Countries"
# $listItems = Get-SharePointSiteListItems -Site $site -List $list
# $listItems | Format-Table