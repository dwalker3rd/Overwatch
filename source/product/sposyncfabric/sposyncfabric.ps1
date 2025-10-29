#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param(
    [switch]$Debug
)

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

#region LOCAL FUNCTIONS

    function Update-SharepointListItemHelper {

        param(
            [Parameter(Mandatory=$true,Position=0)][object]$Site,
            [Parameter(Mandatory=$true,Position=1)][object]$List,
            [Parameter(Mandatory=$true,Position=2)][object]$ListItem,
            [Parameter(Mandatory=$false)][string]$ColumnDisplayName,
            [Parameter(Mandatory=$false)][object]$Value,
            [Parameter(Mandatory=$false)][switch]$Status
        )                   

        if ($Status) {
            $ColumnDisplayName = "Status"
        }

        # get column data
        $_columns = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $Site -List $List
        $_column = $_columns | Where-Object { $_.DisplayName -eq $ColumnDisplayName }
        $columnName = $_column.Name
        $columnDisplayName = $_column.displayName

        # if the column is a lookup column
        # get the id from the source column
        if ($_column.lookup) {
            $sourceListId = $_column.lookup.ListId
            $sourceList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $Site -List $sourceListId 
            $sourceColumns = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $Site -List $sourceList
            $sourceColumn = $sourceColumns | Where-Object { $_.name -eq $_column.lookup.columnName}
            $sourceColumnName = $sourceColumn.displayName
            $sourceListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $Site -List $sourceList
            $sourceListItem = $sourceListItems | Where-Object { $_."$sourceColumnName" -eq $Value }
            $columnName += "LookupId"
            $Value = $sourceListItem.Id
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

        return $_listItem

    }

    # helper function for writing to a sharepoint list "log"
    function Write-Log+ {

        param (
            [Parameter(Mandatory=$false)][string]$Context = $($global:Product.Id),
            [Parameter(Mandatory=$false)][string]$Message,
            [Parameter(Mandatory=$false)][ValidateSet("Information","Warning","Error","Verbose","Debug","Event")][string]$EntryType = 'Information',
            [Parameter(Mandatory=$false)][string]$Action="Log",
            [Parameter(Mandatory=$false)][string]$Status,
            [Parameter(Mandatory=$false)][string]$Target,
            [switch]$Force
        )

        $params = @{
            Context = $Context
            Target = $Target
            Action = $Action
            Status = $Status
            Message = $Message
            EntryType = $EntryType
            Force = $Force.IsPresent
        }

        Write-Log @params  
        
        $body = @{ 
            fields = @{ 
                $_columnNameLogEntryType = $EntryType
                $_columnNameLogAction = $Action
                $_columnNameLogTarget = $Target
                $_columnNameLogStatus = $Status
                $_columnNameLogMessage = $Message                    
            }
        }
        $_updatedListItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $logList -ListItemBody $body 

        return

    }
    
    function Approve-InteractiveExecution {

        param(
            [Parameter(Mandatory=$true,Position=0)][string]$ProductId,
            [switch]$Quiet
        )    

        # initialize the return object
        $_decision = @{
            isExecutionInteractive = $false     # is this execution interactive?
            productId = $ProductId              # id of product being executed
            platformTask = $null                # the platform task status upon entering this function
            continue = $true                    # indicates whether the interactive execution should continue
            decisionCode = $null                # the code of the decision
            decisionText1 = $null               # line 1 of the decision text
            decisionText2 = $null               # line 2 of the decision text
        }   
        
        $platformTask = $null
        $isExecutionInteractive = [System.Environment]::UserInteractive
        $_decision.isExecutionInteractive = $isExecutionInteractive

        # if this is an interactive execution
        if ($isExecutionInteractive) {
        
            $platformTask = Get-PlatformTask -Id $ProductId
            $_decision.platformTask = $platformTask
            $platformTaskStatusColor = $platformTask.Status -in $global:PlatformStatusColor.Keys ? $global:PlatformStatusColor.$($platformTask.Status) : "DarkGray"        

            # deal with return possibilities from get-platformtask
            if (!$platformTask -or $platformTask.count -gt 1 -or $platformTask.ProductID -ne $ProductId) {
                $_decision.continue = $true
                $_decision.decisionCode = "NOTFOUND"
                $_decision.decisionText1 = "Platform task not found"
            }
            else {               
            
                # platform task is already disabled
                if ($platformTask.Status -eq "Disabled") {
                    $_decision.continue = $true
                    $_decision.decisionCode = "DISABLED"
                    $_decision.decisionText1 = "Platform task status is disabled"
                }

                # platform task is running or queued to run
                elseif ($platformTask.Status -in @("Queued", "Running")) {
                    $_decision.continue = $false
                    $_decision.decisionCode = "NOTALLOWED"
                    $_decision.decisionText1 = "Platform task Status precludes execution"
                    $_decision.decisionText2 = "Platform task is $($global:ConsoleSequence.ForegroundGreen)$($platformTask.Status.ToUpper())$($global:consoleSequence.Default)"
                }

                elseif (($platformTask.ScheduledTaskInfo.NextRunTime - [datetime]::Now) -le $global:Product.Config.AverageRunTime ) {
                    $_decision.continue = $false
                    $_decision.decisionCode = "NOTALLOWED"
                    $_decision.decisionText1 = "Platform task NextRunTime precludes execution"
                    $_decision.decisionText2 = "Next run time is $($platformTask.ScheduledTaskInfo.NextRunTime.ToString('u'))"
                }

                # platform task is enabled but not running (or queued to run)
                else {
                    $_decision.continue = $true
                    $_decision.decisionCode = "CONTINUE"
                    $_decision.decisionText1 = "Platform task status acceptable"                      
                }

            }
        }

        return $_decision

    }

#endregion LOCAL FUNCTIONS   

#region INTERACTIVE EXECUTION DECISION

    $productStartTime = [datetime]::Now

    # if this is an interactive execution, determine if it can continue
    # conditions:
    #   - platform task is not running or queued to run
    #   - platform task is not about to run ($global:Product.Config.AverageRuntime)

    $decision = Approve-InteractiveExecution -ProductId $overwatchProductId

    if (!$decision.continue) {
        $platformTask = $decision.platformTask
        $platformTaskStatusColor = $platformTask.Status -in $global:PlatformStatusColor.Keys ? $global:PlatformStatusColor.$($platformTask.Status) : "DarkGray"
        $message = "<$($platformTask.displayName) <.>48> $($platformTask.Status.ToUpper())"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,$platformTaskStatusColor       
        Write-Host+ -NoTrace -NoSeparator $decision.decisionCode, ": ", $decision.decisionText1 -ForegroundColor DarkRed, DarkGray, DarkGray
        if (![string]::IsNullOrEmpty($decision.decisionText2)) {
            Write-Host+ -NoTrace -NoSeparator $decision.decisionCode, ": ", $decision.decisionText2 -ForegroundColor DarkRed, DarkGray, DarkGray
        }
        Write-Host+
        return 
    } 

#endregion INTERACTIVE EXECUTION DECISION    

#region CONNECTIONS

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

#endregion CONNECTIONS

#region CACHE    

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

#endregion CACHE

#region SHAREPOINT LOG

    $logList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Log.Name
    $logListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $logList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # get sharepoint log list items' [internal] column names
    $_columnNamesLog = Get-SharePointSiteListColumns -Tenant $global:SharePoint.Tenant -Site $site -List $logList
    $_logNameMessageColumn = $_columnNamesLog | Where-Object { $_.DisplayName -eq 'Message' }; $_columnNameLogMessage = $_logNameMessageColumn.Name
    $_logNameEntryTypeColumn = $_columnNamesLog | Where-Object { $_.DisplayName -eq 'EntryType' }; $_columnNameLogEntryType = $_logNameEntryTypeColumn.Name
    $_logNameActionColumn = $_columnNamesLog | Where-Object { $_.DisplayName -eq 'Action' }; $_columnNameLogAction = $_logNameActionColumn.Name
    $_logNameTargetColumn = $_columnNamesLog | Where-Object { $_.DisplayName -eq 'Target' }; $_columnNameLogTarget = $_logNameTargetColumn.Name
    $_logNameStatusColumn = $_columnNamesLog | Where-Object { $_.DisplayName -eq 'Status' }; $_columnNameLogStatus = $_logNameStatusColumn.Name

#endretion SHAREPOINT LOG

#region AUTO-PROVISIONING TEMPLATES

    $autoProvisionGroupsList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.AutoProvisioning.GroupsandRoles.Name
    $autoProvisionGroupsListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $autoProvisionGroupsList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    foreach ($autoProvisionGroupsListItem in $autoProvisionGroupsListItems) {
        $_isValid = $autoProvisionGroupsListItem.'Group Name' -match '^(?:[^<>]*|[^<>]*<workspaceName>[^<>]*)$'
        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $autoProvisionGroupsList -ListItem $autoProvisionGroupsListItem -Status -Value ($_isValid ? "Valid" : "Invalid")
    }

#endretion AUTO-PROVISIONING TEMPLATES

#region GET CAPACITY LIST

    # get sharepoint capacity list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Capacities.Name -ForegroundColor DarkGray, DarkBlue
    $capacityList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Capacities.Name
    $capacityListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $capacityList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show the sharepoint capacity list items
    $capacityListItems | Format-Table -Property @("ID", "Capacity Name", "SKU", "Region", "State", "Capacity ID")

#endregion GET CAPACITY LIST

#region UPDATE CAPACITY LIST    

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
            $message = "Added capacity instance $($unlistedCapacity.displayName) to SharePoint list $($capacityList.DisplayName)"
            Write-Log+ -Context $overwatchProductId -Target "Capacity" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force            
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

#endregion UPDATE CAPACITY LIST

#region GET WORKSPACE LIST

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

#endregion GET WORKSPACE LIST

#region UPDATE WORKSPACE LIST

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
        $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $workspaceList -ListItem $removeWorkspaceItem  
        $message = "Removed workspace $($removeWorkspaceItem.'Workspace Name') from SharePoint list $($workspaceList.DisplayName)"
        Write-Log+ -Context $overwatchProductId -Target "WorkspaceSiteListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force   
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed workspace item ", $removeWorkspaceItem.'Workspace Name', " from SharePoint list ", $workspaceList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue     
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
            if ( $workspaceListItemWithStatus.Status -notlike "*invalid*" -and $workspaceListItemWithStatus.Status -notlike "*failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$workspaceListItemWithStatus.Modified
                if ($sinceModified.TotalSeconds -gt $statusTimeToLiveInSeconds) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared status for workspace ", $workspaceListItemWithStatus.'Workspace Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            # else {
            #     Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $workspaceListItemWithStatus.Status, " status for workspace ", $workspaceListItemWithStatus.'Workspace Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            # }
        }
        $hadUpdate = $true
    }

#endregion UPDATE WORKSPACE LIST   

#region PROCESS WORKSPACE COMMANDS

    # auto-provision groups initialization
    $autoProvisionGroups = [PSCustomObject]@()

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

        if ($null -eq $workspaceListItemWithCommand.Command -or $workspaceListItemWithCommand.Command -notin @("Create", "Rename", "Assign")) { continue }

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
                        $message = "Created workspace $($workspaceListItemWithCommand.'Workspace Name')"
                        Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "New" -Status "Success" -Message $message -EntryType "Information" -Force 
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Created workspace ", $workspace.displayName -ForegroundColor DarkGray, DarkBlue                       
                        
                        if ($workspace) {

                            # add sharepoint list item Workspace ID
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Workspace ID" -Value $workspace.id
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Created workspace"   
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   

                            #region AUTOPROVISION GROUPS
                            
                                # auto-provision groups
                                foreach ($autoProvisionGroupsListItem in $autoProvisionGroupsListItems) {
                                    $autoProvisionGroups += [PSCustomObject]@{
                                        workspaceName = $workspace.displayName
                                        groupName = $autoProvisionGroupsListItem.'Group Name' -replace "<workspaceName>", $workspace.displayName
                                        role = $autoProvisionGroupsListItem.Role
                                    }
                                }
                                # $autoProvisionGroups += [PSCustomObject]@{ workspaceName = $workspace.displayName; groupName = "$($workspace.displayName) - Gold"; role = "Contributor" }
                                # $autoProvisionGroups += [PSCustomObject]@{ workspaceName = $workspace.displayName; groupName = "$($workspace.displayName) - Data Contributors"; role = "Contributor" }
                                # $autoProvisionGroups += [PSCustomObject]@{ workspaceName = $workspace.displayName; groupName = "Data Curators"; role = "Member" }
                                # $autoProvisionGroups += [PSCustomObject]@{ workspaceName = $workspace.displayName; groupName = "Fabric Admin"; role = "Admin" }                                

                            #endregion AUTOPROVISION GROUPS                                
                            
                        }
                        else {
                            
                            # failed to create the workspace
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Create workspace failed"   
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "   
                            $message = "Failed to create workspace $($workspaceListItemWithCommand.'Workspace Name')"
                            Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "New" -Status "Failure" -Message $message -EntryType "Error" -Force
                            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to create workpace ", $($workspace.displayName) -ForegroundColor DarkRed, DarkBlue 
                            
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
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Status" -Value "Invalid Workspace ID"   
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " " 
                        $message = "Workspace $($workspaceListItemWithCommand.'Workspace Name') not found"
                        Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "Get" -Status "Failure" -Message $message -EntryType "Error" -Force
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Workspace ", $workspaceListItemWithCommand.'Workspace Name', ": ", "not found" -ForegroundColor DarkYellow
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Invalid Workspace ID ", $workspaceListItemWithCommand.'Workspace ID' -ForegroundColor DarkRed                        
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
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Renamed workspace"   
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "  
                                $message = "Renamed workspace $($workspaceListItemWithCommand.'Workspace Name')"
                                Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "Rename" -Status "Success" -Message $message -EntryType "Information" -Force
                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Renamed workspace from ", $oldWorkspaceDisplayName, " to ", $newWorkspaceDisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue  
                            }
                            else {
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Rename workspace failed"   
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " "  
                                $message = "Failed to rename workspace $($workspaceListItemWithCommand.'Workspace Name')"
                                Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "Rename" -Status "Failure" -Message $message -EntryType "Error" -Force
                                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to rename workspace: ", $workspace.displayName -ForegroundColor DarkRed                                
                            }
                        }
                    }

                #endregion RENAME WORKSPACE                    

            }
        }
    
        #region ASSIGN CAPACITY

            if ($workspace -and $workspaceListItemWithCommand.Command -in ("Create", "Assign")) {
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
                            if ($workspaceListItemWithCommand.Command -eq "Assign") {
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Assigned capacity"  
                                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " " 
                            }
                            $message = "Assigned capacity $($Capacity.displayName) to workspace $($workspace.displayName)"
                            Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Success" -Message $message -EntryType "Information" -Force  
                            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Assigned capacity ", $($Capacity.displayName), " to workspace ", $($workspace.displayName) -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue                 
                        }
                        else {
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Assign capacity failed" 
                            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " " 
                            $message = "Failed to assign capacity $($Capacity.displayName) to workspace $($workspace.displayName)"
                            Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Failure" -Message $message -EntryType "Error" -Force 
                            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Failed to assign capacity ", $($Capacity.displayName), " to workspace ", $($workspace.displayName) -ForegroundColor DarkRed
                        }
                    }
                    else {
                        # the capacity name field in the sharepoint list item is NOT valid
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -Status -Value "Invalid capacity"   
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceList -ListItem $workspaceListItemWithCommand -ColumnDisplayName "Command" -Value " " 
                        $message = "Capacity $($Capacity.displayName) was not found"
                        Write-Log+ -Context $overwatchProductId -Target "Workspace" -Action "AssignCapacity" -Status "Error" -Message $message -EntryType "Error" -Force 
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Capacity ", $($capacity.displayName), "NOT FOUND" -ForegroundColor DarkRed                    
                    }
                }
            }

        #endregion ASSIGN CAPACITY

    }

    Write-Host+

#endregion PROCESS WORKSPACE COMMANDS

#region GET USER LIST

    # get sharepoint user list items
    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Getting data from SharePoint list ", $global:SharePoint.List.Users.Name -ForegroundColor DarkGray, DarkBlue
    $userList = Get-SharePointSiteList -Tenant $global:SharePoint.Tenant -Site $site -List $global:SharePoint.List.Users.Name
    $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns

    # show sharepoint user list items
    $userListItems | Format-Table -Property $global:SharePointView.User.Default

#endregion GET USER LIST   

#region UPDATE USER LIST

    $hadUpdate = $false
    foreach ($userListItem in $userListItems) {

        $azureADUser = $azureADUsers | Where-Object { $_.mail -eq $userListItem.'User Email'}

        # update Sharepoint list item User ID when blank
        # this is done here b/c later updates rely on list item User ID
        # lookup azure AD user with list item User Email
        # no action if both list item User ID and User Email are blank
        if ([string]::IsNullOrEmpty($userListItem.'User ID') -and ![string]::IsNullOrEmpty($userListItem.'User Email')) {
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "User ID" -Value $azureADUser.id
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Updated user"
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Update ", "User ID", " for user ", $userListItem.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            $hadUpdate = $true
        }

        # if listed user isn't in Azure AD, remove it from the list
        if (!$azureADUser) {
            $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ListItem $userListItem  
            if ($removeResponse.error) {            
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Unable to remove non-existent user ", $userListItem.'User Email', " from SharePoint list ", $userList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                Write-Host+ -NoTimestamp -NoTrace $removeResponse.error.message -ForegroundColor DarkGray
                $message = "Unable to remove non-existent user $($userListItem.'User Email') from SharePoint list $($userList.DisplayName)"
                Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Failure" -Message $message -EntryType "Error" -Force  
                Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Failure" -Message $removeResponse.error.message -EntryType "Error" -Force 
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed non-existent user ", $userListItem.'User Email', " from SharePoint list ", $userList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                $message = "Removed non-existent user $($userListItem.'User Email') from SharePoint list $($userList.DisplayName)"
                Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force        
                $hadUpdate = $true     
            }           
        }
    } 

    # refresh sharepoint user list items
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Users.Name -ForegroundColor DarkGray, DarkBlue
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
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Updated user"
                $message = "Repaired `"User Email`" for user $($azureADUser.mail)"
                Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Repair" -Status "Success" -Message $message -EntryType "Information" -Force                 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Repaired ", "User Email", " for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                $hadUpdate = $true
            }    

            # remove accounts that don't have an email address
            # this is a proxy for checking the account types
            # if $azureADUser.mail is null, this isn't an account to be tracking
            if ([string]::IsNullOrEmpty($azureADUser.mail)) {
                $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ListItem $userListItem              
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed user item ", $userListItem.'User Name', " from SharePoint list ", $userList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                $message = "Removed user $($userListItem.'User Name') from SharePoint list $($userList.DisplayName)"
                Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force        
                $hadUpdate = $true
            }        

            # update sharepoint list item when $azureADUser.accountenabled does not match Account Status
            if ($($userListItem.'Account Status' -eq "Enabled") -ne $azureADUser.accountEnabled) {
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -ColumnDisplayName "Account Status" -Value $($azureADUser.accountEnabled ? "Enabled" : "Disabled")   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Updated user"
                $message = "Updated `"Account Status`" for user $($azureADUser.mail)"
                Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated ", "`"Account Status`"", " for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue           
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
                        $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Updated user"
                        $message = "Updated `"External User State`" for user $($azureADUser.mail)"
                        Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force
                        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated ", "`"External User State`"", " for user ", $azureADUser.mail -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
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
                    $message = "Added user $($azureADUser.mail.ToLower()) from Azure AD"
                    Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force                                 
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator $message -ForegroundColor DarkGray, DarkBlue, DarkGray
                }
                else {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItem -Status -Value "Failed to add user" 
                    $message = "Failed to add user $($azureADUser.mail.ToLower()) from Azure AD"
                    Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Add" -Status "Failure" -Message $message -EntryType "Error" -Force 
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator $message -ForegroundColor DarkRed            
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
            if ( $userListItemWithStatus.Status -notlike "*invalid*" -and $userListItemWithStatus.Status -notlike "*failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$userListItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $userList -ListItem $userListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared status for user ", $userListItemWithStatus.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            # else {
            #     Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $userListItemWithStatus.Status, " status for user ", $userListItemWithStatus.'User Email' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            # }
        }
        $hadUpdate = $true
    }    

    # refresh sharepoint user list items
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Users.Name -ForegroundColor DarkGray, DarkBlue
        $userListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $userList -ExcludeColumn $global:SharePoint.List.ExcludeColumns -IncludeColumn $global:SharePoint.List.IncludeColumns
        $userListItems | Format-Table -Property $global:SharePointView.User.Default
    }    

#endregion UPDATE USER LIST  

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
        $azureADUser = $null
        if (![string]::IsNullOrEmpty($userListItem.'User ID')) {
            $azureADUser = Get-AzureADUser -Tenant $global:Fabric.Tenant -User $userListItem.'User ID'
        }
        if ($azureADUser) {

            # enable/disable azureADUser account 
            if ($userListItem.Command -in @("Enable", "Disable")) {
                if ($userListItem.Command -eq "Enable") {
                    Enable-AzureADUser -Tenant $global:Fabric.Tenant -User $azureADUser
                    $message = "Enabled account for user $($azureADUser.displayName)" 
                    Write-Log+ -Context $overwatchProductId -Target "User" -Action "Enable" -Status "Success" -Message $message -EntryType "Information" -Force
                }
                elseif ($userListItem.Command -eq "Disable") {
                    Disable-AzureADUser -Tenant $global:Fabric.Tenant -User $azureADUser
                    $message = "Disabled account for user $($azureADUser.displayName)" 
                    Write-Log+ -Context $overwatchProductId -Target "User" -Action "Disable" -Status "Success" -Message $message -EntryType "Information" -Force
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
                $message = "Renamed `"User Name`" from $currentAzureADUserName to $($azureADUser.displayName)"
                Write-Log+ -Context $overwatchProductId -Target "User" -Action "Rename" -Status "Success" -Message $message -EntryType "Information" -Force             
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
                $message = "Invited $($azureADUser.displayName) to tenant $($global:Fabric.Tenant)"
                Write-Log+ -Context $overwatchProductId -Target "User" -Action "Invite" -Status "Success" -Message $message -EntryType "Information" -Force          
            }
            $updatedAzureADUsers = $true

        }

    }

    # if any Azure AD user was created/updated/removed,
    # regresh the Overwatch Azure AD user cache
    if ($updatedAzureADUsers) {
        Write-Host+
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing ", "Azure AD Users" -ForegroundColor DarkGray, DarkBlue
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Users -Quiet
        $azureADUsers, $cacheError = Get-AzureAdUsers -Tenant $global:Fabric.Tenant -AsArray
    }  
    
    Write-Host+

#endregion PROCESS USER COMMANDS

#region GET GROUP LISTS

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

#endregion GET GROUP LISTS

#region UPDATE GROUP LIST    

    $hadUpdate = $false
    
    # for each Azure AD group not in the sharepoint group list 
    # create a new sharepoint group list item 
    foreach ($_azureADGroup in $azureADGroups) {
        $azureADGroup = Get-AzureADGroup -Tenant $global:Fabric.Tenant -Id $_azureADGroup.id
        if (!$azureADGroup.error) {
            $groupListItem = $groupListItems | Where-Object { $_.'Group ID' -eq $azureADGroup.id}
            if (!$groupListItem) {
                $body = @{
                    fields = @{
                        $_columnNameGroupGroupName = $azureADGroup.displayName
                        $_columnNameGroupGroupId = $azureADGroup.id
                        $_columnNameGroupStatus = "Added group"
                    }
                }
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItemBody $body 
                $message = "Added group $($azureADGroup.displayName) to SharePoint list $($groupList.Name)"
                Write-Log+ -Context $overwatchProductId -Target "Group" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force                 
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
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItemWithMissingName -Status -Value "Repaired group name"
            $message = "Repaired $($groupListItemWithMissingName.'Group Name') group name"
            Write-Log+ -Context $overwatchProductId -Target "GroupListItem" -Action "Repair" -Status "Success" -Message $message -EntryType "Information" -Force
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
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItemWithMissingId -Status -Value "Repaired group id"
            $message = "Repaired $($groupListItemWithMissingId.'Group Name') group id" 
            Write-Log+ -Context $overwatchProductId -Target "GroupListItem" -Action "Repair" -Status "Success" -Message $message -EntryType "Information" -Force            
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
    $removeGroupListItems = $groupListItems | Where-Object {$_.'Group ID' -notin $azureADGroups.id -and [string]::IsNullOrEmpty($_.Command) }
    foreach ($removeGroupListItem in $removeGroupListItems) {
        $removedGroupName = ![string]::IsNullOrEmpty($removeGroupListItem.'Group Name') ? $removeGroupListItem.'Group Name' : "<group name is blank>"
        $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ListItem $removeGroupListItem         
        $message = "Removed group $($removedGroupName) from SharePoint list $($groupList.name)"
        Write-Log+ -Context $overwatchProductId -Target "GroupListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force               
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
            if ( $groupItemWithStatus.Status -notlike "*invalid*" -and $groupItemWithStatus.Status -notlike "*failed*" -and $groupItemWithStatus.Status -notlike "*dependency*" ) {
                $sinceModified = [datetime]::Now - [datetime]$groupItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared status for group ", $groupListItemsWithStatus.'Group Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            # else {
            #     Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $groupItemWithStatus.Status, " status for group ", $groupListItemsWithStatus.'Group Name' -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            # }
        }
        $hadUpdate = $true
    }

    # if the sharepoint group list was updated, refresh the sharepoint group list
    if ($hadUpdate) {
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing data from SharePoint list ", $global:SharePoint.List.Groups.Name -ForegroundColor DarkGray, DarkBlue
        $groupListItems = Get-SharePointSiteListItems -Tenant $global:SharePoint.Tenant -Site $site -List $groupList
        $groupListItems | Format-Table -Property $global:SharePointView.Group.Default
    }    

#endregion UPDATE GROUP LIST

#region PROCESS GROUP COMMANDS

    # get the sharepoint group list items that have a pending command
    $hadCommand = $false
    $groupListItemsWithCommand = @()
    $groupListItemsWithCommand += $groupListItems | Where-Object { ![string]::IsNullOrEmpty($_.Command) }
    $_autoProvisionGroups = $autoProvisionGroups | Where-Object { $_.'groupName' -notin $azureADGroups.displayName}
    foreach ($autoProvisionGroup in $_autoProvisionGroups ) {
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

        if ($null -eq $groupListItem.Command -or $groupListItem.Command -notin @("Create", "Delete", "Rename")) { 
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
                        $_columnNameGroupGroupName = $_newMailEnabledSecurityGroup.displayName
                        $_columnNameGroupGroupID = $_newMailEnabledSecurityGroup.ExternalDirectoryObjectId
                        $_columnNameGroupStatus = "Created group"
                    }
                }
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $groupList -ListItemBody $body                
            }

            $message = "Created group $($groupListItem.'Group Name')"
            Write-Log+ -Context $overwatchProductId -Target "Group" -Action "New" -Status "Success" -Message "Created new group $($groupListItem.'Group Name')" -EntryType "Information" -Force
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator $message -ForegroundColor DarkGray, DarkBlue            
            $updatedAzureADGroups = $true
        }

        # rename a mail-enabled security group
        if ($groupListItem.Command -eq "Rename" -and $azureADGroup) {
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> ", $groupListItem.Command, " group ", $groupListItem.'Group Name'  -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue 
            # get the group from Azure AD to get the actual displayName in case it's been renamed before
            $groupIdentityName = (Get-MailEnabledSecurityGroup -Identity $azureADGroup.displayName).name            
            $groupNewDisplayName = $groupListItem.'Group Name'
            $_updatedGroup = Rename-MailEnabledSecurityGroup -Identity $groupIdentityName -DisplayName $groupNewDisplayName 
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -Status -Value "Renamed"  
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Command" -Value $null 
            $message = "Renamed group $($originalDisplayName) to $($groupNewDisplayName)"
            Write-Log+ -Context $overwatchProductId -Target "Group" -Action "Rename" -Status "Success" -Message "Renamed group $originalDisplayName to $groupNewDisplayName" -EntryType "Information" -Force
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator $message -ForegroundColor DarkGray, DarkBlue, DarkGray
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

            if ($groupListItem.'Group ID' -in $workspaceRoleAssignments.principal.id) {
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -Status -Value "Role assignment dependency"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Command" -Value " "  
                $message = "Unable to delete group $($groupListItem.'Group Name') b/c of a workspace role assignment dependency"       
                Write-Log+ -Context $overwatchProductId -Target "Group" -Action "Delete" -Status "Failure" -Message $message -EntryType "Information" -Force
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Unable to delete group ", $groupListItem.'Group Name', " b/c of a workspace role assignment dependency" -ForegroundColor DarkGray, DarkBlue , DarkGray   
                continue
            }
            elseif ($azureADGroup.members) {
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -Status -Value "Membership dependency"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupList -ListItem $groupListItem -ColumnDisplayName "Command" -Value " "                 
                $message = "Unable to delete group $($groupListItem.'Group Name') b/c of a workspace role assignment dependency"
                Write-Log+ -Context $overwatchProductId -Target "Group" -Action "Delete" -Status "Failure" -Message $message -EntryType "Information" -Force
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Unable to delete group ", $groupListItem.'Group Name', " b/c of a group membership dependency" -ForegroundColor DarkGray, DarkBlue , DarkGray   
                continue            
            }
            Remove-MailEnabledSecurityGroup -Group $groupListItem.'Group ID' 
            $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupList -ListItem $groupListItem
            $message = "Deleted group $($groupListItem.'Group Name')"
            Write-Log+ -Context $overwatchProductId -Target "Group" -Action "Delete" -Status "Success" -Message $message -EntryType "Information" -Force
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Deleted group ", $groupListItem.'Group Name' -ForegroundColor DarkGray, DarkBlue
            $updatedAzureADGroups = $true            
        }

    }   

    # refresh Azure AD Group cache
    if ($updatedAzureADGroups) {
        Write-Host+
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing ", "Azure AD Groups" -ForegroundColor DarkGray, DarkBlue
        Start-Sleep -Seconds 15
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Quiet
        $azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
    }
    
    Write-Host+    

#endregion PROCESS GROUP COMMANDS

#region GET GROUP MEMBERSHIP LISTS

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

#endregion GET GROUP MEMBERSHIP LISTS   

#region UPDATE GROUP MEMBERSHIP LIST

    # create a new sharepoint list item for any Azure AD group member not in the Fabric Group Membership sharepoint list 
    $unlistedMembers = @()
    $hadUpdate = $false
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
                $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupMembershipList -ListItemBody $body
                $message = "Added $($azureADGroup.displayName) | $($userListItem.'User Email') from Azure AD to SharePoint list $($groupMembershipList.DisplayName)"
                Write-Log+ -Context $overwatchProductId -Target "GroupMembershipListItem" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added ", $($azureADGroup.displayName), " | ", $userListItem.'User Email', " from Azure AD to SharePoint list ", $groupMembershipList.DisplayName -ForegroundColor DarkGray, DarkBlue, DarkBlue, DarkBlue, DarkGray, DarkBlue
                $hadUpdate = $true
            }
        }
    }

    # if the user listed in the group membership list item isn't in Azure AD, remove the row from the group membership list
    foreach ($groupMembershipListItem in $groupMembershipListItems) {
        $azureADUser = $azureADUsers | Where-Object { $_.mail -eq $groupMembershipListItem.'User Email' }
        if (!$azureADUser) {
            $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $site -List $groupMembershipList -ListItem $groupMembershipListItem              
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed non-existent member ", $groupMembershipListItem.'User Email', " from group ", $groupMembershipListItem.'Group Name', " in Sharepoint list ", $groupMembershipList.displayName -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue, DarkGray, DarkBlue
            $message = "Removed non-existent user $($groupMembershipListItem.'User Email') from group $($groupMembershipListItem.'Group Name') in SharePoint list $($groupMembershipList.DisplayName)"
            Write-Log+ -Context $overwatchProductId -Target "UserListItem" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force        
            $hadUpdate = $true                
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
            if ( $groupMembershipListItemWithStatus.Status -notlike "*invalid*" -and $groupMembershipListItemWithStatus.Status -notlike "*failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$groupMembershipListItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $groupMembershipList -ListItem $groupMembershipListItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared status for group membership ", $groupMembershipPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            # else {
            #     Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $groupMembershipListItemWithStatus.Status, " status for group membership ", $groupMembershipPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            # }
        }
        $hadUpdate = $true
    }

#endregion UPDATE GROUP MEMBERSHIP LIST  

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
            $message = "Added user $($groupMembershipListItem.'User Email') to group $($groupMembershipListItem.'Group Name')"
            Write-Log+ -Context $overwatchProductId -Target "GroupMembership" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added user ", $($groupMembershipListItem.'User Email'), " to group ", $($groupMembershipListItem.'Group Name') -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            $updatedAzureADGroups = $true        
        }

        # remove user from group
        if ($groupMembershipListItem.Command -eq "Remove") {
            # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing user ", $groupMembershipListItem.'User Email', " from group ", $($groupMembershipListItem.'Group Name')   -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            Remove-MailEnabledSecurityGroupMember -Group $groupMembershipListItem.'Group Name' -Member $groupMembershipListItem.'User Email'
            $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $groupMembershipList -ListItem $groupMembershipListItem
            $message = "Removed user $($groupMembershipListItem.'User Email') from group $($groupMembershipListItem.'Group Name')"
            Write-Log+ -Context $overwatchProductId -Target "GroupMembership" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed user ", $($groupMembershipListItem.'User Email'), " from group ", $($groupMembershipListItem.'Group Name') -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            $updatedAzureADGroups = $true
        }    

    }

    # refresh Azure AD Group cache
    if ($updatedAzureADGroups) {
        Write-Host+
        Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Refreshing ", "Azure AD Groups" -ForegroundColor DarkGray, DarkBlue
        Start-Sleep -Seconds 15
        Update-AzureADObjects -Tenant $global:Fabric.Tenant -Type Groups -Quiet
        $azureADGroups, $cacheError = Get-AzureAdGroups -Tenant $global:Fabric.Tenant -AsArray
    }    

    Write-Host+

#endregion PROCESS GROUP MEMBERSHIP COMMANDS

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
            $groupListItem = $groupListItems | Where-Object { $_.'Group Name' -eq $_workspaceRoleAssignment.principal.displayName}  
            $body = @{
                fields = @{
                    $_columnNameWorkspaceRoleAssignmentsWorkspaceName = $workspaceListItem.id 
                    $_columnNameWorkspaceRoleAssignmentsGroupName = $groupListItem.id 
                    $_columnNameWorkspaceRoleAssignmentsRole = $_workspaceRoleAssignment.role 
                    $_columnNameWorkspaceRoleAssignmentsWorkspaceId = $_workspaceRoleAssignment.id
                }
            }
            $_listItem = New-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $workspaceRoleAssignmentsList  -ListItemBody $body 
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $($_workspaceRoleAssignment.principal.displayName) | $($_workspaceRoleAssignment.role)" 
            $message = "Added role assignment $($workspaceRoleAssignmentText) to SharePoint list $($workspaceRoleAssignmentsList.displayName) from Fabric"
            Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignmentListItem" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force                 
            Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added role assignment ", $workspaceRoleAssignmentText, " to SharePoint list ", $($workspaceRoleAssignmentsList.displayName), " from Fabric" -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue, DarkGray
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
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentList -ListItem $_workspaceRoleAssignmentsListItem -Status -Value "Repaired workspace name"
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $($_workspaceRoleAssignmentsListItem.'Group Name') | $($_workspaceRoleAssignmentsListItem.Role)" 
            $message = "Repaired workspace name in workspace role assignment $($workspaceRoleAssignmentText)"
            Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignmentListItem" -Action "Repair" -Status "Success" -Message $message -EntryType "Information" -Force    
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
            # if the group name was missing, it might be due to a renamed group.  so get the group from Azure AD to get the actual displayName
            $workspaceRoleAssignmentGroupDisplayName = (Get-AzureADGroup -Tenant $global:Fabric.Tenant -Id $workspaceRoleAssignment.principal.id).displayName
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $_workspaceRoleAssignmentsListItem -ColumnDisplayName "Group Name" -Value $workspaceRoleAssignmentGroupDisplayName
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentList -ListItem $_workspaceRoleAssignmentsListItem -Status -Value "Repaired group name"
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $workspaceRoleAssignmentGroupDisplayName | $($workspaceRoleAssignment.role)"
            $message = "Repaired group name in workspace role assignment $($workspaceRoleAssignmentText)"
            Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignmentListItem" -Action "Repair" -Status "Success" -Message $message -EntryType "Information" -Force              
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
            $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentList -ListItem $_workspaceRoleAssignmentsListItem -Status -Value "Repaired role"
            $workspaceRoleAssignmentText = "$($workspace.displayName) | $($workspaceRoleAssignment.principal.displayName) | $($workspaceRoleAssignment.role)" 
            $message = "Repaired role in workspace role assignment $($workspaceRoleAssignmentText)"
            Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignmentListItem" -Action "Repair" -Status "Success" -Message $message -EntryType "Information" -Force            
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
            if ( $workspaceRoleAssignmentItemWithStatus.Status -notlike "*invalid*" -and $workspaceRoleAssignmentItemWithStatus.Status -notlike "*failed*" ) {
                $sinceModified = [datetime]::Now - [datetime]$workspaceRoleAssignmentItemWithStatus.Modified
                if ($sinceModified -gt $global:SharePoint.ListItem.StatusExpiry) {
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentItemWithStatus -Status -Value $null  
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Cleared status for workspace role assignment ", $workspaceRoleAssignmentPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
                }
            }
            # else {
            #     Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Retained ", $workspaceRoleAssignmentItemWithStatus.Status, " status for workspace role assignment ", $workspaceRoleAssignmentPath -ForegroundColor DarkGray, DarkBlue, DarkGray, DarkBlue
            # }
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
            $_workspaceRoleAssignments = Get-WorkspaceRoleAssignments -Tenant $global:Fabric.Tenant -Workspace $workspace | Where-Object { $_.principal.type -eq "Group"}
            $workspaceRoleAssignment = $_workspaceRoleAssignments | Where-Object { $_.principal.displayName -eq $workspaceRoleAssignmentsListItem.'Group Name' }
            if (!$workspaceRoleAssignment) {

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
                $message = "Added workspace role assignment for $workspaceRoleAssignmentText"
                Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Add" -Status "Success" -Message $message -EntryType "Information" -Force   
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Added workspace role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue   
                
            }
            else {
                $message = "The group $($workspaceRoleAssignmentsListItem.'Group Name') already has a role assigned in the workspace"
                Write-Log+ -Context $overwatchProductId -Target "Workspace Role Assignment" -Action "Add" -Status "Failure" -Message $message -EntryType "Error" -Force
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "The group ", $($workspaceRoleAssignmentsListItem.'Group Name'), " already has a role assigned in the workspace" -ForegroundColor DarkGray, DarkBlue , DarkGray   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Invalid assignment"   
                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "  
            }  

        }
        else {

            # for the Remove and Update commands, verify that the workspace role assignment exists
            $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -Id $workspaceRoleAssignmentsListItem.'Workspace Role Assignment ID' # -PrincipalType "Group" -PrincipalId $azureADGroup.id
            if ($workspaceRoleAssignment) {

                if ($workspaceRoleAssignmentsListItem.Command -eq "Remove") {
                    # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
                    # $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id
                    $response = Remove-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -WorkspaceRoleAssignment $workspaceRoleAssignment
                    $removeResponse = Remove-SharePointSiteListItem -Tenant $global:SharePoint.Tenant -Site $Site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem
                    $message = "Removed workspace role assignment for $workspaceRoleAssignmentText"
                    Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Remove" -Status "Success" -Message $message -EntryType "Information" -Force 
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removed workspace role assignment for ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue  
                }

                if ($workspaceRoleAssignmentsListItem.Command -eq "Update") {
                    # Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Removing role assignment ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue
                    # $workspaceRoleAssignment = Get-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -PrincipalType "Group" -PrincipalId $azureADGroup.id
                    $response = Update-WorkspaceRoleAssignment -Tenant $global:Fabric.Tenant -Workspace $workspace -WorkspaceRoleAssignment $workspaceRoleAssignment -Role $workspaceRoleAssignmentsListItem.Role 
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Updated role"   
                    $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "   
                    $message = "Updated workspace role assignment for $workspaceRoleAssignmentText"
                    Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action "Update" -Status "Success" -Message $message -EntryType "Information" -Force
                    Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Updated workspace role assignment for ", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue  
                } 

            }
            else {

                $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -Status -Value "Invalid role"   
                # $_updatedListItem = Update-SharepointListItemHelper -Site $site -List $workspaceRoleAssignmentsList -ListItem $workspaceRoleAssignmentsListItem -ColumnDisplayName "Command" -Value " "    
                $message = "Unable to find workspace role assignment $workspaceRoleAssignmentText"
                Write-Log+ -Context $overwatchProductId -Target "WorkspaceRoleAssignment" -Action $workspaceRoleAssignmentsListItem.Command -Status "Failure" -Message $message -EntryType "Error" -Force 
                Write-Host+ -NoTimestamp -NoTrace -NoSeparator "Unable to find workspace role assignment", $workspaceRoleAssignmentText -ForegroundColor DarkGray, DarkBlue 

            }
        }
    }

#endregion PROCESS WORKSPACE ROLE ASSIGNMENTS COMMANDS   

#region LOG DIAGNOSTICS

    $productEndTime = [datetime]::Now
    $productRunTime = $productStartTime - $productEndTime

    if ($Debug) {
        Write-Log -Context $overwatchProductId -Target "Diagnostics" -Action "StartTime" -Status "Success" -Message $productStartTime.ToString('u')  -EntryType Information -Force
        Write-Log -Context $overwatchProductId -Target "Diagnostics" -Action "EndTime" -Status "Success" -Message $productEndTime.ToString('u')  -EntryType Information -Force
        Write-Log -Context $overwatchProductId -Target "Diagnostics" -Action "RunTime" -Status "Success" -Message $productRunTime.TotalSeconds  -EntryType Information -Force
    }

#endregion LOG DIAGNOSTICS    

Write-Host+; Write-Host+
Write-Host+ -NoTimestamp -NoTrace -NoSeparator "> end of line" -ForegroundColor DarkGray
Write-Host+
