#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param()

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id = "SPOSyncFabric"}
$overwatchProductId = $global:Product.Id
. $PSScriptRoot\definitions.ps1  

function Update-SharepointListItemHelper {

    param(
        [Parameter(Mandatory=$true,Position=0)][object]$Site,
        [Parameter(Mandatory=$true,Position=1)][object]$List,
        [Parameter(Mandatory=$true,Position=2)][object]$ListItem,
        [Parameter(Mandatory=$false)][string]$ColumnDisplayName,
        [Parameter(Mandatory=$false)][object]$Value,
        [Parameter(Mandatory=$false)][switch]$Status,
        [Parameter(Mandatory=$false)][switch]$Active
    )              

    if ($Status -and $Active) {
        throw "-Status and -Active cannot be used together."
    }     

    if ($Status) {
        $ColumnDisplayName = "Status"
    }
    if ($Active) {
        $ColumnDisplayName = "Active"
    }

    $_columns = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $Site -List $List
    $_column = $_columns | Where-Object { $_.DisplayName -eq $ColumnDisplayName }
    $columnName = $_column.Name
    $columnDisplayName = $_column.displayName

    if ($_column.lookup) {
        $lookupListId = $_column.lookup.ListId
        $lookupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $Site -List $lookupListId 
        $lookupColumns = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $Site -List $lookupList
        $lookupColumn = $lookupColumns | Where-Object { $_.name -eq $_column.lookup.columnName}
        $lookupColumnName = $lookupColumn.displayName
        $lookupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $Site -List $lookupList
        $lookupListItem = $lookupListItems | Where-Object { $_."$lookupColumnName" -eq $Value }
        $columnName += "LookupId"
        $Value = $lookupListItem.Id
    }
    $listItemValue = "`"$Value`""

    $fieldvalueset = @{ $columnName = $Value }
    if ($null -eq [object]$Value) {
        $fieldvalueset = @{ $columnName = " " }
        $listItemValue = "an empty string"
    }
    $fieldvaluesetSerialized = $fieldvalueset | ConvertTo-Json -Compress

    try{
        $_listItem = Update-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $List -ListItem $ListItem -FieldValueSet $fieldvalueset
    }
    catch {
        Write-Log -Context $overwatchProductId -Target "ListItem $($ListItem.Id)" -Action "Update" -Status "Error" -Message "Attempted to update column `"$columnDisplayName`" with $listItemValue" -EntryType "Error" -Force
        Write-Log -Context $overwatchProductId -Target "ListItem $($ListItem.Id)" -Action "Update" -Status "Error" -Message $error[-1] -EntryType "Error" -Force
        return $_listItem
    }


    Write-Log -Context $overwatchProductId -Target "ListItem $($ListItem.Id)" -Action "Update" -Status "Success" -Message "Updated column `"$columnDisplayName`" with $listItemValue" -EntryType "Information" -Force
    return $_listItem

}

# Write-Host+

Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Connecting to tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
Connect-Fabric -Tenant $global:Fabric.Tenant
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Connecting to Exchange Online for tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
Connect-ExchangeOnline+ -Tenant $global:Fabric.Tenant 
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Connecting to tenant ", $global:SharePoint.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
Connect-MgGraph+ -Tenant $global:SharePoint.Tenant
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Connecting to SharePoint site ", $global:SharePoint.Site, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
$site = Get-SharePointSite -Tenant $global:SharePoint.Tenant -Site $global:SharePoint.Site
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

Write-Host+

# cache capacities to improve performance
# ignore Trial and PPU capacities
Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Caching capacities from tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
$_capacities = Get-Capacities -Tenant $global:Fabric.Tenant
$capacities = $_capacities | Where-Object {
    $capacityDisplayName = $_.DisplayName
    -not ($global:Fabric.Capacities.Special | Where-Object { $capacityDisplayName -like $_ })
}

Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

# cache workspaces to improve performance
# ignore personal and app workspaces
Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Caching workspaces from tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
$workspaces = Get-Workspaces -Tenant $global:Fabric.Tenant | Where-Object { $_.type -eq "Workspace" -and $_.displayName -notin $global:Fabric.Workspaces.Applications }
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

# cache users to improve performance
Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Refreshing and caching users from tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Users -Quiet
$azureADUsers, $cacheError = Get-AzureAdUsers -Tenant $global:Fabric.Tenant -AsArray
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

# cache groups to improve performance
Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Refreshing and caching groups from tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Quiet
$azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
$azureADGroups = $azureADGroups | Where-Object { ![string]::IsNullOrEmpty($_.displayName) }
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint capacity list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Capacities.Name -ForegroundColor DarkGray, DarkBlue
    $capacityList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Capacities.Name
    $capacityListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show the sharepoint capacity list items
    $capacityListItems | Format-Table -Property @("ID", "Capacity Name", "SKU", "Region", "State", "Capacity ID")

#endregion GET SHAREPOINT LISTS

#region UPDATE SHAREPOINT CAPACITY LIST    

    # get sharepoint capacity list items' [internal] column names
    $_columnNamesCapacity = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList
    $_capacityNameCapacityColumn = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Capacity Name' }; $_columnNameCapacityCapacityName = $_capacityNameCapacityColumn.Name
    $_capacityIdCapacityColumn = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Capacity ID' }; $_columnNameCapacityCapacityId = $_capacityIdCapacityColumn.Name
    $_skuCapacityColumn = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Sku' }; $_columnNameCapacitySku = $_skuCapacityColumn.Name
    $_regionCapacityColumn = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Region' }; $_columnNameCapacityRegion = $_regionCapacityColumn.Name
    $_stateCapacityColumn = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'State' }; $_columnNameCapacityState = $_stateCapacityColumn.Name

    # for each fabric capacity that is not in the sharepoint capacity list, 
    # create a new sharepoint capacity list item
    $updatedCapacityList = $false
    $unlistedCapacities = $capacities | Where-Object {$_.displayName -notin $capacityListItems.'Capacity Name'}
    foreach ($unlistedCapacity in $unlistedCapacities) {
        $capacity = $capacities | Where-Object { $_.id -eq $unlistedCapacity.capacityId }
        $body = @{ 
            fields = @{ 
                $_columnNameCapacityCapacityName = $unlistedCapacity.displayName
                $_columnNameCapacityCapacityId = $unlistedCapacity.id
                $_columnNameCapacitySku = $unlistedCapacity.sku
                $_columnNameCapacityRegion = $unlistedCapacity.region
                $_columnNameCapacityState = $unlistedCapacity.state
            }
        }
        $_unlistedCapacityListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList -ListItemBody $body
        if ($_unlistedCapacityListItem){  
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $capacityList -ListItem $_unlistedCapacityListItem -Status -Value "Added capacity"               
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added capacity ", $_unlistedCapacityListItem.displayName, " from Fabric" -ForegroundColor DarkGray, DarkBlue, DarkGray
            $updatedCapacityList = $true
        }
    }

    # if the sharepoint capacity list was updated ...
    if ($updatedCapacityList) {
        # refresh the sharepoint capacity list items cache
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Capacities.Name -ForegroundColor DarkGray, DarkBlue
        $capacityListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        # show the updated sharepoint capacity list items
        $capacityListItems | Format-Table -Property $global:SharePointView.Capacity.Default 
    }

#endregion UPDATE SHAREPOINT CAPACITY LIST

#region UPDATE SHAREPOINT WORKSPACE LIST

    # get sharepoint workspace list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Workspaces.Name -ForegroundColor DarkGray, DarkBlue
    $workspaceList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Workspaces.Name
    $workspaceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show the sharepoint workspace list items
    $workspaceListItems | Format-Table -Property $global:SharePointView.Workspace.Default

    # get sharepoint workspace list items' [internal] column names
    $_columnNamesWorkspace = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList
    $_workspaceNameWorkspaceColumn = $_columnNamesWorkspace | Where-Object { $_.DisplayName -eq 'Workspace Name' }; $_columnNameWorkspaceWorkspaceName = $_workspaceNameWorkspaceColumn.Name
    $_workspaceIdWorkspaceColumn = $_columnNamesWorkspace | Where-Object { $_.DisplayName -eq 'Workspace ID' }; $_columnNameWorkspaceWorkspaceId = $_workspaceIdWorkspaceColumn.Name
    $_workspaceCapacityNameWorkspaceColumn = $_columnNamesWorkspace | Where-Object { $_.DisplayName -eq 'Capacity Name' }; $_columnNameWorkspaceCapacityName = "$($_workspaceCapacityNameWorkspaceColumn.Name)LookupId"

    # for each fabric workspace that is not in the sharepoint workspace list, 
    # create a new sharepoint workspace list item
    $updatedWorkspaceList = $false
    $unlistedWorkspaces = $workspaces | Where-Object {$_.displayName -notin $workspaceListItems.'Workspace Name'}
    foreach ($unlistedWorkspace in $unlistedWorkspaces) {
        $capacityListItem = $capacityListItems | Where-Object { $_.'Capacity ID' -eq $unlistedWorkspace.capacityId }
        $body = @{ 
            fields = @{ 
                $_columnNameWorkspaceWorkspaceName = $unlistedWorkspace.displayName
                $_columnNameWorkspaceWorkspaceId = $unlistedWorkspace.id
                $_columnNameWorkspaceCapacityName = $capacityListItem.id
            }
        }
        $_unlistedWorkspaceListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ListItemBody $body
        if ($_unlistedWorkspaceListItem){
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $_unlistedWorkspaceListItem -Status -Value "Added workspace"               
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added workspace ", $unlistedWorkspace.displayName, " from Fabric" -ForegroundColor DarkGray, DarkBlue, DarkGray
            $updatedWorkspaceList = $true
        }
    }

    # for each sharepoint workspace list item that is not in fabric, 
    # remove the sharepoint workspace list item
    $removeWorkspaceItems = $workspaceListItems | Where-Object {$_.'Workspace Name' -notin $workspaces.displayName -and [string]::IsNullOrEmpty($_.Command) }
    foreach ($removeWorkspaceItem in $removeWorkspaceItems) {
        Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ListItem $removeWorkspaceItem              
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed workspace item ", $removeWorkspaceItem.'Workspace Name', " from SharePoint list ", $workspaceList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
        Write-Log -Context $overwatchProductId -Target "WorkspaceSiteListItem" -Action "Remove" -Status "Success" -Message "Removed workspace $($removeWorkspaceItem.'Workspace Name') from SharePoint list $($workspaceList.DisplayName)" -EntryType "Information" -Force        
        $updatedWorkspaceList = $true
    }

    # if a workspace list item was added or removed, refresh the workspace list items
    if ($updatedWorkspaceList) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Workspaces.Name -ForegroundColor DarkGray, DarkBlue
        $workspaceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns  
        $workspaceListItems | Format-Table -Property $global:SharePointView.Workspace.Default
    }

    # for each sharepoint workspace list item, 
    # if the time when its status was updated is greater than $statusTimeToLiveInSeconds,
    # clear the sharepoint workspace list item's status
    $hadUpdate = $false
    $workspaceListItemsWithStatus = $workspaceListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($workspaceListItemsWithStatus.Count -gt 0) {
        foreach ($workspaceListItemWithStatus in $workspaceListItemsWithStatus) {
            if ( $workspaceListItemWithStatus.Status -notlike "Invalid*" -and $workspaceListItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$workspaceListItemWithStatus.Modified
                if ($sinceModified.TotalSeconds -gt $statusTimeToLiveInSeconds) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $workspaceListItemWithStatus.Status, " status for workspace ", $workspaceListItemWithStatus.'Workspace Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $workspaceListItemWithStatus.Status, " status for workspace ", $workspaceListItemWithStatus.'Workspace Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadUpdate = $true
    }

#endregion UPDATE SHAREPOINT WORKSPACE LIST   

#region PROCESS WORKSPACE COMMANDS

    # auto-provision groups initialization
    $autoProvisionGroups = @()

    # get the sharepoint workspace list items that have a pending command
    $hadCommand = $false
    $workspaceListItemsWithCommand = $workspaceListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command)}
    if ($workspaceListItemsWithCommand.Count -gt 0) {
        $workspaceListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($updatedWorkspaceList -or $hadUpdate)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    foreach ($workspaceListItemWithCommand in $workspaceListItemsWithCommand) {

        if ($null -eq $workspaceListItemWithCommand.Command -or $workspaceListItemWithCommand.Command -notin @("Create", "Rename")) { continue }

        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $workspaceListItemWithCommand.Command, " workspace ", $workspaceListItemWithCommand.'Workspace Name'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

        $workspace = Get-Workspace -Tenant $global:Fabric.Tenant -Name $workspaceListItemWithCommand.'Workspace Name'
        if (!$workspace) {

            # workspace id in sharepoint list item is null
            # if the workspace id is not null, the workspace has already been created
            if ([string]::IsNullOrEmpty($workspaceListItemWithCommand.'Workspace ID')) {

                #region CREATE WORKSPACE

                    if ($workspaceListItemWithCommand.Command -eq "Create") {

                        # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Creating workspace: ", $workspaceListItemWithCommand.'Workspace Name' -ForegroundColor DarkGray, DarkBlue
                        $workspace = New-Workspace -Tenant $global:Fabric.Tenant -Name $workspaceListItemWithCommand.'Workspace Name'
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Created workspace ", $workspace.displayName -ForegroundColor DarkGray, DarkBlue
                        Write-Log -Context $overwatchProductId -Target "Workspace" -Action "New" -Status "Success" -Message "Created workspace $($workspaceListItemWithCommand.'Workspace Name')" -EntryType "Information" -Force                        
                        
                        if ($workspace) {

                            # add sharepoint list item Workspace ID
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Workspace ID" -Value $workspace.id
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Created workspace"   
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   

                            #region AUTOPROVISION GROUPS
                            
                                # auto-provision groups
                                $autoProvisionGroups = @()
                                $autoProvisionGroups += @{ workspaceName = $workspace.displayName; groupName = "$($workspace.displayName) - Read Only"; role = "Viewer" }
                                $autoProvisionGroups += @{ workspaceName = $workspace.displayName; groupName = "$($workspace.displayName) - Workspace Admin"; role = "Admin" }
                                $autoProvisionGroups += @{ workspaceName = $workspace.displayName; groupName = "$($workspace.displayName) - Data Contributors"; role = "Contributor" }
                                $autoProvisionGroups += @{ workspaceName = $workspace.displayName; groupName = "Data Curators"; role = "Member" }
                                $autoProvisionGroups += @{ workspaceName = $workspace.displayName; groupName = "Fabric Admin"; role = "Admin" }                                

                            #endregion AUTOPROVISION GROUPS                                
                            
                        }
                        else {
                            
                            # failed to create the workspace
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Create workspace failed"   
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   
                            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to create workpace ", $($workspace.displayName) -ForegroundColor DarkRed, DarkBlue 
                            Write-Log -Context $overwatchProductId -Target "Workspace" -Action "New" -Status "Failure" -Message "Failed to create workspace $($workspaceListItemWithCommand.'Workspace Name')" -EntryType "Error" -Force

                        }    
                    }

                #endregion CREATE WORKSPACE

            }

            # workspace id in sharepoint list item is NOT null
            else {

                #region VALIDATE WORKSPACE ID

                    try{

                        # see if workspace id in sharepoint list item is a valid workspace id (guid)
                        $workspace = Get-Workspace -Tenant $global:Fabric.Tenant -Id $workspaceListItemWithCommand.'Workspace ID'

                    }
                    catch {

                        # workspace id in sharepoint list item is NOT a valid workspace id
                        # TODO: this sharepoint list item is invalid
                        $workspace = $null
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Workspace ", $workspaceListItemWithCommand.'Workspace Name', ": ", "not found" -ForegroundColor DarkYellow
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Invalid Workspace ID ", $workspaceListItemWithCommand.'Workspace ID' -ForegroundColor DarkRed
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Status" -Value "Invalid Workspace ID"   
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   
                        Write-Log -Context $overwatchProductId -Target "Workspace" -Action "Get" -Status "Failure" -Message "Workspace $($workspaceListItemWithCommand.'Workspace Name') not found" -EntryType "Error" -Force
                    }

                #endregion VALIDATE WORKSPACE ID                    

                #region RENAME WORKSPACE
                
                    if ($workspace) {

                        if ($workspaceListItemWithCommand.Command -eq "Rename") {

                            # the workspace id in sharepoint list item is a valid workspace id
                            # but the workspace name doesn't match what's in the sharepoint list item
                            # so this is a RENAME operation
                            $oldWorkspaceDisplayName = $workspace.displayName
                            $newWorkspaceDisplayName = $workspaceListItemWithCommand.'Workspace Name'
                            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Renaming workspace ", $oldWorkspaceDisplayName, " to ", $newWorkspaceDisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

                            # rename the workspace
                            $workspace = Update-Workspace -Tenant $global:Fabric.Tenant -Workspace $workspace -Name $newWorkspaceDisplayName
                            
                            if ($workspace.displayName -eq $newWorkspaceDisplayName) {

                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Renamed workspace from ", $oldWorkspaceDisplayName, " to ", $newWorkspaceDisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue  
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Renamed workspace"   
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "  
                                Write-Log -Context $overwatchProductId -Target "Workspace" -Action "Rename" -Status "Success" -Message "Renamed workspace $($workspaceListItemWithCommand.'Workspace Name')" -EntryType "Information" -Force

                            }
                            else {

                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to rename workspace: ", $workspace.displayName -ForegroundColor DarkRed
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Rename workspace failed"   
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "  
                                Write-Log -Context $overwatchProductId -Target "Workspace" -Action "Rename" -Status "Failure" -Message "Failed to rename workspace $($workspaceListItemWithCommand.'Workspace Name')" -EntryType "Error" -Force

                            }
                        }
                    }

                #endregion RENAME WORKSPACE                    

            }
        }

    #region UPDATE SHAREPOINT WORKSPACE LIST
    
    #region ASSIGN CAPACITY

        if ($workspace -and $workspaceListItemWithCommand.Command -eq "Create") {
            # workspace has a capacity id assigned in fabric
            if ($workspace.capacityId) {
                $capacity = Get-Capacity -Tenant $global:Fabric.Tenant -Id $workspace.capacityId -Capacities $capacities
                if ($capacity) {
                    if ([string]::IsNullOrEmpty($workspaceListItemWithCommand.'Capacity Name')) { 
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Capacity Name not specified"  -ForegroundColor DarkYellow
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Using capacity ", $($capacity.displayName), " assigned to workpace" -ForegroundColor DarkGray, DarkBlue, DarkGray
                        # update the capacity name field in the sharepoint list item
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Capacity Name" -Value $capacity.displayName                          
                    }    
                } 
            }
            # workspace has not been assigned a capacity
            else {
                # validate the capacity name field from the sharepoint list item
                $capacity = Get-Capacity -Tenant $global:Fabric.Tenant -Name $workspaceListItemWithCommand.'Capacity Name' -Capacities $capacities
                if ($capacity) {
                    # assign capacity to workspace
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Assigning capacity ", $($Capacity.displayName), " to workspace ", $($workspace.displayName) -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                    $workspace = Set-WorkspaceCapacity -Tenant $global:Fabric.Tenant -Workspace $Workspace -Capacity $Capacity
                    if ($workspace) {
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Assigned capacity ", $($Capacity.displayName), " to workspace ", $($workspace.displayName) -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Assigned capacity"  
                        Write-Log -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Success" -Message "Assigned capacity $($Capacity.displayName) to workspace $($workspace.displayName)" -EntryType "Information" -Force                  
                    }
                    else {
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to assign capacity ", $($Capacity.displayName), " to workspace ", $($workspace.displayName) -ForegroundColor DarkRed
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Assign capacity failed" 
                        Write-Log -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Failure" -Message "Failed to assign capacity $($Capacity.displayName) to workspace $($workspace.displayName)" -EntryType "Error" -Force 
                    }
                }
                else {
                    # the capacity name field in the sharepoint list item is NOT valid
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Capacity ", $($capacity.displayName), "NOT FOUND" -ForegroundColor DarkRed
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Invalid capacity"   
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " " 
                    Write-Log -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Error" -Message "Capacity $($Capacity.displayName) was not found" -EntryType "Error" -Force 
                }
            }
        }

    #endregion ASSIGN CAPACITY

}

#endregion PROCESS WORKSPACE COMMANDS

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint user list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users.Name -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users.Name
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint user list items
    $userListItems | Format-Table -Property $global:SharePointView.User.Default

#endregion GET SHAREPOINT LISTS    

#region UPDATE SHAREPOINT USER LIST

    # update Sharepoint list item User ID when blank
    # this is done here b/c later updates rely on list item User ID
    # lookup azure AD user with list item User Email
    # no action if both list item User ID and User Email are blank
    $hadUpdate = $false
    foreach ($userListItem in $userListItems) {
        if ([string]::IsNullOrEmpty($userListItem.'User ID') -and ![string]::IsNullOrEmpty($userListItem.'User Email')) {
            $azureADUser = $azureADUsers | Where-Object { $_.mail -eq $userListItem.'User Email'}
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User ID" -Value $azureADUser.id
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Update user"
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Update ", "User ID", " for user ", $userListItem.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            $hadUpdate = $true
        }
    }

    # refresh sharepoint user list items
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $userList -ForegroundColor DarkGray, DarkBlue
        $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $userListItems | Format-Table -Property $global:SharePointView.User.Default
    }

    function Repair-SharePointUserListItems {

        $hadUpdate = $false

        # get user ids from sharepoint user list items
        $listedUserIds = @()
        foreach ($userListItem in $userListItems) {
            $listedUserIds += $userListItem.'User ID'
        }

        # get user [internal] column names
        $_columnNames = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $userList
        $_userNameColumn = $_columnNames | Where-Object { $_.DisplayName -eq 'User Name' }; $_columnNameUserName = $_userNameColumn.Name
        $_emailColumn = $_columnNames | Where-Object { $_.DisplayName -eq 'User Email' }; $_columnNameEmail = $_emailColumn.Name
        $_userIdColumn = $_columnNames | Where-Object { $_.DisplayName -eq 'User ID' }; $_columnNameUserId = $_userIdColumn.Name
        $_accountStatusColumn = $_columnNames | Where-Object { $_.DisplayName -eq 'Account Status' }; $_columnNameAccountStatus = $_accountStatusColumn.Name
        $_externalUserStateColumn = $_columnNames | Where-Object { $_.DisplayName -eq 'External User State' }; $_columnNameExternalUserState = $_externalUserStateColumn.Name

        # update sharepoint user list items with meta from Azure AD
        $hadUpdate = $false
        $listedAzureADUsers = $azureADUsers | Where-Object { $_.id -in $listedUserIds }
        foreach ($listedAzureADUser in $listedAzureADUsers) {

            $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $listedAzureADUser.id
            $userListItem = $userListItems | Where-Object { $_.'User ID' -eq $azureADUser.id }

            # update sharepoint list item when User Email is null or empty
            if ([string]::IsNullOrEmpty($userListItem.'User Email') -and ![string]::IsNullOrEmpty($azureADUser.mail)) {        
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User Email" -Value $azureADUser.mail
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Update user"
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated ", "User Email", " for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                $hadUpdate = $true
            }    

            # remove accounts that don't have an email address
            # this is a proxy for checking the account types
            # if $azureADUser.mail is null, this isn't an account to be tracking
            if ([string]::IsNullOrEmpty($azureADUser.mail)) {
                Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ListItem $userListItem              
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed user item ", $userListItem.'User Name', " from SharePoint list ", $userList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                Write-Log -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Success" -Message "Removed user $($userListItem.'User Name') from SharePoint list $($userList.DisplayName)" -EntryType "Information" -Force        
                $hadUpdate = $true
            }        

            # update sharepoint list item when $azureADUser.accountenabled does not match Account Status
            if ($($userListItem.'Account Status' -eq "Enabled") -ne $azureADUser.accountEnabled) {
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value $($azureADUser.accountEnabled ? "Enabled" : "Disabled")   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Update user"
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated ", "Account Status", " for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue           
                $hadUpdate = $true
            }

            # update sharepoint list item when $azureADUser.externalUserState does not match the Azure AD user's externalUserState propery
            # if ((![string]::IsNullOrEmpty($userListItem.'External User State') -and ![string]::IsNullOrEmpty($azureADUser.externalUserState) -and $userListItem.'External User State' -ne $azureADUser.externalUserState) -or [string]::IsNullOrEmpty($userListItem.'External User State')) {
                # if ($azureADUser.userType -eq "Guest") {
                    $externalUserState = $azureADUser.userPrincipalName -match "#EXT#@" ? $azureADUser.externalUserState : "Internal"
                    if ($externalUserState -eq "Accepted" -and ($azureADUser.externalUserStateChangeDateTime - [datetime]::Now) -gt $global:SharePoint.Lists.Users.ShowAcceptedExpiry) {
                        $externalUserState = "External"
                    }
                    if ($userListItem.'External User State' -ne $externalUserState) {
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "External User State" -Value $externalUserState
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Update user"
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated ", "External User State", " for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                        $hadUpdate = $true
                    }
                # }       
            # }   

        }

        # for Azure AD users not in the sharepoint user list 
        # create a new sharepoint user list item 
        $hadUpdate = $false
        $unlistedUsers = $azureADUsers | Where-Object { $_.id -and $_.id -notin $listedUserIds -and ![string]::IsNullOrEmpty($_.mail) }
        foreach ($unlistedUser in $unlistedUsers) {
            # need full Azure AD user object
            $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $unlistedUser.id
            if (!$azureADGroup.error) {        
                $body = @{ fields = @{} }
                $body.fields += @{ $_columnNameUserName = $azureADUser.displayName }
                $body.fields += @{ $_columnNameEmail = $azureADUser.mail.ToLower() }
                $body.fields += @{ $_columnNameAccountStatus = $azureADUser.accountEnabled ? "Enabled" : "Disabled" }
                $body.fields += @{ $_columnNameExternalUserState = $azureADUser.externalUserState }
                $body.fields += @{ $_columnNameUserId = $azureADUser.id }
                $unlistedUserListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ListItemBody $body
                if ($unlistedUserListItem){
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $unlistedUserListItem -Status -Value "Added user"               
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added user ", $azureADUser.mail.ToLower(), " from Azure AD" -ForegroundColor DarkGray, DarkBlue, DarkGray
                }
                else {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Add user failed" 
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to add user ", $azureADUser.mail.ToLower(), " from Azure AD" -ForegroundColor DarkRed            
                }
                $hadUpdate = $true            
            }
            
        }

        return $hadUpdate

    }

    Repair-SharePointUserListItems

    # for each sharepoint user list item, 
    # if the time when its status was updated is greater than $statusTimeToLiveInSeconds,
    # clear the sharepoint user list item's status
    $hadUpdate = $false
    $userListItemsWithStatus = $userListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($userListItemsWithStatus.Count -gt 0) {
        foreach ($userListItemWithStatus in $userListItemsWithStatus) {
            if ( $userListItemWithStatus.Status -notlike "Invalid*" -and $userListItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$userListItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared status for user ", $userListItemWithStatus.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $userListItemWithStatus.Status, " status for user ", $userListItemWithStatus.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadUpdate = $true
    }    

    # refresh sharepoint user list items
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $userList -ForegroundColor DarkGray, DarkBlue
        $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $userListItems | Format-Table -Property $global:SharePointView.User.Default
    }    

#endregion UPDATE SHAREPOINT USER LIST  

#region PROCESS USER COMMANDS

    # get the sharepoint user list items that have a pending command
    $hadCommand = $false
    $userListItemsWithCommand = $userListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    if ($userListItemsWithCommand.Count -gt 0) {
        $userListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($hadUpdate)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    $updatedAzureADUsers = $false
    foreach ($userListItem in $userListItems) {

        if ($null -eq $userListItem.Command -or $userListItem.Command -notin @("Rename", "Invite", "Enable", "Disable")) { continue }

        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $userListItem.Command, " user ", $userListItem.'User Email'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

        # get Azure AD user
        $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $userListItem.'User ID'
        if ($azureADUser) {

            # enable/disable azureADUser account 
            if ($userListItem.Command -in @("Enable", "Disable")) {
                if ($userListItem.Command -eq "Enable") {
                    Enable-AzureADUser -Tenant $global:Fabric.Tenant -User $azureADUser
                    Write-Log -Context $overwatchProductId -Target "User" -Action "Enable" -Status "Success" -Message "Enabled account for user $($azureADUser.displayName)" -EntryType "Information" -Force
                }
                elseif ($userListItem.Command -eq "Disable") {
                    Disable-AzureADUser -Tenant $global:Fabric.Tenant -User $azureADUser
                    Write-Log -Context $overwatchProductId -Target "User" -Action "Disable" -Status "Success" -Message "Disabled account for user $($azureADUser.displayName)" -EntryType "Information" -Force
                }
                # need full Azure AD user object
                $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $azureADUser.mail
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value ($azureADUser.accountEnabled ? "Enabled" : "Disabled")
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Command" -Value " "
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "User ", $azureADUser.mail, " ", $($azureADUser.accountEnabled ? "Enabled" : "Disabled") -ForegroundColor DarkGray, DarkBlue, DarkGray, ($azureADUser.accountEnabled? "DarkGreen" : "DarkRed") 
                $updatedAzureADUsers = $true

            }

            # rename azureADuser account when azureADUser.displayName is different from the sharepoint user list item's User Name
            if ($userListItem.Command -eq "Rename" -and $userListItem.'User Name' -ne $azureADUser.displayName) {
                $currentAzureADUserName = $azureADUser.displayName
                $userListItemUserName = $userListItem.'User Name'
                $azureADUser = Update-AzureADUserNames -Tenant $global:Fabric.Tenant -User $azureADUser -DisplayName $userListItemUserName
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Renamed user"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Command" -Value " "             
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Renamed `"User Name`" from ", $azureADUser.mail, " to ", $azureADUser.displayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
                Write-Log -Context $overwatchProductId -Target "User" -Action "Rename" -Status "Success" -Message "Renamed `"User Name`" from $currentAzureADUserName to $($azureADUser.displayName)" -EntryType "Information" -Force             
            }
            $updatedAzureADUsers = $true

        }
        else {

            # send invitation to newly added user
            if ($userListItem.Command -eq "Invite") {
                $invitation = Send-AzureADInvitation -Tenant $global:Fabric.Tenant -Email $userListItem.'User Email' -DisplayName $userListItem.'User Name'
                $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $invitation.invitedUser.id 
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName 'User Email' -Value $azureADUser.mail
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName 'External User State' -Value $azureADUser.externalUserState
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value "Enabled"
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User ID" -Value $azureADUser.id
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Invited user" 
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Command" -Value " " 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Invited user ", $azureADUser.mail, " to tenant ", $global:Fabric.Tenant -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
                Write-Log -Context $overwatchProductId -Target "User" -Action "Invite" -Status "Success" -Message "Invited $($azureADUser.displayName) to tenant $($global:Fabric.Tenant)" -EntryType "Information" -Force          
            }
            $updatedAzureADUsers = $true

        }

    }

#endregion PROCESS USER COMMANDS

#region REFRESH AZURE AD USER CACHE

    # if any Azure AD user was created/updated/removed,
    # regresh the Overwatch Azure AD user cache
    if ($updatedAzureADUsers) {
        Write-Host+
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing ", "Azure AD Users" -ForegroundColor DarkGray, DarkBlue
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Users -Quiet
        $azureADUsers, $cacheError = Get-AzureAdUsers -Tenant $global:Fabric.Tenant -AsArray        
        Write-Log -Context $overwatchProductId -Target "Users" -Action "Refresh" -Status "Success" -Message "Refreshed Azure AD user cache" -EntryType "Information" -Force
    }

#region REFRESH AZURE AD USER CACHE

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint user list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users.Name -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users.Name
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups.Name -ForegroundColor DarkGray, DarkBlue
    $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups.Name
    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint group list items
    $groupListItems | Format-Table -Property $global:SharePointView.Group.Default

    # get sharepoint group list items' [internal] column names
    $_columnNamesGroup = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $groupList
    $_groupNameGroupColumn = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnNameGroupGroupName = $_groupNameGroupColumn.Name
    $_groupIdGroupColumn = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Group ID' }; $_columnNameGroupGroupId = $_groupIdGroupColumn.Name
    $_statusGroupColumn = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Status' }; $_columnNameGroupStatus = $_statusGroupColumn.Name

#endregion GET SHAREPOINT LISTS

#region UPDATE SHAREPOINT GROUP LIST    


    $hadUpdate = $false
    
    # for each Azure AD group not in the sharepoint group list 
    # create a new sharepoint group list item 
    foreach ($_azureADGroup in $azureADGroups) {
        $azureADGroup = Get-AzureADGroup -Tenant $global:Fabric.Tenant -Id $_azureADGroup.id
        if (!$azureADGroup.error) {
            $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $azureADGroup.displayName}
            if (!$groupListItem) {
                $body = @{
                    fields = @{
                        $_columnNameGroupGroupName = $azureADGroup.displayName
                        $_columnNameGroupGroupId = $azureADGroup.id
                        $_columnNameGroupStatus = "Added group"
                    }
                }
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItemBody $body 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added group ", $azureADGroup.displayName, " to SharePoint list ", $groupList.Name -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue    
                $hadUpdate = $true   
            }
        }
    }        
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Groups" -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $hadUpdate = $false
    }  

    # for each sharepoint group list item,
    # if the group name is missing, add it
    # lookup group with list item Group ID
    $groupListItemsWithMissingName = $groupListItems | Where-Object { [string]::IsNullOrEmpty($_.'Group ID') -and [string]::IsNullOrEmpty($_.Command) }
    if ($groupListItemsWithMissingName.Count -gt 0) {
        foreach ($groupListItemWithMissingName in $groupListItemsWithMissingName) {
            $azureADGroup = $azureADGroups | Where-Object { $_.id -eq $groupListItemWithMissingName.'Group ID' }
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItemWithMissingName -ColumnDisplayName "Group Name" -Value $azureADGroup.displayName
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItemWithMissingName -Status -Value "Repaired group"
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Repaired ", $groupListItemWithMissingName.'Group Name', " group name" -ForegroundColor DarkGray, DarkBlue, DarkGray
            }
        $hadUpdate = $true
    }    
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Groups" -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $hadUpdate = $false
    }         

    # for each sharepoint group list item,
    # if the group id is missing, add it
    # lookup group with list item Group Name
    $groupListItemsWithMissingId = $groupListItems | Where-Object { [string]::IsNullOrEmpty($_.'Group ID') -and [string]::IsNullOrEmpty($_.Command)}
    if ($groupListItemsWithMissingId.Count -gt 0) {
        foreach ($groupListItemWithMissingId in $groupListItemsWithMissingId) {
            $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $groupListItemWithMissingId.'Group Name' }
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItemWithMissingId -ColumnDisplayName "Group ID" -Value $azureADGroup.id
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItemWithMissingId -Status -Value "Repaired group"
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Repaired ", $groupListItemWithMissingId.'Group Name', " group id" -ForegroundColor DarkGray, DarkBlue, DarkGray
            }
        $hadUpdate = $true
    }   
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Groups" -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $hadUpdate = $false
    }          

    # for each sharepoint group list item that is not in fabric, 
    # remove the sharepoint group list item
    $removeGroupItems = $groupListItems | Where-Object {$_.'Group Name' -notin $azureADGroups.displayName -and [string]::IsNullOrEmpty($_.Command) }
    foreach ($removeGroupItem in $removeGroupItems) {
        $removedGroupName = ![string]::IsNullOrEmpty($removeGroupItem.'Group Name') ? $removeGroupItem.'Group Name' : "<group name is blank>"
        Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ListItem $removeGroupItem              
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed group ", $removedGroupName, " from SharePoint list ", $groupList.name -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
        $hadUpdate = $true
    }
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Groups" -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $hadUpdate = $false
    }         

    # for each sharepoint group list item, 
    # if the time when its status was updated is greater than $statusTimeToLiveInSeconds,
    # clear the sharepoint group list item's status    
    $groupListItemsWithStatus = $groupListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($groupListItemsWithStatus.Count -gt 0) {
        foreach ($groupItemWithStatus in $groupListItemsWithStatus) {
            if ( $groupItemWithStatus.Status -notlike "Invalid*" -and $groupItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$groupItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $groupItemWithStatus.Status, " status for group ", $groupListItemsWithStatus.'Group Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $groupItemWithStatus.Status, " status for group ", $groupListItemsWithStatus.'Group Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadUpdate = $true
    }

    # if the sharepoint group list was updated, refresh the sharepoint group list
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Groups.Name -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList
        $groupListItems | Format-Table -Property $global:SharePointView.Group.Default
    }    

#endregion UPDATE SHAREPOINT GROUP LIST

#region PROCESS GROUP COMMANDS

    # get the sharepoint group list items that have a pending command
    $hadCommand = $false
    $groupListItemsWithCommand = @()
    $groupListItemsWithCommand += $groupListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    foreach ($autoProvisionGroup in $autoProvisionGroups) {
        $groupListItemsWithCommand += [PSCustomObject]@{
            'Group Name' = $autoProvisionGroup.groupName
            Command = "Create"
        }
    }
    if ($groupListItemsWithCommand.Count -gt 0) {
        $groupListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($hadUpdate)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    $updatedAzureADGroups = $false
    foreach ($groupListItem in $groupListItemsWithCommand) {

        if ($null -eq $groupListItem.Command -or $groupListItem.Command -notin @("Create", "Delete")) { 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupListItem.Command, " group ", $groupListItem.'Group Name'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Unsupported command" -ForegroundColor DarkRed
            continue 
        }

        # get Azure AD group
        $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $groupListItem.'Group Name' }

        # create a new mail-enabled security group
        # update the sharepoint group list item
        if ($groupListItem.Command -eq "Create" -and !$azureADGroup) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupListItem.Command, " group ", $groupListItem.'Group Name'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue            
            $_newMailEnabledSecurityGroup = New-MailEnabledSecurityGroup -Name $groupListItem.'Group Name'

            if (![string]::IsNullOrEmpty($groupListItem.Id)) {
                # $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Group Name" -Value $azureADGroup.displayName
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Group ID" -Value $_newMailEnabledSecurityGroup.ExternalDirectoryObjectId
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -Status -Value "Created group"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Command" -Value " " 
            }

            # this is the path for auto-provisioned groups
            else {
                $body = @{ 
                    fields = @{ 
                        $_columnNameGroupGroupName = $azureADGroup.displayName
                        $_columnNameGroupGroupID = $azureADGroup.id
                        $_columnNameGroupStatus = "Created group"
                    }
                }
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ListItemBody $body                
            }

            Write-Log -Context $overwatchProductId -Target "Group" -Action "New" -Status "Success" -Message "Created new group $($groupListItem.'Group Name')" -EntryType "Information" -Force
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Created group ", $groupListItem.'Group Name' -ForegroundColor DarkGray, DarkBlue            
            $updatedAzureADGroups = $true
        }

        $workspaceRoleAssignments = @()
        foreach ($workspace in $workspaces) {
            $workspaceRoleAssignments += Get-WorkspaceRoleAssignments -Tenant $global:Fabric.Tenant -Workspace $workspace | Where-Object { $_.principal.type -eq "Group"}
        }

        # delete a mail-enabled security group
        # delete the sharepoint group list item
        if ($groupListItem.Command -eq "Delete" -and $azureADGroup) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupListItem.Command, " group ", $groupListItem.'Group Name'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue  
            if ($groupListItem.'Group ID' -notin $workspaceRoleAssignments.principal.id) {
                Remove-MailEnabledSecurityGroup -Group $groupListItem.'Group Name' 
                Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItem $groupListItem
                Write-Log -Context $overwatchProductId -Target "Group" -Action "Delete" -Status "Success" -Message "Deleted group $($groupListItem.'Group Name')" -EntryType "Information" -Force
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Deleted group ", $groupListItem.'Group Name' -ForegroundColor DarkGray, DarkBlue
                $updatedAzureADGroups = $true
            }
            else {
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -Status -Value "Blocked"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Command" -Value " "                 
                Write-Log -Context $overwatchProductId -Target "Group" -Action "Delete" -Status "Failure" -Message "Unable to delete group $($groupListItem.'Group Name') b/c of a workspace role assignment dependency" -EntryType "Information" -Force
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Unable to delete group ", $groupListItem.'Group Name', " b/c of a workspace role assignment dependency" -ForegroundColor DarkGray, DarkBlue , DarkGray               
            }
        }

    }   

#endregion PROCESS GROUP COMMANDS

#region REFRESH AZURE AD GROUP CACHE

    if ($updatedAzureADGroups) {
        Write-Host+
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing ", "Azure AD Groups" -ForegroundColor DarkGray, DarkBlue
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Quiet
        $azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
        Write-Log -Context $overwatchProductId -Target "Groups" -Action "Refresh" -Status "Success" -Message "Refreshed Azure AD group cache" -EntryType "Information" -Force
    }

#endregion REFRESH AZURE AD USER CACHE

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint user list and list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users.Name -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users.Name
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group list and list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups.Name -ForegroundColor DarkGray, DarkBlue
    $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups.Name
    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group membership list and list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.GroupMembership.Name -ForegroundColor DarkGray, DarkBlue
    $groupMembershipList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.GroupMembership.Name
    $groupMembershipListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint group membership list items
    $groupMembershipListItems | Format-Table -Property $global:SharePointView.GroupMembership.Default

    # get sharepoint group membership list items' [internal] column names
    $_columnNamesGroupMembership = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList
    $_groupNameGroupMembershipColumn = $_columnNamesGroupMembership | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnNameGroupMembershipGroupName = "$($_groupNameGroupMembershipColumn.Name)LookupId"
    $_userEmailGroupMembershipColumn = $_columnNamesGroupMembership | Where-Object { $_.DisplayName -eq 'User Email' }; $_userEmailGroupMembershipGroupName = "$($_userEmailGroupMembershipColumn.Name)LookupId"

#endregion GET SHAREPOINT LISTS   

#region UPDATE GROUP MEMBERSHIP SHAREPOINT LIST

    # create a new sharepoint list item for any Azure AD group member not in the Fabric Group Membership sharepoint list 
    $unlistedMembers = @()
    $hadUpdate = $false
    # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Comparing Azure AD group membership with SharePoint list ", $groupMembershipList.DisplayName -ForegroundColor DarkGray, DarkBlue
    foreach ($_azureADGroup in $azureADGroups) {
        $azureADGroup = Get-AzureADGroup -Tenant $global:Fabric.Tenant -Id $_azureADGroup.id    
        foreach ($member in $azureADGroup.members) {
            $userListItem = $userListItems | Where-Object { $_.'User Email' -eq $member.mail}
            $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $azureADGroup.displayName}
            $groupMembershipListItem = $groupMembershipListItems | Where-Object { $_.'Group Name' -eq $azureADGroup.displayName -and $_.'User Email' -eq $member.mail}
            if (!$groupMembershipListItem -and $userListItem) {
                $body = @{
                    fields = @{
                        $_columnNameGroupMembershipGroupName = $groupListItem.id
                        $_userEmailGroupMembershipGroupName = $userListItem.id
                    }
                }
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding ", $($azureADGroup.displayName), " | ", $userListItem.'User Email', " from Azure AD to SharePoint list ", $groupMembershipList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkBlue, DarkBlue, DarkGray, DarkBlue
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupMembershipList -ListItemBody $body
                $hadUpdate = $true
            }
        }
    }
    
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.GroupMembership.Name -ForegroundColor DarkGray, DarkBlue
        $groupMembershipListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $groupMembershipListItems | Format-Table -Property $global:SharePointView.GroupMembership.Default
    }

    $hadUpdate = $false
    $groupMembershipListItemsWithStatus = $groupMembershipListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($groupMembershipListItemsWithStatus.Count -gt 0) {
        foreach ($groupMembershipListItemWithStatus in $groupMembershipListItemsWithStatus) {
            $groupMembershipPath = "$($groupMembershipListItemWithStatus.'Group Name')\$($groupMembershipListItemWithStatus.'User Email')"
            if ( $groupMembershipListItemWithStatus.Status -notlike "Invalid*" -and $groupMembershipListItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$groupMembershipListItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $groupMembershipListItemWithStatus.Status, " status for group membership ", $groupMembershipPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $groupMembershipListItemWithStatus.Status, " status for group membership ", $groupMembershipPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadUpdate = $true
    }

#endregion UPDATE GROUP MEMBERSHIP SHAREPOINT LIST  

#region PROCESS GROUP MEMBERSHIP COMMANDS

    $updatedAzureADGroups = $false

    # get the sharepoint group membership list items that have a pending command
    $hadCommand = $false
    $groupMembershipListItemsWithCommand = $groupMembershipListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    if ($groupMembershipListItemsWithCommand.Count -gt 0) {
        $groupMembershipListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($hadUpdate)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    foreach ($groupMembershipListItem in $groupMembershipListItemsWithCommand) {

        if ($null -eq $groupMembershipListItem.Command -or $groupMembershipListItem.Command -notin @("Add", "Remove")) { continue }

        $userListItem = $userListItems | Where-Object { $_.'User Email' -eq $groupMembershipListItem.'User Email'}
        $groupWorkspace = $workspaces | Where-Object {$_.displayName -in ($groupMembershipListItem.'Group Name' -split " - " )[0]}

        # get Azure AD user
        $azureADUser = $azureADUsers | Where-Object { $_.mail -eq $groupMembershipListItem.'User Email' }
        if (!$azureADUser) {
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -Status -Value "Invalid user"   
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -ColumnDisplayName "Command" -Value " "   
            continue      
        }

        # create a piped path string to use for group membership 
        # format:  <workspace> | <user email>  
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupMembershipListItem.Command, " user ", $groupMembershipListItem.'User Email', " to group ", $groupMembershipListItem.'Group Name', " in workspace ", $groupWorkspace.displayName  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue, DarkGray, DarkBlue, DarkGray, DarkBlue

        # get Azure AD group
        $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $groupMembershipListItem.'Group Name' }
        if (!$azureADGroup) {
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -Status -Value "Invalid group"   
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -ColumnDisplayName "Command" -Value " "         
            continue
        }

        # add user to group
        if ($groupMembershipListItem.Command -eq "Add") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding user ", $groupMembershipListItem.'User Email', " to group ", $($groupMembershipListItem.'Group Name')   -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            Add-MailEnabledSecurityGroupMember -Group $groupMembershipListItem.'Group Name' -Member $groupMembershipListItem.'User Email'
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -Status -Value "Added user"   
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -ColumnDisplayName "Command" -Value " " 
            Write-Log -Context $overwatchProductId -Target "GroupMembership" -Action "Add" -Status "Success" -Message "Added user $($groupMembershipListItem.'User Email') to group $($groupMembershipListItem.'Group Name')" -EntryType "Information" -Force 
            $updatedAzureADGroups = $true        
        }

        # remove user from group
        if ($groupMembershipListItem.Command -eq "Remove") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing user ", $groupMembershipListItem.'User Email', " from group ", $($groupMembershipListItem.'Group Name')   -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            Remove-MailEnabledSecurityGroupMember -Group $groupMembershipListItem.'Group Name' -Member $groupMembershipListItem.'User Email'
            Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupMembershipList -ListItem $groupMembershipListItem
            Write-Log -Context $overwatchProductId -Target "GroupMembership" -Action "Remove" -Status "Success" -Message "Removed user $($groupMembershipListItem.'User Email') from group $($groupMembershipListItem.'Group Name')" -EntryType "Information" -Force 
            $updatedAzureADGroups = $true
        }    

    }

#endregion PROCESS GROUP MEMBERSHIP COMMANDS

#region REFRESH AZURE AD GROUP CACHE

    if ($updatedAzureADGroups) {
        Write-Host+
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing ", "Azure AD Groups" -ForegroundColor DarkGray, DarkBlue
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Quiet
        $azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
        Write-Log -Context $overwatchProductId -Target "Groups" -Action "Refresh" -Status "Success" -Message "Refreshed Azure AD group cache" -EntryType "Information" -Force
    }

#endregion REFRESH AZURE AD USER CACHE

Write-Host+

#region GET WORKSPACE ROLE ASSIGNMENTS LISTS

    # get sharepoint workspace list and its listitems
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Workspaces.Name -ForegroundColor DarkGray, DarkBlue
    $workspaceList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Workspaces.Name
    $workspaceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group list and its listitems
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups.Name -ForegroundColor DarkGray, DarkBlue
    $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups.Name
    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint workspace role assignment list and its listitems
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.WorkspaceRoleAssignments.Name -ForegroundColor DarkGray, DarkBlue
    $workspaceRoleAssignmentsList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.WorkspaceRoleAssignments.Name
    $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint workspace role assignment list items
    $workspaceRoleAssignmentsListItems | Format-Table -Property $global:SharePointView.WorkspaceRoleAssignment.Default

    # get sharepoint workspace role assignment list items' [internal] column names
    $_columnNamesWorkspaceRoleAssignments = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList
    $_workspaceNameWorkspaceRoleAssignmentsColumn = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Workspace Name' }; $_columnNameWorkspaceRoleAssignmentsWorkspaceName = "$($_workspaceNameWorkspaceRoleAssignmentsColumn.Name)LookupId"
    $_groupWorkspaceRoleAssignmentsColumn = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnNameWorkspaceRoleAssignmentsGroupName = "$($_groupWorkspaceRoleAssignmentsColumn.Name)LookupId"
    $_roleWorkspaceRoleAssignmentsColumn = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Role' }; $_columnNameWorkspaceRoleAssignmentsRole = $_roleWorkspaceRoleAssignmentsColumn.Name
    $_workspaceRoleAssignmentIdWorkspaceRoleAssignmentsColumn = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Workspace Role Assignment ID' }; $_columnNameWorkspaceRoleAssignmentsWorkspaceId = $_workspaceRoleAssignmentIdWorkspaceRoleAssignmentsColumn.Name
    $_statusWorkspaceRoleAssignmentsColumn = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Status' }; $_columnNameWorkspaceRoleAssignmentsStatus = $_statusWorkspaceRoleAssignmentsColumn.Name

#endregion GET WORKSPACE ROLE ASSIGNMENTS LISTS

#region UPDATE WORKSPACE ROLE ASSIGNMENTS LISTS
 
    $hadUpdate = $false

    foreach ($workspace in $workspaces) {

        $workspaceRoleAssignments = Get-WorkspaceRoleAssignments -Tenant $global:Fabric.Tenant -Workspace $workspace | Where-Object { $_.principal.type -eq "Group"}
        $_workspaceRoleAssignmentsListItems = $workspaceRoleAssignmentsListItems | Where-Object { $_.'Workspace Name' -eq $workspace.displayName }

        # create a new sharepoint list item for any role assignments not in the Fabric Workspace Role Assignments sharepoint list
        $_workspaceRoleAssignments = $workspaceRoleAssignments | Where-Object { $_.id -notin $_workspaceRoleAssignmentsListItems.'Workspace Role Assignment ID'}
        foreach ($_workspaceRoleAssignment in $_workspaceRoleAssignments) {
            $workspaceListItem = $workspaceListItems | Where-Object { $_.'Workspace Name' -eq $workspace.displayName}  
            $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $workspaceRoleAssignment.principal.displayName}  
            $body = @{
                fields = @{
                    $_columnNameWorkspaceRoleAssignmentsWorkspaceName = $workspaceListItem.id 
                    $_columnNameWorkspaceRoleAssignmentsGroupName = $groupListItem.id 
                    $_columnNameWorkspaceRoleAssignmentsRole = $_workspaceRoleAssignment.role 
                    $_columnNameWorkspaceRoleAssignmentsWorkspaceId = $_workspaceRoleAssignment.id
                }
            }
            $workspaceRoleAssignmentText = "$($_workspaceRoleAssignment.displayName) | $($_workspaceRoleAssignment.principal.displayName) | $($_workspaceRoleAssignment.role)" 
            $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $workspaceRoleAssignmentsList  -ListItemBody $body     
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $hadUpdate = $true               
        }
        if ($hadUpdate) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Workspace Role Assignments" -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
            $hadUpdate = $false
        }


        # for each sharepoint group list item that is not in fabric, 
        # remove the sharepoint group list item
        $removeGroupItems = $workspaceRoleAssignmentsListItems | Where-Object {$_.'Workspace Name' -like "$($workspace.displayName)*" -and $_.'Workspace Role Assignment ID' -notin $workspaceRoleAssignments.id -and [string]::IsNullOrEmpty($_.Command) }
        foreach ($removeGroupItem in $removeGroupItems) {
            Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ListItem $removeGroupItem             
            $workspaceRoleAssignmentText = "$($removeGroupItem.'Workspace Name') | $($removeGroupItem.'Group Name') | $($removeGroupItem.Role)" 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed workspace role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $hadUpdate = $true
        }         
        if ($hadUpdate) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Workspace Role Assignments" -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
            $hadUpdate = $false
        }               

        # workspace name is missing from workspace role assignment sharepoint list
        $__workspaceRoleAssignmentsListItems = $_workspaceRoleAssignmentsListItems | Where-Object { [string]::IsNullOrEmpty($_.'Workspace Name') -and [string]::IsNullOrEmpty($_.Command) }
        foreach ($_workspaceRoleAssignmentsListItem in $__workspaceRoleAssignmentsListItems) { 
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $_workspaceRoleAssignmentsListItem -ColumnDisplayName "Workspace Name" -Value $workspace.displayName
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $($_workspaceRoleAssignmentsListItem.'Group Name') | $($_workspaceRoleAssignmentsListItem.Role)" 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated workspace role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $hadUpdate = $true 
        }  
        if ($hadUpdate) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Workspace Role Assignments" -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
            $hadUpdate = $false
        }                 

        # group name is missing from workspace role assignment sharepoint list
        $__workspaceRoleAssignmentsListItems = $_workspaceRoleAssignmentsListItems | Where-Object { [string]::IsNullOrEmpty($_.'Group Name') -and [string]::IsNullOrEmpty($_.Command) }
        foreach ($_workspaceRoleAssignmentsListItem in $__workspaceRoleAssignmentsListItems) {
            $workspaceRoleAssignment = $workspaceRoleAssignments | Where-Object { $_.id -eq $_workspaceRoleAssignmentsListItem.'Workspace Role Assignment ID'}
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $_workspaceRoleAssignmentsListItem -ColumnDisplayName "Group Name" -Value $workspaceRoleAssignment.principal.displayName
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $($workspaceRoleAssignment.principal.displayName) | $($workspaceRoleAssignment.role)" 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated workspace role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $hadUpdate = $true 
        } 
        if ($hadUpdate) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Workspace Role Assignments" -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
            $hadUpdate = $false
        }   

        # role is missing from workspace role assignment sharepoint list
        $__workspaceRoleAssignmentsListItems = $_workspaceRoleAssignmentsListItems | Where-Object { [string]::IsNullOrEmpty($_.'Role') -and [string]::IsNullOrEmpty($_.Command) }
        foreach ($_workspaceRoleAssignmentsListItem in $__workspaceRoleAssignmentsListItems) {
            $workspaceRoleAssignment = $workspaceRoleAssignments | Where-Object { $_.id -eq $_workspaceRoleAssignmentsListItem.'Workspace Role Assignment ID'}
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $_workspaceRoleAssignmentsListItem -ColumnDisplayName "Role" -Value $workspaceRoleAssignment.role
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $($workspaceRoleAssignment.principal.displayName) | $($workspaceRoleAssignment.role)" 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated workspace role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $hadUpdate = $true 
        }
        if ($hadUpdate) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing SharePoint list ", "Workspace Role Assignments" -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
            $hadUpdate = $false
        }

    }

    $hadUpdate = $false
    $workspaceRoleAssignmentListItemsWithStatus = $workspaceRoleAssignmentsListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($workspaceRoleAssignmentListItemsWithStatus.Count -gt 0) {
        foreach ($workspaceRoleAssignmentItemWithStatus in $workspaceRoleAssignmentListItemsWithStatus) {
            $workspaceRoleAssignmentPath = "$($workspaceRoleAssignmentItemWithStatus.'Workspace Name') | $($workspaceRoleAssignmentItemWithStatus.'Group Name') | $($workspaceRoleAssignmentItemWithStatus.role)" 
            if ( $workspaceRoleAssignmentItemWithStatus.Status -notlike "Invalid*" -and $workspaceRoleAssignmentItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$workspaceRoleAssignmentItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $workspaceRoleAssignmentItemWithStatus.Status, " status for workspace role assignment ", $workspaceRoleAssignmentPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $workspaceRoleAssignmentItemWithStatus.Status, " status for workspace role assignment ", $workspaceRoleAssignmentPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadUpdate = $true
    }

#endregion UPDATE WORKSPACE ROLE ASSIGNMENTS LIST    

#region PROCESS WORKSPACE ROLE ASSIGNMENTS COMMANDS

    # get the sharepoint workspace role assignment list items that have a pending command
    $hadCommand = $false
    $workspaceRoleAssignmentsListItemsWithCommand = @()
    $workspaceRoleAssignmentsListItemsWithCommand += $workspaceRoleAssignmentsListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    foreach ($autoProvisionGroup in $autoProvisionGroups) {
        $workspaceRoleAssignmentsListItemsWithCommand += [PSCustomObject]@{
            'Workspace Name' = $autoProvisionGroup.workspaceName
            'Group Name' = $autoProvisionGroup.groupName
            Role = $autoProvisionGroup.role
            Command = "Add"
        }
    }
    if ($workspaceRoleAssignmentsListItemsWithCommand.Count -gt 0) {
        $workspaceRoleAssignmentsListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($hadUpdate)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    foreach ($workspaceRoleAssignmentsListItem in $workspaceRoleAssignmentsListItemsWithCommand) {

        if ($null -eq $workspaceRoleAssignmentsListItem.Command -or $workspaceRoleAssignmentsListItem.Command -notin @("Add", "Remove", "Update")) { continue }

        $workspace = Get-Workspace -Tenant $global:Fabric.Tenant -Name $workspaceRoleAssignmentsListItem.'Workspace Name'
        $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $workspaceRoleAssignmentsListItem.'Group Name'}    

        # create a piped path string to use for workspace role assignments
        # format:  <workspace> | <group> | <role>
        $workspaceRoleAssignmentText = "$($workspaceRoleAssignmentsListItem.'Workspace Name') | $($workspaceRoleAssignmentsListItem.'Group Name') | $($workspaceRoleAssignmentsListItem.Role)" 
        
        # get Azure AD 
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $workspaceRoleAssignmentsListItem.Command, " workspace role assignment ", $workspaceRoleAssignmentText  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

        if ($workspaceRoleAssignmentsListItem.Command -eq "Add") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignment = Add-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id -Role $workspaceRoleAssignmentsListItem.Role
            if (![string]::IsNullOrEmpty($workspaceRoleAssignmentsListItem.Id)) {
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Workspace Role Assignment ID" -Value $workspaceRoleAssignment.id 
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Added role"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "     
            }
            else {
                $workspaceListItem = $workspaceListItems | Where-Object { $_.'Workspace Name' -eq $workspaceRoleAssignmentsListItem.'Workspace Name'}            
                $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $workspaceRoleAssignmentsListItem.'Group Name'}                 
                $body = @{
                    fields = @{
                        $_columnNameWorkspaceRoleAssignmentsWorkspaceName = $workspaceListItem.id 
                        $_columnNameWorkspaceRoleAssignmentsGroupName = $groupListItem.id 
                        $_columnNameWorkspaceRoleAssignmentsRole = $workspaceRoleAssignment.role 
                        $_columnNameWorkspaceRoleAssignmentsWorkspaceId = $workspaceRoleAssignment.id
                        $_columnNameWorkspaceRoleAssignmentsStatus = "Added role"
                    }
                }
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ListItemBody $body 

            } 

            Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Add" -Status "Success" -Message "Added workspace role assignment for $workspaceRoleAssignmentText" -EntryType "Information" -Force   
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added workspace role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue        
        }
        else {

            # for the Remove and Update commands, verify that the workspace role assignment exists
            $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -Id workspaceRoleAssignmentsListItem.'Workspace Role Assignment ID' # -PrincipalType "Group" -PrincipalId $azureADGroup.id
            if ($workspaceRoleAssignment) {

                if ($workspaceRoleAssignmentsListItem.Command -eq "Remove") {
                    # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
                    # $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id
                    $response = Remove-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -WorkspaceRoleAssignment $workspaceRoleAssignment
                    Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem
                    Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Remove" -Status "Success" -Message "Removed workspace role assignment for $workspaceRoleAssignmentText" -EntryType "Information" -Force 
                }

                if ($workspaceRoleAssignmentsListItem.Command -eq "Update") {
                    # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
                    # $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id
                    $response = Update-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -WorkspaceRoleAssignment $workspaceRoleAssignment -Role $workspaceRoleAssignmentsListItem.Role 
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Updated role"   
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "     
                    Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Update" -Status "Success" -Message "Updated workspace role assignment for $workspaceRoleAssignmentText" -EntryType "Information" -Force 
                } 

            }
            else {

                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Invalid role"   
                # $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "     
                Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action $workspaceRoleAssignmentsListItem.Command -Status "Failure" -Message "Unable to find workspace role assignment $workspaceRoleAssignmentText" -EntryType "Error" -Force 

            }
        }
    }

#endregion PROCESS WORKSPACE ROLE ASSIGNMENTS COMMANDS    

Write-Host+; Write-Host+
Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> end of line" -ForegroundColor DarkGray
Write-Host+
