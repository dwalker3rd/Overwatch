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

Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Connecting to tenant ", $global:Fabric.Tenant -ForegroundColor DarkGray, DarkBlue
Connect-Fabric -Tenant $global:Fabric.Tenant

Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Connecting to Exchange Online for tenant ", $global:Fabric.Tenant -ForegroundColor DarkGray, DarkBlue
Connect-ExchangeOnline+ -Tenant $global:Fabric.Tenant 

Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Connecting to tenant ", $global:SharePoint.Tenant -ForegroundColor DarkGray, DarkBlue
Connect-MgGraph+ -Tenant $global:SharePoint.Tenant

Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Connecting to SharePoint site ", $global:SharePoint.Site -ForegroundColor DarkGray, DarkBlue
$site = Get-SharePointSite -Tenant $global:SharePoint.Tenant -Site $global:SharePoint.Site

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
Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Caching users from tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
$azureADUsers, $cacheError = Get-AzureAdUsers -Tenant $global:Fabric.Tenant -AsArray
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

# cache groups to improve performance
Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Caching groups from tenant ", $global:Fabric.Tenant, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
$azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
$azureADGroups = $azureADGroups | Where-Object { ![string]::IsNullOrEmpty($_.displayName) }
Write-Host+ -NoTimestamp -NoTrace "`e[5D    "

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint capacity list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Capacities -ForegroundColor DarkGray, DarkBlue
    $capacityList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Capacities
    $capacityListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show the sharepoint capacity list items
    $capacityListItems | Format-Table -Property @("ID", "Capacity Name", "SKU", "Region", "State", "Capacity ID")

#endregion GET SHAREPOINT LISTS

#region UPDATE SHAREPOINT CAPACITY LIST    

    # get sharepoint capacity list items' [internal] column names
    $_columnNamesCapacity = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList
    $_capacityNameCapacityListItem = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Capacity Name' }; $_columnNameCapacityCapacityName = $_capacityNameCapacityListItem.Name
    $_capacityIdCapacityListItem = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Capacity ID' }; $_columnNameCapacityCapacityId = $_capacityIdCapacityListItem.Name
    $_skuCapacityListItem = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Sku' }; $_columnNameCapacitySku = $_skuCapacityListItem.Name
    $_regionCapacityListItem = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'Region' }; $_columnNameCapacityRegion = $_regionCapacityListItem.Name
    $_stateCapacityListItem = $_columnNamesCapacity | Where-Object { $_.DisplayName -eq 'State' }; $_columnNameCapacityState = $_stateCapacityListItem.Name

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
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $capacityList -ListItem $_unlistedCapacityListItem -Status -Value "Added capacity"               
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added capacity ", $_unlistedCapacityListItem.displayName, " from Fabric" -ForegroundColor DarkGray, DarkBlue, DarkGray
            $updatedCapacityList = $true
        }
    }

    # if the sharepoint capacity list was updated ...
    if ($updatedCapacityList) {
        # refresh the sharepoint capacity list items cache
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Capacities -ForegroundColor DarkGray, DarkBlue
        $capacityListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        # show the updated sharepoint capacity list items
        $capacityListItems | Format-Table -Property $global:SharePointView.Capacity.Default 
    }

#endregion UPDATE SHAREPOINT CAPACITY LIST

#region UPDATE SHAREPOINT WORKSPACE LIST

    # get sharepoint workspace list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Workspaces -ForegroundColor DarkGray, DarkBlue
    $workspaceList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Workspaces
    $workspaceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show the sharepoint workspace list items
    $workspaceListItems | Format-Table -Property $global:SharePointView.Workspace.Default

    # get sharepoint workspace list items' [internal] column names
    $_columnNamesWorkspace = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList
    $_workspaceNameWorkspaceListItem = $_columnNamesWorkspace | Where-Object { $_.DisplayName -eq 'Workspace Name' }; $_columnNameWorkspaceWorkspaceName = $_workspaceNameWorkspaceListItem.Name
    $_workspaceIdWorkspaceListItem = $_columnNamesWorkspace | Where-Object { $_.DisplayName -eq 'Workspace ID' }; $_columnNameWorkspaceWorkspaceId = $_workspaceIdWorkspaceListItem.Name
    $_workspaceCapacityNameWorkspaceListItem = $_columnNamesWorkspace | Where-Object { $_.DisplayName -eq 'Capacity Name' }; $_columnNameWorkspaceCapacityName = "$($_workspaceCapacityNameWorkspaceListItem.Name)LookupId"

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
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $_unlistedWorkspaceListItem -Status -Value "Added workspace"               
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
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Workspaces -ForegroundColor DarkGray, DarkBlue
        $workspaceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns  
        $workspaceListItems | Format-Table -Property $global:SharePointView.Workspace.Default
    }

    # for each sharepoint workspace list item, 
    # if the time when its status was updated is greater than $statusTimeToLiveInSeconds,
    # clear the sharepoint workspace list item's status
    $hadStatus = $false
    $workspaceListItemsWithStatus = $workspaceListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($workspaceListItemsWithStatus.Count -gt 0) {
        foreach ($workspaceListItemWithStatus in $workspaceListItemsWithStatus) {
            if ( $workspaceListItemWithStatus.Status -notlike "Invalid*" -and $workspaceListItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$workspaceListItemWithStatus.Modified
                if ($sinceModified.TotalSeconds -gt $statusTimeToLiveInSeconds) {
                    $updatedWorkspaceListItemWithStatus = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $workspaceListItemWithStatus.Status, " status for workspace ", $workspaceListItemWithStatus.'Workspace Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $workspaceListItemWithStatus.Status, " status for workspace ", $workspaceListItemWithStatus.'Workspace Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadStatus = $true
    }

#endregion UPDATE SHAREPOINT WORKSPACE LIST   

#region PROCESS WORKSPACE COMMANDS

    # get the sharepoint workspace list items that have a pending command
    $hadCommand = $false
    $workspaceListItemsWithCommand = $workspaceListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command)}
    if ($workspaceListItemsWithCommand.Count -gt 0) {
        $workspaceListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($updatedWorkspaceList -or $hadStatus)
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
                            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Workspace ID" -Value $workspace.id
                            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Created workspace"   
                            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   

                            #region AUTOPROVISION GROUPS
                            
                                # auto-provision groups
                                $autoProvisionGroups = @()
                                $autoProvisionGroups += @{ displayName = "$($workspace.displayName) - Read Only"; role = "Viewer" }
                                $autoProvisionGroups += @{ displayName = "$($workspace.displayName) - Workspace Admin"; role = "Admin" }
                                $autoProvisionGroups += @{ displayName = "$($workspace.displayName) - Data Contributors"; role = "Contributor" }

                                # get sharepoint group list items
                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups -ForegroundColor DarkGray, DarkBlue
                                $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups
                                $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

                                # get group [internal] column names
                                $_columnNamesGroup = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $groupList
                                $_groupNameGroupListItem = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnNameGroupGroupName = $_groupNameGroupListItem.Name
                                $_groupIdGroupListItem = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Group Id' }; $_columnNameGroupGroupId = $_groupIdGroupListItem.Name
                                $_commandGroupListItem = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Command' }; $_columnNameGroupCommand = $_commandGroupListItem.Name

                                # create a new sharepoint list item for each auto-provision group in the sharepoint groups list 
                                # when the groups list is processed in subsequent steps, it will create the groups
                                $updatedGroupList = $false
                                foreach ($autoProvisionGroup in $autoProvisionGroups) {
                                    $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $autoProvisionGroup.displayName}
                                    if (!$groupListItem) {
                                        $body = @{
                                            fields = @{
                                                $_columnNameGroupGroupName = $autoProvisionGroup.displayName
                                                $_columnNameGroupCommand = "Create"
                                            }
                                        }
                                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding group ", $autoProvisionGroup.displayName, " to SharePoint list ", $groupList.Name -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                                        $_groupListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItemBody $body   
                                        Write-Log -Context $overwatchProductId -Target "Group" -Action "Auto-provision" -Status "Success" -Message "Added group $($autoProvisionGroup.displayName) to SharePoint list $($groupList.Name)" -EntryType "Information" -Force  
                                        $updatedGroupList = $true   
                                    }
                                }
                                if ($updatedGroupList) {

                                    # refresh sharepoint group list items
                                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Groups -ForegroundColor DarkGray, DarkBlue
                                    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
                                    $groupListItems | Format-Table -Property $global:SharePointView.Group.Default
                                }

                                # get sharepoint workspace role assignment list and its listitems
                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.WorkspaceRoleAssignments -ForegroundColor DarkGray, DarkBlue
                                $workspaceRoleAssignmentsList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.WorkspaceRoleAssignments
                                $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns      
                                
                                # get sharepoint workspace role assignment list items' [internal] column names
                                $_columnNamesWorkspaceRoleAssignments = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList
                                $_workspaceNameWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Workspace Name' }; $_columnNameWorkspaceRoleAssignmentsWorkspaceName = "$($_workspaceNameWorkspaceRoleAssignmentsListItem.Name)LookupId"
                                $_groupWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnWorkspaceRoleAssignmentsGroupName = "$($_groupWorkspaceRoleAssignmentsListItem.Name)LookupId"
                                $_roleWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Role' }; $_columnWorkspaceRoleAssignmentsRole = $_roleWorkspaceRoleAssignmentsListItem.Name
                                $_commandWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Command' }; $_columnNameWorkspaceRoleAssignmentsCommand = $_commandWorkspaceRoleAssignmentsListItem.Name
                                
                                # these two groups need to be added to the workspace role assignments
                                # $autoProvisionGroups += @{ displayName = "Data Curators"; role = "Member" }
                                # $autoProvisionGroups += @{ displayName = "Fabric Admin"; role = "Admin" }

                                # create a new sharepoint list item for each auto-provision group in the sharepoint workspace role assignments list 
                                # when the workspace role assignments list is processed in subsequent steps, it will create the workspace role assignments
                                $updatedWorkspaceRoleAssignmentList = $false
                                foreach ($autoProvisionGroup in $autoProvisionGroups) {
                                    $workspaceListItem = $workspaceListItems | Where-Object { $_.'Workspace Name' -eq $workspace.displayName}            
                                    $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $autoProvisionGroup.displayName}  
                                    $body = @{
                                        fields = @{
                                            $_columnNameWorkspaceRoleAssignmentsWorkspaceName = $workspaceListItem.id 
                                            $_columnWorkspaceRoleAssignmentsGroupName = $groupListItem.id 
                                            $_columnWorkspaceRoleAssignmentsRole = $workspaceRoleAssignment.role 
                                            $_columnNameWorkspaceRoleAssignmentsCommand = "Add"
                                        }
                                    }
                                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding role ", $autoProvisionGroup.displayName, " to SharePoint list ", $workspaceRoleAssignmentsList.displayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                                    $_workspaceRoleAssignmentListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $workspaceRoleAssignmentsList -ListItemBody $body 
                                    Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Auto-provision" -Status "Success" -Message "Adding role $($workspaceRoleAssignment.role) for workspace $($workspace.displayName) and group $($autoProvisionGroup.displayName) to SharePoint list $($workspaceRoleAssignmentsList.displayName)" -EntryType "Information" -Force      
                                    $updatedworkspaceRoleAssignmentList = $true   
                                }
                                if ($updatedworkspaceRoleAssignmentList) {

                                    # refresh sharepoint group list items
                                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.WorkspaceRoleAssignments -ForegroundColor DarkGray, DarkBlue
                                    $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
                                    $workspaceRoleAssignmentsListItems | Format-Table -Property $global:SharePointView.WorkspaceRoleAssignment.Default
                                }

                            #endregion AUTOPROVISION GROUPS                                
                            
                        }
                        else {
                            
                            # failed to create the workspace
                            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Create workspace failed"   
                            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   
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
                        $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Status" -Value "Invalid Workspace ID"   
                        $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   
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
                                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Renamed workspace"   
                                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "  
                                Write-Log -Context $overwatchProductId -Target "Workspace" -Action "Rename" -Status "Success" -Message "Renamed workspace $($workspaceListItemWithCommand.'Workspace Name')" -EntryType "Information" -Force

                            }
                            else {

                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to rename workspace: ", $workspace.displayName -ForegroundColor DarkRed
                                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Rename workspace failed"   
                                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "  
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
                        $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Capacity Name" -Value $capacity.displayName                          
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
                        $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Assigned capacity"  
                        Write-Log -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Success" -Message "Assigned capacity $($Capacity.displayName) to workspace $($workspace.displayName)" -EntryType "Information" -Force                  
                    }
                    else {
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to assign capacity ", $($Capacity.displayName), " to workspace ", $($workspace.displayName) -ForegroundColor DarkRed
                        $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Assign capacity failed" 
                        Write-Log -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Failure" -Message "Failed to assign capacity $($Capacity.displayName) to workspace $($workspace.displayName)" -EntryType "Error" -Force 
                    }
                }
                else {
                    # the capacity name field in the sharepoint list item is NOT valid
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Capacity ", $($capacity.displayName), "NOT FOUND" -ForegroundColor DarkRed
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Invalid capacity"   
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " " 
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
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint user list items
    $userListItems | Format-Table -Property $global:SharePointView.User.Default

#endregion GET SHAREPOINT LISTS    

#region UPDATE SHAREPOINT USER LIST

    # update sharepoint user list item User Email if it's been changed
    # note that User Email should/must not be changed 
    # but if it is, restore it from User Email (backup)
    $updatedUserListItems = $false
    foreach ($userListItem in $userListItems) {
        
        # update Sharepoint list item User Email with User Email (backup) when User Email is blank but User Email (backup) is not blank
        if ([string]::IsNullOrEmpty($userListItem.'User Email') -and ![string]::IsNullOrEmpty($userListItem.'User Email (backup)')) {
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User Email" -Value $userListItem.'User Email (backup)'
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Restored email"
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "User Email ", $userListItem.'User Email', " restored to ", $userListItem.'User Email (backup)' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
        }

        # update Sharepoint list item User Email with User Email (backup) when both are not blank and User Email does not match User Email (backup)
        # assume that User Email (backup) is still correct since it was updated by this code (it's hidden and shouldn't be modified)
        if (![string]::IsNullOrEmpty($userListItem.'User Email') -and ![string]::IsNullOrEmpty($userListItem.'User Email (backup)') -and 
            $userListItem.'User Email' -ne $userListItem.'User Email (backup)') {
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User Email" -Value $userListItem.'User Email (backup)'
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Restored email"
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "User Email ", $userListItem.'User Email', " restored to ", $userListItem.'User Email (backup)' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue    
                $updatedUserListItems = $true       
        } 

    }

    # refresh sharepoint user list items
    if ($updatedUserListItems) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $userList -ForegroundColor DarkGray, DarkBlue
        $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $userListItems | Format-Table -Property $global:SharePointView.User.Default
    }

    # get user email addresses from sharepoint user list items
    $listedUsers = @()
    foreach ($userListItem in $userListItems) {
        $listedUsers += $userListItem.'User Email'
    }

    # get user [internal] column names
    $_columnNames = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $userList
    $_userNameListItem = $_columnNames | Where-Object { $_.DisplayName -eq 'User Name' }; $_columnNameUserName = $_userNameListItem.Name
    $_emailListItem = $_columnNames | Where-Object { $_.DisplayName -eq 'User Email' }; $_columnNameEmail = $_emailListItem.Name
    $_emailBackupListItem = $_columnNames | Where-Object { $_.DisplayName -eq 'User Email (backup)' }; $_columnNameEmailBackup = $_emailBackupListItem.Name
    $_accountStatusListItem = $_columnNames | Where-Object { $_.DisplayName -eq 'Account Status' }; $_columnNameAccountStatus = $_accountStatusListItem.Name
    $_externalUserStateListItem = $_columnNames | Where-Object { $_.DisplayName -eq 'External User State' }; $_columnNameExternalUserState = $_externalUserStateListItem.Name

    # update sharepoint user list items with meta from Azure AD
    $updatedUserList = $false
    $listedAzureADUsers = $azureADUsers | Where-Object { $_.mail -and $_.mail -in $listedUsers }
    foreach ($listedAzureADUser in $listedAzureADUsers) {

        $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $listedAzureADUser.mail
        $userListItem = $userListItems | Where-Object { $_.'User Email' -eq $azureADUser.mail }

        # update sharepoint list item when User Email (backup) is null or empty
        if ([string]::IsNullOrEmpty($userListItem.'User Email (backup)')) {        
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User Email (backup)" -Value $azureADUser.mail
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated `"User Email (backup)`" for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue
            $updatedUserList = $true
        }    

        # update sharepoint list item when $azureADUser.accountenabled does not match Account Status
        if ($($userListItem.'Account Status' -eq "Enabled") -ne $azureADUser.accountEnabled) {
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value $($azureADUser.accountEnabled ? "Enabled" : "Disabled")   
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "User ", $azureADUser.mail, $($azureADUser.accountEnabled ? " Enabled" : " Disabled") -ForegroundColor DarkGray, DarkBlue, ($azureADUser.accountEnabled ? "DarkGreen" : "DarkRed")              
            $updatedUserList = $true
        }

        # update sharepoint list item when $azureADUser.externalUserState does not match the Azure AD user's externalUserState propery
        # if ((![string]::IsNullOrEmpty($userListItem.'External User State') -and ![string]::IsNullOrEmpty($azureADUser.externalUserState) -and $userListItem.'External User State' -ne $azureADUser.externalUserState) -or [string]::IsNullOrEmpty($userListItem.'External User State')) {
            # if ($azureADUser.userType -eq "Guest") {
                $externalUserState = $azureADUser.userPrincipalName -match "#EXT#@" ? $azureADUser.externalUserState : "Internal"
                if ($userListItem.'External User State' -ne $externalUserState) {
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "External User State" -Value $externalUserState
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "User ", $azureADUser.mail, " externalUserState: ", $azureADUser.externalUserState -ForegroundColor DarkGray, DarkBlue, DarkGray, ($azureADUser.externalUserState -eq "Accepted" ? "DarkGreen" : "DarkYellow")
                    $updatedUserList = $true
                }
            # }       
        # }   

    }

    # for Azure AD users not in the sharepoint user list 
    # create a new sharepoint user list item 
    $updatedUnlistedUserList = $false
    $unlistedUsers = $azureADUsers | Where-Object { $_.mail -and $_.mail -notin $listedUsers }
    foreach ($unlistedUser in $unlistedUsers) {
        if ($unlistedUser.mail) {
            # need full Azure AD user object
            $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $unlistedUser.mail
            if (!$azureADGroup.error) {        
                $body = @{ fields = @{} }
                $body.fields += @{ $_columnNameUserName = $azureADUser.displayName }
                $body.fields += @{ $_columnNameEmailBackup = $azureADUser.mail.ToLower() }
                $body.fields += @{ $_columnNameEmail = $azureADUser.mail.ToLower() }
                $body.fields += @{ $_columnNameAccountStatus = $azureADUser.accountEnabled ? "Enabled" : "Disabled" }
                $body.fields += @{ $_columnNameExternalUserState = $azureADUser.externalUserState }
                $unlistedUserListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ListItemBody $body
                if ($unlistedUserListItem){
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $unlistedUserListItem -Status -Value "Added user"               
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added user ", $azureADUser.mail.ToLower(), " from Azure AD" -ForegroundColor DarkGray, DarkBlue, DarkGray
                }
                else {
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Add user failed" 
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to add user ", $azureADUser.mail.ToLower(), " from Azure AD" -ForegroundColor DarkRed            
                }
                $updatedUnlistedUserList = $true            
            }
            
        }
    }

    # for each sharepoint user list item, 
    # if the time when its status was updated is greater than $statusTimeToLiveInSeconds,
    # clear the sharepoint user list item's status
    $hadStatus = $false
    $userListItemsWithStatus = $userListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($userListItemsWithStatus.Count -gt 0) {
        foreach ($userListItemWithStatus in $userListItemsWithStatus) {
            if ( $userListItemWithStatus.Status -notlike "Invalid*" -and $userListItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$userListItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $updatedWorkspaceListItemWithStatus = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $userListItemWithStatus.Status, " status for user ", $userListItemWithStatus.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $userListItemWithStatus.Status, " status for user ", $userListItemWithStatus.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadStatus = $true
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
        Write-Host+ -Iff $($updatedUserList -or $updatedUnlistedUserList -or $hadStatus)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    $updatedAzureADUsers = $false
    foreach ($userListItem in $userListItems) {

        if ($null -eq $userListItem.Command -or $userListItem.Command -notin @("Rename", "Invite", "Enable", "Disable")) { continue }

        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $userListItem.Command, " user ", $userListItem.'User Email'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

        # get Azure AD user
        $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $userListItem.'User Email'
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
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value ($azureADUser.accountEnabled ? "Enabled" : "Disabled")
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Command" -Value " "
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "User ", $azureADUser.mail, " ", $($azureADUser.accountEnabled ? "Enabled" : "Disabled") -ForegroundColor DarkGray, DarkBlue, DarkGray, ($azureADUser.accountEnabled? "DarkGreen" : "DarkRed") 

            }

            # rename azureADuser account when azureADUser.displayName is different from the sharepoint user list item's User Name
            if ($userListItem.Command -eq "Rename" -and $userListItem.'User Name' -ne $azureADUser.displayName) {
                $currentAzureADUserName = $azureADUser.displayName
                $userListItemUserName = $userListItem.'User Name'
                $azureADUser = Update-AzureADUserNames -Tenant $global:Fabric.Tenant -User $azureADUser -DisplayName $userListItemUserName
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Renamed user"   
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Command" -Value " "             
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Renamed `"User Name`" from ", $azureADUser.mail, " to ", $azureADUser.displayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
                Write-Log -Context $overwatchProductId -Target "User" -Action "Rename" -Status "Success" -Message "Renamed `"User Name`" from $currentAzureADUserName to $($azureADUser.displayName)" -EntryType "Information" -Force             
            }

        }
        else {

            # send invitation to newly added user
            if ($userListItem.Command -eq "Invite") {
                $invitation = Send-AzureADInvitation -Tenant $global:Fabric.Tenant -Email $userListItem.'User Email' -DisplayName $userListItem.'User Name'
                $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $invitation.invitedUser.id 
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName 'User Email (backup)' -Value $azureADUser.mail
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName 'External User State' -Value $azureADUser.externalUserState
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value "Enabled"
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Invited user" 
                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Command" -Value " " 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Invited user ", $azureADUser.mail, " to tenant ", $global:Fabric.Tenant -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
                Write-Log -Context $overwatchProductId -Target "User" -Action "Invite" -Status "Success" -Message "Invited $($azureADUser.displayName) to tenant $($global:Fabric.Tenant)" -EntryType "Information" -Force          
            }
        }

        $updatedAzureADUsers = $true

    }

#endregion PROCESS USER COMMANDS

#region REFRESH AZURE AD USER CACHE

    # if any Azure AD user was created/updated/removed,
    # regresh the Overwatch Azure AD user cache
    if ($updatedAzureADUsers) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", "Update", " Azure AD Users" -ForegroundColor DarkGray, DarkBlue, DarkGray
        # Write-Host+
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Users -Timeout $azureADCacheTimeout -Quiet
        $azureADUsers, $cacheError = Get-AzureAdUsers -Tenant $global:Fabric.Tenant -AsArray        
        Write-Log -Context $overwatchProductId -Target "Users" -Action "Refresh" -Status "Success" -Message "Refreshed Azure AD user cache" -EntryType "Information" -Force
    }

#region REFRESH AZURE AD USER CACHE

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint user list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups -ForegroundColor DarkGray, DarkBlue
    $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups
    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint group list items
    $groupListItems | Format-Table -Property $global:SharePointView.Group.Default

    # get sharepoint group list items' [internal] column names
    $_columnNamesGroup = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $groupList
    $_groupNameGroupListItem = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnNameGroupGroupName = $_groupNameGroupListItem.Name
    $_groupIdGroupListItem = $_columnNamesGroup | Where-Object { $_.DisplayName -eq 'Group ID' }; $_columnNameGroupGroupId = $_groupIdGroupListItem.Name

#endregion GET SHAREPOINT LISTS

#region UPDATE SHAREPOINT GROUP LIST    

    # for each Azure AD group not in the sharepoint group list 
    # create a new sharepoint group list item 
    $updatedGroupList = $false
    foreach ($_azureADGroup in $azureADGroups) {
        $azureADGroup = Get-AzureADGroup -Tenant $global:Fabric.Tenant -Id $_azureADGroup.id
        if (!$azureADGroup.error) {
            $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $azureADGroup.displayName}
            if (!$groupListItem) {
                $body = @{
                    fields = @{
                        $_columnNameGroupGroupName = $azureADGroup.displayName
                        $_columnNameGroupGroupId = $azureADGroup.id
                    }
                }
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItemBody $body 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added group ", $azureADGroup.displayName, " to SharePoint list ", $groupList.Name -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue    
                $updatedGroupList = $true   
            }
        }
    }

    # for each sharepoint group list item that is not in fabric, 
    # remove the sharepoint group list item
    $removeGroupItems = $groupListItems | Where-Object {$_.'Group Name' -notin $azureADGroups.displayName -and [string]::IsNullOrEmpty($_.Command) }
    foreach ($removeGroupItem in $removeGroupItems) {
        $removedGroupName = ![string]::IsNullOrEmpty($removeGroupItem.'Group Name') ? $removeGroupItem.'Group Name' : "<group name is blank>"
        Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ListItem $removeGroupItem              
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed group ", $removedGroupName, " from SharePoint list ", $groupList.name -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
        $updatedGroupList = $true
    }

    # if the sharepoint group list was updated, refresh the sharepoint group list
    if ($updatedGroupList) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Groups -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList
        $groupListItems | Format-Table -Property $global:SharePointView.Group.Default
    }

    # for each sharepoint group list item, 
    # if the time when its status was updated is greater than $statusTimeToLiveInSeconds,
    # clear the sharepoint group list item's status    
    $hadStatus = $false
    $groupListItemsWithStatus = $groupListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($groupListItemsWithStatus.Count -gt 0) {
        foreach ($groupItemWithStatus in $groupListItemsWithStatus) {
            if ( $groupItemWithStatus.Status -notlike "Invalid*" -and $groupItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$groupItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $updatedGroupListItemWithStatus = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $groupItemWithStatus.Status, " status for group ", $groupListItemsWithStatus.'Group Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $groupItemWithStatus.Status, " status for group ", $groupListItemsWithStatus.'Group Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadStatus = $true
    }

#endregion UPDATE SHAREPOINT GROUP LIST

#region PROCESS GROUP COMMANDS

    # get the sharepoint group list items that have a pending command
    $hadCommand = $false
    $groupListItemsWithCommand = $groupListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    if ($groupListItemsWithCommand.Count -gt 0) {
        $groupListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($updatedGroupList -or $hadStatus)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    $updatedAzureADGroups = $false
    foreach ($groupListItem in $groupListItemsWithCommand) {

        if ($null -eq $groupListItem.Command -or $groupListItem.Command -notin @("Create", "Delete")) { continue }
    
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupListItem.Command, " group ", $groupListItem.'Group Name'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

        # get Azure AD group
        $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $groupListItem.'Group Name' }

        # create a new mail-enabled security group
        # update the sharepoint group list item
        if ($groupListItem.Command -eq "Create" -and !$azureADGroup) {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Creating group ", $groupListItem.'Group Name' -ForegroundColor DarkGray, DarkBlue
            $_newMailEnabledSecurityGroup = New-MailEnabledSecurityGroup -Name $groupListItem.'Group Name'
            Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Timeout $azureADCacheTimeout -Quiet
            $azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
            $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $groupListItem.'Group Name' }
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Group Name" -Value $azureADGroup.displayName
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Group ID" -Value $azureADGroup.id
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -Status -Value "Created group"   
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Command" -Value " " 
            Write-Log -Context $overwatchProductId -Target "Group" -Action "New" -Status "Success" -Message "Created new mail-enabled security group $($groupListItem.'Group Name')" -EntryType "Information" -Force
            $updatedAzureADGroups = $true
        }

        # delete a new mail-enabled security group
        # delete the sharepoint group list item
        if ($groupListItem.Command -eq "Delete" -and $azureADGroup) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing group ", $groupListItem.'Group Name' -ForegroundColor DarkGray, DarkBlue
            Remove-MailEnabledSecurityGroup -Group $groupListItem.'Group Name' 
            Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItem $groupListItem
            Write-Log -Context $overwatchProductId -Target "Group" -Action "Remove" -Status "Success" -Message "Removed mail-enabled security group $($groupListItem.'Group Name')" -EntryType "Information" -Force
            $updatedAzureADGroups = $true
        } 
    }   

#endregion PROCESS GROUP COMMANDS

#region REFRESH AZURE AD GROUP CACHE

    if ($updatedAzureADGroups) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", "Update", " Azure AD Groups" -ForegroundColor DarkGray, DarkBlue, DarkGray
        # Write-Host+
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Timeout $azureADCacheTimeout -Quiet
        $azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
        Write-Log -Context $overwatchProductId -Target "Groups" -Action "Refresh" -Status "Success" -Message "Refreshed Azure AD group cache" -EntryType "Information" -Force
    }

#endregion REFRESH AZURE AD USER CACHE

Write-Host+

#region GET SHAREPOINT LISTS

    # get sharepoint user list and list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group list and list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups -ForegroundColor DarkGray, DarkBlue
    $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups
    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group membership list and list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.GroupMembership -ForegroundColor DarkGray, DarkBlue
    $groupMembershipList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.GroupMembership
    $groupMembershipListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint group membership list items
    $groupMembershipListItems | Format-Table -Property $global:SharePointView.GroupMembership.Default

    # get sharepoint group membership list items' [internal] column names
    $_columnNamesGroupMembership = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList
    $_groupNameGroupMembershipListItem = $_columnNamesGroupMembership | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnNameGroupMembershipGroupName = "$($_groupNameGroupMembershipListItem.Name)LookupId"
    $_userEmailGroupMembershipListItem = $_columnNamesGroupMembership | Where-Object { $_.DisplayName -eq 'User Email' }; $_userEmailGroupMembershipGroupName = "$($_userEmailGroupMembershipListItem.Name)LookupId"

#endregion GET SHAREPOINT LISTS   

#region UPDATE GROUP MEMBERSHIP SHAREPOINT LIST

    # create a new sharepoint list item for any Azure AD group member not in the Fabric Group Membership sharepoint list 
    $unlistedMembers = @()
    $updatedGroupMembershipList = $false
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
                $updatedGroupMembershipList = $true
            }
        }
    }
    if ($updatedGroupMembershipList) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.GroupMembership -ForegroundColor DarkGray, DarkBlue
        $groupMembershipListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $groupMembershipListItems | Format-Table -Property $global:SharePointView.GroupMembership.Default
    }

    $hadStatus = $false
    $groupMembershipListItemsWithStatus = $groupMembershipListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($groupMembershipListItemsWithStatus.Count -gt 0) {
        foreach ($groupMembershipListItemWithStatus in $groupMembershipListItemsWithStatus) {
            $groupMembershipPath = "$($groupMembershipListItemWithStatus.'Group Name')\$($groupMembershipListItemWithStatus.'User Email')"
            if ( $groupMembershipListItemWithStatus.Status -notlike "Invalid*" -and $groupMembershipListItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$groupMembershipListItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $updatedWorkspaceListItemWithStatus = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $groupMembershipListItemWithStatus.Status, " status for group membership ", $groupMembershipPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $groupMembershipListItemWithStatus.Status, " status for group membership ", $groupMembershipPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadStatus = $true
    }

#endregion UPDATE GROUP MEMBERSHIP SHAREPOINT LIST  

#region PROCESS GROUP MEMBERSHIP COMMANDS

    # get the sharepoint group membership list items that have a pending command
    $hadCommand = $false
    $groupMembershipListItemsWithCommand = $groupMembershipListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    if ($groupMembershipListItemsWithCommand.Count -gt 0) {
        $groupMembershipListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($updatedGroupMembershipList -or $hadStatus)
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
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -Status -Value "Invalid user"   
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -ColumnDisplayName "Command" -Value " "   
            continue      
        }

        # create a piped path string to use for group membership 
        # format:  <workspace> | <user email>  
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupMembershipListItem.Command, " user ", $groupMembershipListItem.'User Email', " to mail-enabled security group ", $groupMembershipListItem.'Group Name', " in workspace ", $groupWorkspace.displayName  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue, DarkGray, DarkBlue, DarkGray, DarkBlue

        # get Azure AD group
        $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $groupMembershipListItem.'Group Name' }
        if (!$azureADGroup) {
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -Status -Value "Invalid group"   
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -ColumnDisplayName "Command" -Value " "         
            continue
        }

        # add user to group
        if ($groupMembershipListItem.Command -eq "Add") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding user ", $groupMembershipListItem.'User Email', " to group ", $($groupMembershipListItem.'Group Name')   -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            Add-MailEnabledSecurityGroupMember -Group $groupMembershipListItem.'Group Name' -Member $groupMembershipListItem.'User Email'
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -Status -Value "Added user"   
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem -ColumnDisplayName "Command" -Value " " 
            Write-Log -Context $overwatchProductId -Target "GroupMembership" -Action "Add" -Status "Success" -Message "Added user $($groupMembershipListItem.'User Email') to mail-enabled security group $($groupMembershipListItem.'Group Name')" -EntryType "Information" -Force         
        }

        # remove user from group
        if ($groupMembershipListItem.Command -eq "Remove") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing user ", $groupMembershipListItem.'User Email', " from group ", $($groupMembershipListItem.'Group Name')   -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            Remove-MailEnabledSecurityGroupMember -Group $groupMembershipListItem.'Group Name' -Member $groupMembershipListItem.'User Email'
            Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupMembershipList -ListItem $groupMembershipListItem
            Write-Log -Context $overwatchProductId -Target "GroupMembership" -Action "Remove" -Status "Success" -Message "Removed user $($groupMembershipListItem.'User Email') from mail-enabled security group $($groupMembershipListItem.'Group Name')" -EntryType "Information" -Force 
        }    

    }

#endregion PROCESS GROUP MEMBERSHIP COMMANDS

Write-Host+

#region GET WORKSPACE ROLE ASSIGNMENTS LISTS

    # get sharepoint workspace list and its listitems
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Workspaces -ForegroundColor DarkGray, DarkBlue
    $workspaceList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Workspaces
    $workspaceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint group list and its listitems
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Groups -ForegroundColor DarkGray, DarkBlue
    $groupList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Groups
    $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint workspace role assignment list and its listitems
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.WorkspaceRoleAssignments -ForegroundColor DarkGray, DarkBlue
    $workspaceRoleAssignmentsList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.WorkspaceRoleAssignments
    $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint workspace role assignment list items
    $workspaceRoleAssignmentsListItems | Format-Table -Property $global:SharePointView.WorkspaceRoleAssignment.Default

    # get sharepoint workspace role assignment list items' [internal] column names
    $_columnNamesWorkspaceRoleAssignments = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList
    $_workspaceNameWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Workspace Name' }; $_columnNameWorkspaceRoleAssignmentsWorkspaceName = "$($_workspaceNameWorkspaceRoleAssignmentsListItem.Name)LookupId"
    $_groupWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Group Name' }; $_columnWorkspaceRoleAssignmentsGroupName = "$($_groupWorkspaceRoleAssignmentsListItem.Name)LookupId"
    $_roleWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Role' }; $_columnWorkspaceRoleAssignmentsRole = $_roleWorkspaceRoleAssignmentsListItem.Name
    $_workspaceRoleAssignmentIdWorkspaceRoleAssignmentsListItem = $_columnNamesWorkspaceRoleAssignments | Where-Object { $_.DisplayName -eq 'Workspace Role Assignment ID' }; $_columnNameWorkspaceRoleAssignmentsWorkspaceId = $_workspaceRoleAssignmentIdWorkspaceRoleAssignmentsListItem.Name

#endregion GET WORKSPACE ROLE ASSIGNMENTS LISTS

#region UPDATE WORKSPACE ROLE ASSIGNMENTS LISTS

    # create a new sharepoint list item for any role assignments not in the Fabric Workspace Role Assignments sharepoint list 
    $updatedWorkspaceRoleAssignmentList = $false
    # Write-Host+ -NoTimestamp -NoTrace -NoSeparator -NoNewLine "Comparing Fabric Role Assignments with SharePoint list ", $workspaceRoleAssignmentsList.DisplayName, " ... " -ForegroundColor DarkGray, DarkBlue, DarkGray
    foreach ($workspace in $workspaces) {
        $workspaceRoleAssignments = Get-WorkspaceRoleAssignments -Tenant $global:Fabric.Tenant -Workspace $workspace | Where-Object { $_.principal.type -eq "Group"}
        foreach ($workspaceRoleAssignment in $workspaceRoleAssignments) {
            if ($workspace.displayName -in $workspaceRoleAssignmentsListItems.'Workspace Name' -and
            $workspaceRoleAssignment.principal.displayName -in $workspaceRoleAssignmentsListItems.'Group Name' -and
            $workspaceRoleAssignment.role -in $workspaceRoleAssignmentsListItems.Role) {
                continue
            }
            else {
                $workspaceListItem = $workspaceListItems | Where-Object { $_.'Workspace Name' -eq $workspace.displayName}            
                $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $workspaceRoleAssignment.principal.displayName}  
                $body = @{
                    fields = @{
                        $_columnNameWorkspaceRoleAssignmentsWorkspaceName = $workspaceListItem.id 
                        $_columnWorkspaceRoleAssignmentsGroupName = $groupListItem.id 
                        $_columnWorkspaceRoleAssignmentsRole = $workspaceRoleAssignment.role 
                        $_columnNameWorkspaceRoleAssignmentsWorkspaceId = $workspaceRoleAssignment.id
                    }
                }
                # Write-Host+ # close NoNewLine
                $workspaceRoleAssignmentText = "$($workspaceListItem.'Workspace Name') | $($groupListItem.'Group Name') | $($workspaceRoleAssignment.role)"
                # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding role assignment ", $workspaceRoleAssignmentText, " from Fabric to SharePoint list ", $global:SharePoint.List.WorkspaceRoleAssignments -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $workspaceRoleAssignmentsList  -ListItemBody $body     
                $updatedWorkspaceRoleAssignmentList = $true               
            }
        }
    }
    if ($updatedWorkspaceRoleAssignmentList) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.WorkspaceRoleAssignments -ForegroundColor DarkGray, DarkBlue
        $workspaceRoleAssignmentsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceRoleAssignmentsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $workspaceRoleAssignmentsListItems | Format-Table -Property $global:SharePointView.WorkspaceRoleAssignment.Default
    }
    # else {
    #     Write-Host+ -NoTimestamp -NoTrace "`e[5D    "
    # }

    $hadStatus = $false
    $workspaceRoleAssignmentListItemsWithStatus = $workspaceRoleAssignmentsListItems | Where-Object { ![string]::IsNullOrEmpty($_.Status)}
    if ($workspaceRoleAssignmentListItemsWithStatus.Count -gt 0) {
        foreach ($workspaceRoleAssignmentItemWithStatus in $workspaceRoleAssignmentListItemsWithStatus) {
            $workspaceRoleAssignmentPath = "$($workspaceRoleAssignmentItemWithStatus.'Workspace Name')\$($workspaceRoleAssignmentItemWithStatus.'Group Name')\$($workspaceRoleAssignmentItemWithStatus.role)" 
            if ( $workspaceRoleAssignmentItemWithStatus.Status -notlike "Invalid*" -and $workspaceRoleAssignmentItemWithStatus.Status -notlike "Failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$workspaceRoleAssignmentItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $updatedWorkspaceListItemWithStatus = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared ", $workspaceRoleAssignmentItemWithStatus.Status, " status for workspace role assignment ", $workspaceRoleAssignmentPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $workspaceRoleAssignmentItemWithStatus.Status, " status for workspace role assignment ", $workspaceRoleAssignmentPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            }
        }
        $hadStatus = $true
    }

#endregion UPDATE WORKSPACE ROLE ASSIGNMENTS LIST    

#region PROCESS WORKSPACE ROLE ASSIGNMENTS COMMANDS

    # get the sharepoint workspace role assignment list items that have a pending command
    $hadCommand = $false
    $workspaceRoleAssignmentsListItemsWithCommand = $workspaceRoleAssignmentsListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    if ($workspaceRoleAssignmentsListItemsWithCommand.Count -gt 0) {
        $workspaceRoleAssignmentsListItemsWithCommand | Format-Table
        $hadCommand = $true
    }
    else {
        Write-Host+ -Iff $($updatedWorkspaceRoleAssignmentList -or $hadStatus)
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> noop" -ForegroundColor DarkGray
        $hadCommand = $false
    }

    foreach ($workspaceRoleAssignmentsListItem in $workspaceRoleAssignmentsListItemsWithCommand) {

        if ($null -eq $workspaceRoleAssignmentsListItem.Command -or $workspaceRoleAssignmentsListItem.Command -notin @("Add", "Remove", "Update")) { continue }

        $workspace = Get-Workspace -Tenant $global:Fabric.Tenant -Name $workspaceRoleAssignmentsListItem.'Workspace Name'
        $azureADGroup = $azureADGroups | Where-Object { $_.displayName -eq $workspaceRoleAssignmentsListItem.'Group Name'}    

        # create a piped path string to use for workspace role assignments
        # format:  <workspace> | <group> | <role>
        $workspaceRoleAssignmentText = "$($workspaceRoleAssignmentsListItem.'Workspace Name') | $($workspaceRoleAssignmentsListItem.'Group Name')" 
        
        # get Azure AD 
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $workspaceRoleAssignmentsListItem.Command, " workspace role assignment ", $workspaceRoleAssignmentText  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue

        if ($workspaceRoleAssignmentsListItem.Command -eq "Add") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Adding role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
            $workspaceRoleAssignment = Add-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id -Role $workspaceRoleAssignmentsListItem.Role
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Workspace Role Assignment ID" -Value $workspaceRoleAssignment.id 
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Added role"   
            $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "     
            Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Add" -Status "Success" -Message "Added workspace role assignment for $workspaceRoleAssignmentText" -EntryType "Information" -Force     
        }
        else {

            # for the Remove and Update commands, verify that the workspace role assignment exists
            $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id
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
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Updated role"   
                    $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "     
                    Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Update" -Status "Success" -Message "Updated workspace role assignment for $workspaceRoleAssignmentText" -EntryType "Information" -Force 
                } 

            }
            else {

                $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Invalid role"   
                # $_updatedSharePointListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "     
                Write-Log -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action $workspaceRoleAssignmentsListItem.Command -Status "Failure" -Message "Unable to find workspace role assignment $workspaceRoleAssignmentText" -EntryType "Error" -Force 

            }
        }
    }

#endregion PROCESS WORKSPACE ROLE ASSIGNMENTS COMMANDS    

Write-Host+; Write-Host+
Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> end of line" -ForegroundColor DarkGray
Write-Host+
