
#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id="AzureProjects"}
. $PSScriptRoot\definitions.ps1

$resourceTypeMap = @{
    "Microsoft.Storage/storageAccounts" = "StorageAccount"
    "Microsoft.Storage/storageAccounts/*/blobServices/default/containers" = "StorageContainer"
    "Microsoft.Compute/virtualMachines" = "VM"
    "Microsoft.KeyVault/vaults" = "KeyVault"
    "Microsoft.DataFactory/factories" = "DataFactory"
    "Microsoft.Insights/components" = "ApplicationInsights"
    "Microsoft.Network/networkInterfaces" = "NetworkInterface"
    "Microsoft.Network/bastionHosts" = "Bastion"
    "Microsoft.MachineLearningServices/workspaces" = "MLWorkspace"
    "Microsoft.DocumentDB/databaseAccounts" = "CosmosDBAccount"
    "Microsoft.SqlVirtualMachine/SqlVirtualMachines" = "SqlVM"
    "Microsoft.Batch/BatchAccounts" = "BatchAccount"
}

#region SERVER CHECK

    # Do NOT continue if ...
    #   1. the host server is starting up or shutting down

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

#endregion SERVER CHECK

function Request-AzProjectVariable {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Default,
        [Parameter(Mandatory=$false)][string[]]$Suggestions,
        [Parameter(Mandatory=$false)][string[]]$Selections,
        [switch]$AllowNone,
        [switch]$Lowercase, [switch]$Uppercase
    )

    $_selections = @()
    $_selections += $Selections
    if ($AllowNone) {
        $_selections += "None"
    }

    if ($Suggestions.Count -gt 1) {
        Write-Host+ -NoTrace "Suggestions: $($Suggestions | Join-String -Separator ", " )" -ForegroundColor DarkGray
    }
    if ($AllowNone) {
        Write-Host+ -NoTrace "Enter 'None' to deselect $Name" -ForegroundColor DarkGray
    }
    if ([string]::IsNullOrEmpty($Default) -and $Suggestions.Count -eq 1) {
        $Default = $Suggestions[0]
    }

    $showSelections = $true
    do {
        $response = $null
        Write-Host+ -NoTrace -NoSeparator -NoNewLine $Name, $(![string]::IsNullOrEmpty($Default) ? " [$Default]" : ""), ": " -ForegroundColor Gray, Blue, Gray
        $response = Read-Host
        $response = ![string]::IsNullOrEmpty($response) ? $response : $Default
        if ($response -eq "?") { $showSelections = $true }
        if ($showSelections -and $_selections -and $response -notin $_selections) {
            Write-Host+ -NoTrace -NoNewLine "  $Name must be one of the following: " -ForegroundColor DarkGray
            if ($_selections.Count -le 5) {
                Write-Host+ -NoTrace -NoTimestamp ($_selections -join ", ") -ForegroundColor DarkGray
            }
            else {
                $itemsPerRow = 8
                Write-Host+
                for ($i = 0; $i -lt ($_selections.Count - ($_selections.Count % $itemsPerRow))/$itemsPerRow + 1; $i++) {
                    $selectionsRow = "    "
                    for ($j = $i*$itemsPerRow; $j -lt $i*$itemsPerRow+$itemsPerRow; $j++) {
                        $selectionsRow += ![string]::IsNullOrEmpty($_selections[$j]) ? "$($_selections[$j]), " : ""
                    }
                    if ($selectionsRow -ne "    ") {
                        if ($j -ge $_selections.Count) {
                            $selectionsRow = $selectionsRow.Substring(0,$selectionsRow.Length-2)
                        }
                        Write-Host+ -NoTrace $selectionsRow -ForegroundColor DarkGray
                    }
                }
            }
            $showSelections = $false
        }
    } until ($_selections ? $response -in $_selections : $response -ne $global:emptyString)

    if ($Lowercase) { $response = $response.ToLower() }
    if ($Uppercase) { $response = $response.ToUpper() }

    return $response

}

function Read-AzProjectVariable {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name
    )
    
    $iniContent = Get-Content $script:AzureProjectIniFile

    $value = $iniContent | Where-Object {$_ -like "$Name*"}
    if (![string]::IsNullOrEmpty($value)) {
        return $value.split("=")[1].Trim()
    } else {
        return
    }

}

function Write-AzProjectVariable {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Value,
        [switch]$Delete
    )

    if (!$Delete -and [string]::IsNullOrEmpty($Value)) {
        Write-Host+ -NoTrace "'Value' is a required field." -ForegroundColor DarkRed
        return
    }
    
    $iniContent = Get-Content $script:AzureProjectIniFile -Raw

    $valueUpdated = $false
    if (![string]::IsNullOrEmpty($iniContent)) {
        $targetDefinitionRegex = "($Name)\s?=\s?(.*)"
        if ($Delete) { $targetDefinitionRegex = "($Name)\s?=\s?" }
        $targetDefinition = [regex]::Match($iniContent,$targetDefinitionRegex).Groups[0].Value
        if (![string]::IsNullOrEmpty($targetDefinition)) {
            if ($Delete) {
                $iniContent = $iniContent -replace "$targetDefinition\r?\n", ""
            }
            else {
                $iniContent = $iniContent -replace $targetDefinition, "$Name = $Value"
            }
            Set-Content -Path $script:AzureProjectIniFile -Value $iniContent.Trim()
            $valueUpdated = $true
        }
    }
    if (!$valueUpdated -and !$Delete) {
        Add-Content -Path $script:AzureProjectIniFile -Value "$Name = $Value"
    }

    return

}

function global:Initialize-AzProject {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Tenant,
        [Parameter(Mandatory=$false)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$false)][Alias("Group")][string]$GroupName,
        [Parameter(Mandatory=$false)][string]$Prefix,
        [Parameter(Mandatory=$false)][Alias("Location")][string]$ResourceLocation,
        [Parameter(Mandatory=$false)][string]$DeploymentType,
        [switch]$Reinitialize
    )

    $azureProjectsConfig = (Get-Product "AzureProjects").Config

    if ([string]::IsNullOrEmpty($Tenant)) {
        $Tenant = Request-AzProjectVariable -Name "Tenant" -Selections (Get-AzureTenantKeys) -Lowercase
    }
    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant

    $subscriptionId = $global:Azure.$tenantKey.Subscription.Id
    $tenantId = $global:Azure.$tenantKey.Tenant.Id

    if ([string]::IsNullOrEmpty($GroupName)) {
        $groupNames = $global:Azure.Group.Keys
        $GroupName = Request-AzProjectVariable -Name "GroupName" -Suggestions $groupNames -Lowercase
    }

    if ([string]::IsNullOrEmpty($ProjectName)) {
        $ProjectName = Request-AzProjectVariable -Name "ProjectName" -Lowercase
    }

    $resourceGroupName = "$($GroupName)-$($ProjectName)-rg".ToLower()   

    if ([string]::IsNullOrEmpty($global:Azure.$tenantKey.MsGraph.AccessToken)) {
        Connect-AzureAD -Tenant $tenantKey
    }

    # add new group to Azure
    if (!$global:Azure.Group.$groupName) {
        $global:Azure.Group += @{
            $groupName = @{
                Name = $groupName
                DisplayName = $GroupName
                Location = @{
                    Data = "$($global:Azure.Location.Data)\$groupName"
                }
                Project = @{}
            }
        }
    }

    # create group directory
    if (!(Test-Path -Path $global:Azure.Group.$groupName.Location.Data)) {
        New-Item -Path $global:Azure.Location.Data -Name $groupName -ItemType "directory" | Out-Null
    }

    if ($global:Azure.Group.$groupName.Project.$projectName.Initialized) {
        Write-Host+ -NoTrace "WARN: Project `"$projectName`" has already been initialized." -ForegroundColor DarkYellow
        if (!($Reinitialize.IsPresent)) {
            Write-Host+ -NoTrace "INFO: To reinitialize project `"$projectName`", add the -Reinitialize switch."
            return
        }
        Write-Host+ -Iff $($Reinitialize.IsPresent) -NoTrace "WARN: Reinitializing project `"$projectName`"." -ForegroundColor DarkYellow
    }

    # Connect-AzAccount+
    # if the project's ConnectedAccount contains an AzureProfile, save it for reuse
    # otherwise, connect with Connect-AzAccount+ which returns an AzureProfile
    if ($global:Azure.Group.$groupName.Project.$projectName.ConnectedAccount) {
        Write-Host+ -Iff $($Reinitialize.IsPresent) -NoTrace "INFO: Reusing ConnectedAccount from project `"$projectName`"`."
        $_connectedAccount = $global:Azure.Group.$groupName.Project.$projectName.ConnectedAccount
    }
    else {
        $_connectedAccount = Connect-AzAccount+ -Tenant $tenantKey
    }

    # reinitializing the project, so remove the project from $global:Azure
    if ($global:Azure.Group.$groupName.Project.$projectName) {
        $global:Azure.Group.$groupName.Project.Remove($projectName)
    }

    # clear the global scope variable AzureProject as it points to the last initialized project
    Remove-Variable AzureProject -Scope Global -ErrorAction SilentlyContinue 

    #add new project to Azure
    $global:Azure.Group.$groupName.Project += @{
        $projectName = @{
            Name = $projectName
            DisplayName = $ProjectName
            GroupName = $groupName
            Location = @{
                Data = "$($global:Azure.Group.$groupName.Location.Data)\$projectName"
                Credentials = "$($global:Azure.Group.$groupName.Location.Data)\$projectName"
            }
            Initialized = $false
        }
    }
    
    #create project directory 
    if (!(Test-Path -Path $global:Azure.Group.$groupName.Project.$projectName.Location.Data)) {
        New-Item -Path $global:Azure.Group.$groupName.Location.Data -Name $projectName -ItemType "directory" | Out-Null
    }

    # copy resource file templates to new directory if files don't already exist
    New-AzProjectResourceFiles -Project $ProjectName

    $script:AzureProjectIniFile = "$($global:Azure.Group.$GroupName.Project.$ProjectName.Location.Data)\$ProjectName.ini"
    if (!(Test-Path $script:AzureProjectIniFile)) {
        New-Item -Path $script:AzureProjectIniFile -ItemType File | Out-Null
    }

    Write-AzProjectVariable -Name Tenant -Value $Tenant
    Write-AzProjectVariable -Name SubscriptionId -Value $subscriptionId
    Write-AzProjectVariable -Name TenantId -Value $tenantId
    Write-AzProjectVariable -Name GroupName -Value $GroupName
    Write-AzProjectVariable -Name ProjectName -Value $ProjectName
    Write-AzProjectVariable -Name ResourceGroupName -Value $resourceGroupName

    # get/read/update Prefix
    $prefixDefault = Read-AzProjectVariable -Name Prefix
    if ([string]::IsNullOrEmpty($Prefix) -and ![string]::IsNullOrEmpty($prefixDefault)) {
        $Prefix = $prefixDefault
    }
    if ([string]::IsNullOrEmpty($Prefix)) {
        $prefixes = 
            $global:Azure.Group.Keys | 
                Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                    Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.Prefix} |
                        Sort-Object -Unique
        $prefixes = $prefixes | Sort-Object -Unique
        $Prefix = Request-AzProjectVariable -Name "Prefix" -Suggestions $prefixes -Default $prefixDefault
    }
    Write-AzProjectVariable -Name Prefix -Value $Prefix

    # get/read/update ResourceLocation
    $resourceLocationDefault = Read-AzProjectVariable -Name ResourceLocation
    if ([string]::IsNullOrEmpty($ResourceLocation) -and ![string]::IsNullOrEmpty($resourceLocationDefault)) {
        $ResourceLocation = $resourceLocationDefault
    }
    if ([string]::IsNullOrEmpty($ResourceLocation)) {
        $resourceLocationSuggestions = 
            $global:Azure.Group.Keys | 
                Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                    Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.ResourceLocation} |
                        Sort-Object -Unique
        $azLocations = Get-AzLocation | Where-Object {$_.providers -contains "Microsoft.Compute"} | 
            Select-Object -Property displayName, location | Sort-Object -Property location                        
        $resourceLocationSelections = $azLocations.Location
        $ResourceLocation = Request-AzProjectVariable -Name "ResourceLocation" -Suggestions $resourceLocationSuggestions -Selections $resourceLocationSelections -Default $resourceLocationDefault
    }
    Write-AzProjectVariable -Name ResourceLocation -Value $ResourceLocation 

    $global:Azure.Group.$groupName.Project.$projectName += @{
        ConnectedAccount = $_connectedAccount
        DeploymentType = $null
        IniFile = $script:AzureProjectIniFile
        Invitation = @{
            Message = "You have been invited by $($global:Azure.$tenantKey.DisplayName) to collaborate on project $projectNameUpperCase."
        }
        Prefix = $Prefix
        ResourceLocation = $ResourceLocation
        ResourceType = @{
            ResourceGroup = @{
                Name = $azureProjectsConfig.Templates.Resources.ResourceGroup.Name.Pattern.replace("<0>",$groupName).replace("<1>",$projectName)
                Scope = "/subscriptions/$($global:Azure.$tenantKey.Subscription.Id)/resourceGroups/" + $azureProjectsConfig.Templates.Resources.ResourceGroup.Name.Pattern.replace("<0>",$groupName).replace("<1>",$projectName)
                Object = $null
            }
            BatchAccount = @{
                Name =  $azureProjectsConfig.Templates.Resources.BatchAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
                Context = $null
            }
            StorageAccount = @{
                Name =  $azureProjectsConfig.Templates.Resources.StorageAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
                Context = $null
                Parameters = @{}
            }
            StorageContainer = @{
                Name = "data"
                Scope = $null
                Object = $null
                Parameters = @{}
            }
            Bastion = @{
                Name = $azureProjectsConfig.Templates.Resources.Bastion.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
            }
            VM = @{
                Name = $azureProjectsConfig.Templates.Resources.VM.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName).replace("<2>","01")
                Admin = $azureProjectsConfig.Templates.Resources.VM.Admin.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
                NetworkInterface = @()
                Parameters = @{}
            }
            MLWorkspace = @{
                Name = $azureProjectsConfig.Templates.Resources.MLWorkspace.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            CosmosDBAccount = @{
                Name = $azureProjectsConfig.Templates.Resources.CosmosDBAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            SqlVM = @{
                Name = $azureProjectsConfig.Templates.Resources.SqlVM.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            KeyVault = @{
                Name = $azureProjectsConfig.Templates.Resources.KeyVault.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
            }
            DataFactory = @{
                Name = $azureProjectsConfig.Templates.Resources.DataFactory.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
            }
            ApplicationInsights = @{
                Name = $azureProjectsConfig.Templates.Resources.ApplicationInsights.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
            }
            NetworkInterface = @{
                Name = $azureProjectsConfig.Templates.Resources.NetworkInterface.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
            }
        }
    }

    $global:AzureProject = $global:Azure.Group.$groupName.Project.$projectName

    $global:AzureProject += @{
        ScopeBase = "/subscriptions/$($global:Azure.$tenantKey.Subscription.Id)/resourceGroups/$($global:AzureProject.ResourceType.ResourceGroup.Name)/providers"
    }

    $deploymentTypeDefault = Read-AzProjectVariable -Name DeploymentType
    if ([string]::IsNullOrEmpty($DeploymentType) -and ![string]::IsNullOrEmpty($deploymentTypeDefault)) {
        $DeploymentType = $deploymentTypeDefault
    }
    if ([string]::IsNullOrEmpty($DeploymentType)) {
        $deploymentTypeDefault = "Overwatch"
        $deploymentTypeSelections = @("Overwatch","DSVM")
        $DeploymentType = Request-AzProjectVariable -Name "DeploymentType" --Selections $deploymentTypeSelections -Default $deploymentTypeDefault
    }
    Write-AzProjectVariable -Name DeploymentType -Value $DeploymentType
    $global:AzureProject.DeploymentType = $DeploymentType

    $global:AzureProject.ResourceType.StorageAccount.Parameters = Get-AzProjectStorageAccountParameters
    $global:AzureProject.ResourceType.StorageContainer.Parameters = Get-AzProjectStorageContainerParameters
    switch ($DeploymentType) {
        "Overwatch" {
            Remove-AzProjectVmParameters
        }
        "DSVM" {
            $global:AzureProject.ResourceType.Vm.Parameters = Get-AzProjectVmParameters
        }
    }

    Set-AzProjectDefaultResourceScopes
    Get-AzProjectDeployedResources

    $global:AzureProject.Initialized = $true

    return

}
Set-Alias -Name azProjInit -Value Initialize-AzProject -Scope Global

function New-AzProjectResourceFiles {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    $UserImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-users-import.csv"
    if (!(Test-Path $UserImportFile)) {
        Set-Content -Path $UserImportFile -Value "`"signInName`",`"fullName`""
    }

    $GroupImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-groups-import.csv"
    if (!(Test-Path $GroupImportFile)) {
        Set-Content -Path $GroupImportFile -Value "`"group`",`"user`""
    }

    $ResourceImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
    if (!(Test-Path $ResourceImportFile)) {
        Set-Content -Path $ResourceImportFile -Value "`"resourceType`",`"resourceName`",`"resourceId`",`"resourceParent`""
    }

    $SecurityImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-securityAssignments-import.csv"
    if (!(Test-Path $SecurityImportFile)) {
        Set-Content -Path $SecurityImportFile -Value "`"resourceID`",`"role`",`"assigneeType`",`"assignee`""
    }

}

function Set-AzProjectDefaultResourceScopes {

    [CmdletBinding()]
    param()

    $global:AzureProject.ResourceType.BatchAccount.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Batch/BatchAccounts/$($global:AzureProject.ResourceType.BatchAccount.Name)"
    $global:AzureProject.ResourceType.StorageAccount.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Storage/storageAccounts/$($global:AzureProject.ResourceType.StorageAccount.Name)"
    $global:AzureProject.ResourceType.StorageContainer.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Storage/storageAccounts/$($global:AzureProject.ResourceType.StorageAccount.Name)/blobServices/default/containers/$($global:AzureProject.ResourceType.StorageContainer.Name)"
    $global:AzureProject.ResourceType.Bastion.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Network/bastionHosts/$($global:AzureProject.ResourceType.Bastion.Name)"
    $global:AzureProject.ResourceType.VM.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Compute/virtualMachines/$($global:AzureProject.ResourceType.VM.Name)"
    $global:AzureProject.ResourceType.MLWorkspace.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.MachineLearningServices/workspaces/$($global:AzureProject.ResourceType.MLWorkspace.Name)"
    $global:AzureProject.ResourceType.CosmosDBAccount.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.DocumentDB/databaseAccounts/$($global:AzureProject.ResourceType.CosmosDBAccount.Name)" 
    $global:AzureProject.ResourceType.SqlVM.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.SqlVirtualMachine/SqlVirtualMachines/$($global:AzureProject.ResourceType.SqlVM.Name)"
    $global:AzureProject.ResourceType.KeyVault.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.KeyVault/vaults/$($global:AzureProject.ResourceType.KeyVault.Name)"
    $global:AzureProject.ResourceType.DataFactory.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.DataFactory/factories/$($global:AzureProject.ResourceType.DataFactory.Name)"
    $global:AzureProject.ResourceType.ApplicationInsights.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Insights/components/$($global:AzureProject.ResourceType.ApplicationInsights.Name)"
    $global:AzureProject.ResourceType.NetworkInterface.Scope = "$($global:AzureProject.ScopeBase)/Microsoft.Network/networkInterfaces/$($global:AzureProject.ResourceType.NetworkInterface.Name)"

    return

}

function Get-AzProjectDeployedResources {

    [CmdletBinding()]
    param()

    $resourceGroups = Get-AzResourceGroup
    if ($resourceGroups | Where-Object {$_.ResourceGroupName -eq $global:AzureProject.ResourceType.ResourceGroup.Name}) {
        $global:AzureProject.ResourceType.ResourceGroup.Object = Get-AzResourceGroup -Name $global:AzureProject.ResourceType.ResourceGroup.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.BatchAccount.Object = Get-AzBatchAccount -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.BatchAccount.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.StorageAccount.Object = Get-AzStorageAccount -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.StorageAccount.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.StorageAccount.Context = New-AzStorageContext -StorageAccountName $global:AzureProject.ResourceType.StorageAccount.Name -UseConnectedAccount -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.StorageContainer.Object = Get-AzStorageContainer -Context $global:AzureProject.ResourceType.StorageAccount.Context -Name $global:AzureProject.ResourceType.StorageContainer.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.Bastion.Object = Get-AzBastion -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.Bastion.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.VM.Object = Get-AzVm -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.VM.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.CosmosDBAccount.Object = Get-AzCosmosDBAccount -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.CosmosDBAccount.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.SqlVM.Object = Get-AzSqlVM -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.SqlVM.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.KeyVault.Object = Get-AzKeyVault -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.KeyVault.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.DataFactory.Object = Get-AzDataFactory -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.DataFactory.Name -ErrorAction SilentlyContinue
        $global:AzureProject.ResourceType.ApplicationInsights.Object = Get-AzApplicationInsights -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.ApplicationInsights.Name -ErrorAction SilentlyContinue   
        $global:AzureProject.ResourceType.NetworkInterface.Object = Get-AzNetworkInterface -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.NetworkInterface.Name -ErrorAction SilentlyContinue   

        $mlWorkspaces = Get-AzResource -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name | Where-Object {$_.ResourceType -eq "Microsoft.MachineLearningServices/workspaces"}
        if ($mlWorkspaces) {
            # az login --output None # required until https://github.com/Azure/azure-cli/issues/20150 is resolved
            $global:AzureProject.ResourceType.MLWorkspace.Object = Get-AzMlWorkspace -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.MLWorkspace.Name -ErrorAction SilentlyContinue
        }
    }

}

function global:Export-AzProjectResourceFile {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        # [Parameter(Mandatory=$true)][Alias("ResourceGroup")][string]$ResourceGroupName,
        [switch]$Overwrite
    )

    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    $resourceGroupName = $global:AzureProject.ResourceType.ResourceGroup.Name

    $resourcesImported = @()
    $resourceImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
    if (Test-Path $resourceImportFile) {
        $resourcesImported += Import-AzProjectFile $resourceImportFile
    }

    $resources = @()
    foreach ($resource in (Get-AzResource -ResourceGroupName $resourceGroupName)) {

        $resourceType = $resourceTypeMap.$($resource.resourceType)
        
        if (![string]::IsNullOrEmpty($resourceType)) {

            $resourceName = $resource.resourceName
            $resourceObject = $null
            $resourceParent = $null

            $resourceChildren = @()

            switch ($resourceType) {
                {$_ -notin ("DataFactory")} {
                    $resourceName = $resource.resourceName
                    $resourceObject = Invoke-Expression "Get-Az$resourceType -ResourceGroupName $resourceGroupName -Name $resourceName"
                }
                "DataFactory" {
                    $resourceName = $resource.resourceName
                    $resourceObject = Get-AzDataFactory -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue
                    if (!$resourceObject) {
                        $resourceObject = Get-AzDataFactoryV2 -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue
                        if ($resourceObject) {
                            $resourceType = "DataFactoryV2"
                        }
                        else {
                            throw "The resource type could not be found in the namespace 'Microsoft.DataFactory'"
                        }
                    }
                }
                "NetworkInterface" {
                    $resourceParent = ($resourceObject.VirtualMachine.Id -split "/")[-1]
                }
                "StorageAccount" {
                    $storageAccountContext = New-AzStorageContext -StorageAccountName $resource.resourceName -UseConnectedAccount
                    foreach ($storageContainer in Get-AzStorageContainer -Context $storageAccountContext) {
                        if (($storageContainer.Name -split "-")[0] -notin ("bootdiagnostics","insights")) {
                            $resourceChildren += [PSCustomObject]@{
                                resourceType = "StorageContainer"
                                resourceName = $storageContainer.Name
                                resourceId = $storageContainer.Name
                                resourceParent = $resourceName
                            }
                        }
                    }
                }
            }

            $resources += [PSCustomObject]@{
                resourceType = $resourceType
                resourceName = $resourceName
                resourceId = $resourceName
                resourceParent = $resourceParent
            }
            $resources += $resourceChildren

        }
    }

    $resourcesDifferences = Compare-Object $resourcesImported $resources -Property resourceType, resourceName -PassThru
    $resourcesDifferences | Format-Table

    if ($resourcesDifferences.SideIndicator -contains "<=") {
        Write-Host+ -NoTrace "Some resources in the resource import file have not been deployed." -ForegroundColor DarkRed
        Write-Host+ -NoTrace "Verify resource deployment." -ForegroundColor DarkGray
    }
    elseif ($resourcesDifferences.SideIndicator -contains "=>") {
        Write-Host+ -NoTrace "Some deployed resources are not in the resource import file." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoNewLine "Update the resource import file (Y/N)? " -ForegroundColor Gray
        $response = Read-Host
        if ($response -eq "Y") {
            $resourcesImported += $resourcesDifferences | Select-Object -ExcludeProperty SideIndicator
            $resourcesImported | Export-Csv -Path $resourceImportFile -UseQuotes Always -NoTypeInformation
        }        
    }

    return

}

function global:Import-AzProjectFile {

    # alternative to Import-CSV which allows for comments in the project files
    # file format is standard CSV, first row is header row, powershell comments allowed

    # WARNING: This function uses ConvertFrom-String which uses the WinPSCompatSession (implicit remoting)
    # If the WinPSCompatSession is removed, ConvertFrom-String will fail on subsequents calls.  Therefore, 
    # NEVER use Remove-PSSession without ensuring that the WinPSCompatSession is excluded!

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path
    )

    if (!(Test-Path $Path)) {
        Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $Path -Leaf) not found." -ForegroundColor DarkRed
        return
    }

    # tokenize content using the PowerShell Language Parser
    $tokens = $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    $ast | Out-Null

    # remove comment tokens
    $tokens = $tokens | Where-Object {$_.Kind -ne "Comment"}

    # recreate the content
    $tokenText = @()
    foreach ($token in $tokens) {
        if ($token.Kind -eq "StringExpandable") {
            $diff = $token.Text -replace $token.Value
            if (![string]::IsNullOrEmpty($diff)) {
                $tokenValueAlwaysQuoted = $token.Value -match "[,]"
                if ($diff -in ('""',"''") -and !$tokenValueAlwaysQuoted) {
                    $tokenText += [string]::IsNullOrEmpty($token.Value) ? "" : $token.Value
                }
                else {
                    $tokenText += $token.Text
                }
            }
        }
        else {
            $tokenText += $token.Text
        }
    }
    $content = -join $tokenText

    # replace commas inside quoted strings with pipe character
    # this will be reverted after ConvertFrom-String
    $replacementDelimiter = "|"
    $content = $content -replace "\s*,\s*(?!(?:[^`"]*`"[^`"]*`")*[^`"]*$)", $replacementDelimiter

    # content is a string; convert to an array
    $content = $content -split '\r?\n'

    # property names are in the first row
    $propertyNames = ($content -split '\r?\n')[0] -split ","

    # convert remaining rows to an object
    $_object = $content[1..$content.Length] | 
        ConvertFrom-String -Delimiter "," -PropertyNames $propertyNames |
            Select-Object -Property $propertyNames

    # restore comma-separated strings
    foreach ($_row in $_object) {
        foreach ($propertyName in $propertyNames) {
            if ($_row.$propertyName -match "\$replacementDelimiter(?!(?:[^`"]*`"[^`"]*`")*[^`"]*$)") {
                $_row.$propertyName = $_row.$propertyName -replace "\$replacementDelimiter(?!(?:[^`"]*`"[^`"]*`")*[^`"]*$)", ","
                if ($_row.$propertyName -match "^`"(.*)`"$") {
                    $_row.$propertyName = $matches[1]
                }
            }
        }
    }

    return $_object

}

function global:Grant-AzProjectRole {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UPN","Id","UserId","Email","Mail")][string]$User,
        [switch]$ReferencedResourcesOnly,
        [switch]$RemoveUnauthorizedAssignments,
        [switch]$RemoveExpiredInvitations,
        [switch]$WhatIf
    )

    # function Get-AzProjectResourceFromScope {

    #     param(
    #         [Parameter(Mandatory=$true,Position=0)][string]$Scope
    #     )

    #     $resourceName = $Scope.Split("/")[-1]
    #     $provider = $Scope.Replace($global:AzureProject.ScopeBase,"")
    #     $provider = $provider.Substring(1,$provider.LastIndexOf("/")-1)
    
    #     $resourceType = switch ($provider) {
    #         "Microsoft.Storage/storageAccounts" {"StorageAccount"}
    #         {$_ -like "Microsoft.Storage/storageAccounts/*/blobServices/default/containers"} {"StorageContainer"}
    #         "Microsoft.Network/bastionHosts" {"Bastion"}
    #         "Microsoft.Network/networkInterfaces" { "NetworkInterface" }
    #         "Microsoft.Compute/virtualMachines" {"VM"}
    #         "Microsoft.MachineLearningServices/workspaces" {"MLWorkspace"}
    #         "Microsoft.DocumentDB/databaseAccounts" {"CosmosDBAccount "}
    #         "Microsoft.SqlVirtualMachine/SqlVirtualMachines" {"SqlVM"}
    #         "Microsoft.KeyVault/vaults" {"KeyVault"}
    #         "Microsoft.DataFactory/factories" {"DataFactory"}
    #         "Microsoft.Batch/BatchAccounts" {"BatchAccount"}
    #         "Microsoft.Insights/components/" {"ApplicationInsights"}
    #     }
    
    #     return [PSCustomObject]@{
    #         resourceType = $resourceType
    #         resourceName = $resourceName
    #         resourceId = $resourceType + "-" + $resourceName
    #     }
    
    # } 
    
    # function Get-AzProjectResourceScope {

    #     param(
    #         [Parameter(Mandatory=$true,Position=0)][string]$ResourceType,
    #         [Parameter(Mandatory=$true,Position=1)][string]$ResourceName
    #     )
    
    #     $scope = $global:AzureProject.ResourceType.$ResourceType.Scope
    #     $scope = ![string]::IsNullOrEmpty($ResourceName) ? ($scope -replace "$($global:AzureProject.ResourceType.$ResourceType.Name)`$", $ResourceName) : $scope
    
    #     return $scope
    
    # }

    Set-CursorInvisible

    $resourceTypeOrderedList = [ordered]@{
        ResourceGroup = 10
        Bastion = 20
        DataFactoryV2 = 30
        KeyVault = 40
        StorageAccount = 50
        StorageContainer = 55
        VM = 60
        NetworkInterface = 65
        CosmosDBAccount = 100
        MLWorkspace = 200
        default = 999
    }

    Write-Host+

    $message = "<  Options < >40> Description"
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    $message = "<  ------- < >40> -----------"
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray

    $message = "<  -User < >40> Processes only the specified user (object id, upn or email)."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    $message = "<  -ReferencedResourcesOnly < >40> Improves performance, but cannot remove obsolete/invalid role assignments."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    $message = "<  -RemoveUnauthorizedAssignments < >40> Removes role assignments not explicity specified in the import files."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    $message = "<  -RemoveExpiredInvitations < >40> Removes accounts with invitations pending more than 30 days."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    $message = "<  -WhatIf < >40> Simulates operations to allow for testing (Grant-AzProjectRole only)."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    Write-Host+

    if ($User -and $RemoveUnauthorizedAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$RemoveUnauthorizedAssignments switch cannot be used with the `$User parameter." -ForegroundColor Red
        Write-Host+
        return
    }
    if ($User -and $RemoveExpiredInvitations) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$RemoveExpiredInvitations switch cannot be used with the `$User parameter." -ForegroundColor Red
        Write-Host+
        return
    }

    if ($ReferencedResourcesOnly -and $RemoveUnauthorizedAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$ReferencedResourcesOnly and `$RemoveUnauthorizedAssignments switches cannot be used together." -ForegroundColor Red
        Write-Host+
        return
    }

    if ($RemoveUnauthorizedAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  The `"RemoveUnauthorizedAssignments`" switch has been specified." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Role assignments not specified in `"$ProjectName-securityAssignments-import.csv`" will be removed." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  EXCEPTIONS: OWNER role assignments and role assignments inherited from the subscription will NOT be removed." -ForegroundColor Gray
        Write-Host+
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine "  Continue (Y/N)? " -ForegroundColor Gray
        $response = Read-Host
        if ($response -eq $global:emptyString -or $response.ToUpper().Substring(0,1) -ne "Y") {
            Write-Host+
            return
        }
        Write-Host+
    }

    if ($ReferencedResourcesOnly) {
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  The `"ReferencedResourcesOnly`" switch has been specified." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Only resources referenced in the import files for each user's role assignments will be evaulated." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Note that a users' obsolete/invalid role assignments to other resources cannot be removed when the " -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  `"ReferencedResourcesOnly`" switch has been specified." -ForegroundColor Gray
        Write-Host+
    }

    if ($RemoveExpiredInvitations) {
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  The `"RemoveExpiredInvitations`" switch has been specified." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Accounts with invitations pending more than 30 days will be deleted." -ForegroundColor Gray
        Write-Host+
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine "  Continue (Y/N)? " -ForegroundColor Gray
        $response = Read-Host
        if ($response -eq $global:emptyString -or $response.ToUpper().Substring(0,1) -ne "Y") {
            Write-Host+
            return
        }
        Write-Host+
    }

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    $resourceGroupName = $global:AzureProject.ResourceType.ResourceGroup.Name

    #region DATAFILES

        $message = "<  Data validation <.>60> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        $UserImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-users-import.csv"
        $GroupImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-groups-import.csv"
        $ResourceImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
        $SecurityImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-security-import.csv"
        $SecurityExportFile = "$($global:AzureProject.Location.Data)\$ProjectName-security-export.csv"

        if (!(Test-Path $UserImportFile)) {
            Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $UserImportFile -Leaf) not found." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        if (!(Test-Path $GroupImportFile)) {
            $groupsInUse = Select-String -Path $SecurityImportFile -Pattern "Group" -Quiet
            # $groupsInUse = Select-String -Path $RoleAssignmentImportFile -Pattern "Group" -Quiet
            if ($groupsInUse) {
                Write-Host+ -NoTrace "    ($groupsInUse ? 'ERROR' : 'WARNING'): $(Split-Path -Path $GroupImportFile -Leaf) not found." -ForegroundColor ($groupsInUse ? "DarkRed" : "DarkYellow")
                Write-Host+
                return
            }
        }

        if (!(Test-Path $ResourceImportFile)) {
            Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $ResourceImportFile -Leaf) not found." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        if (!(Test-Path $SecurityImportFile)) {
            Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $SecurityImportFile -Leaf) not found." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        #region USER IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $UserImportFile" -ForegroundColor DarkGray
            $users = @()
            $users += Import-AzProjectFile $UserImportFile | Sort-Object -Property * -Unique
            # if ($User) { $users = $users | Where-Object {$_.signInName -eq $User} }

        #endregion USER IMPORT
        #region GROUP IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $GroupImportFile" -ForegroundColor DarkGray
            $groups = @()
            $groups += Import-AzProjectFile $GroupImportFile | Sort-Object -Property * -Unique
            # if ($User) { $groups = $groups | Where-Object {$_.user -eq $User} } 

        #endregion GROUP IMPORT
        #region RESOURCE IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $ResourceImportFile" -ForegroundColor DarkGray
            $resources = @()
            $resources += [PSCustomObject]@{
                resourceType = "ResourceGroup"
                resourceName = $resourceGroupName
                resourceId = "$resourceGroupName"
                resourceScope = $global:AzureProject.ResourceType.ResourceGroup.Scope
                resourcePath = $null
                resourceObject = $null
                resourceContext = $null
                resourceParent = $null
                resourceTypeSortOrder = $resourceTypeOrderedList.("ResourceGroup")
            }
            $resources += Import-AzProjectFile -Path $ResourceImportFile | 
                Select-Object -Property resourceType, resourceName, resourceId, 
                    @{Name="resourceScope"; Expression={$null}}, 
                    @{Name="resourcePath"; Expression={$null}}, 
                    @{Name="resourceObject"; Expression={$null}}, 
                    @{Name="resourceContext"; Expression={$null}}, 
                    resourceParent, @{Name="resourceTypeSortOrder"; Expression={$resourceTypeOrderedList.($_.resourceType) ?? $resourceTypeSortOrder.default}} | 
                Sort-Object -Property * -Unique |
                Sort-Object -Property resourceTypeSortOrder, resourceId

            $duplicateResourceIds = $resources | Group-Object -Property resourceId | Where-Object {$_.Count -gt 1}
            if ($duplicateResourceIds) {
                $errorMessage = "ERROR: Duplicate resource ids found in $(Split-Path -Path $ResourceImportFile -Leaf)."
                Write-Host+ -NoTrace "    $errorMessage" -ForegroundColor DarkRed
                foreach ($duplicateResourceId in $duplicateResourceIds) {
                    Write-Host+ -NoTrace "    $($global:asciiCodes.RightArrowWithHook)  Resource id '$($duplicateResourceId.Name)' occurs $($duplicateResourceId.Count) times" -ForegroundColor DarkGray
                }
                Write-Host+
                return
            }

        #endregion RESOURCE IMPORT
        #region SECURITY ASSIGNMENTS IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $SecurityImportFile" -ForegroundColor DarkGray
            $securityAssignmentsFromFile = Import-AzProjectFile -Path $SecurityImportFile | Sort-Object -Property * -Unique
            # if ($User) {
            #     $securityAssignmentsFromFile = $securityAssignmentsFromFile | Where-Object {($_.assigneeType -in ("User","SystemAssignedIdentity") -and $_.assignee -eq $User) -or ($_.assigneeType -eq "Group" -and $_.assignee -in ($groups | Where-Object {$_.user -eq $User}).group)}
            # }

        #endregion SECURITY ASSIGNMENTS IMPORT

        # if the $ReferencedResourcesOnly switch has been specified, then filter $resources to only those relevant to $users
        # NOTE: this is faster, but it prevents the function from finding/removing roleAssignments from other resources
        if ($ReferencedResourcesOnly) {
          $resources = $resources | Where-Object {$_.resourceId -in $securityAssignmentsFromFile.resourceId}
        }

        $missingUsers = @()
        $missingUsers += $groups | Where-Object {$_.user -notin $users.signInName} | Select-Object -Property @{Name="signInName"; Expression={$_.user}}, @{Name="source"; Expression={"Groups"}}
        $missingUsers += $securityAssignmentsFromFile | Where-Object {$_.assigneeType -eq "User" -and $_.assignee -notin $users.signInName} | Select-Object -Property @{Name="signInName"; Expression={$_.assignee}}, @{Name="source"; Expression={"Role Assignments"}}

        if ($missingUsers.Count -gt 0) {
            
            Write-Host+ 

            $message = "    SignInName : Status   : Source"
            Write-Host+ -NoTrace $message.Split(":")[0],(Format-Leader -Length 40 -Adjust (($message.Split(":")[0]).Length) -Character " "),$message.Split(":")[1],$message.Split(":")[2] -ForegroundColor DarkGray
            $message = "    ---------- : ------   : ------"
            Write-Host+ -NoTrace $message.Split(":")[0],(Format-Leader -Length 40 -Adjust (($message.Split(":")[0]).Length) -Character " "),$message.Split(":")[1],$message.Split(":")[2] -ForegroundColor DarkGray

            foreach ($missingUser in $missingUsers) {
                $message = "    $($missingUser.signInName) | MISSING  | $($missingUser.source)"
                Write-Host+ -NoTrace  $message.Split("|")[0],(Format-Leader -Length 40 -Adjust (($message.Split("|")[0]).Length) -Character " "),$message.Split("|")[1],$message.Split("|")[2] -ForegroundColor DarkGray,DarkGray,DarkRed,DarkGray
            }

            Write-Host+
            $message = "<  Data validation <.>60> FAILURE"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkRed

            return
            
        }

        Write-Host+
        $message = "<  Data validation <.>60> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    #endregion DATAFILES
    
    #region VERIFY RESOURCES

        Write-Host+
        $message = "<  Resource verification <.>60> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        foreach ($resource in $resources) {

            # if the resource already has a resourceObject, 
            # it's already been updated, so skip it (b/c we don't want to overwrite it)
            # example: NICs are updated with the VM but may be after the VM in the processing order
            if ($resource.resourceObject) { 
                continue
            }
            
            $resourceType = $resource.resourceType
            $resourceName = ![string]::IsNullOrEmpty($resource.resourceName) ? $resource.resourceName : $global:AzureProject.ResourceType.$resourceType.Name
            $resourcePath = $resourceGroupName -eq $resourceName ? $resourceGroupName : "$resourceGroupName/$resourceType/$resourceName"

            switch ($resourceType) {
                "StorageContainer" {
                    $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount" -and $_.resourceId -eq $resource.resourceParent}
                    $resourcePath = "$resourceGroupName/$($_storageAccount.resourceType)/$($_storageAccount.resourceName)/$($resource.resourceType)/$($resource.resourceName)"
                }
            }

            # set scope
            $scope = $null
            switch ($resourceType) {
                default {
                    if ([string]::IsNullOrEmpty($resource.resourceScope)) {
                        $scope = $global:AzureProject.ResourceType.$ResourceType.Scope
                        $scope = $scope.Substring(0,$scope.LastIndexOf("/")+1) + $ResourceName
                    }
                    else {
                        $scope = $resource.resourceScope
                    }
                }
                {$_ -like "DataFactory*"} {
                    if ([string]::IsNullOrEmpty($resource.resourceScope)) {
                        $scope = $global:AzureProject.ResourceType.DataFactory.Scope
                        $scope = $scope.Substring(0,$scope.LastIndexOf("/")+1) + $ResourceName
                    }
                    else {
                        $scope = $resource.resourceScope
                    }
                }
                "StorageContainer" {
                    $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount" -and $_.resourceId -eq $resource.resourceParent}
                    $scope = "$($global:AzureProject.ScopeBase)/Microsoft.Storage/storageAccounts/$($_storageAccount.resourceName)/blobServices/default/containers/$($resourceName)"
                }
            }

            # get object
            $object = $null
            $displayScope = $true
            switch ($resourceType) {
                default {
                    $getAzExpression = "Get-Az$resourceType -ResourceGroupName $resourceGroupName"
                    $getAzExpression += $resourceType -ne "ResourceGroup" ? " -Name $resourceName" : $null
                    $object = Invoke-Expression $getAzExpression
                    if (!$object) {
                        throw "$resourcePath does not exist."
                    }
                    # $scope = $object.Id ?? $object.ResourceId
                }
                "StorageContainer" {
                    $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount" -and $_.resourceId -eq $resource.resourceParent}
                    $object = Get-AzStorageContainer -Context $_storageAccount.resourceContext -Name $resourceName
                    if (!$object) {
                        throw "$resourcePath does not exist."
                    }
                }
            }

            $resource.resourceName = [string]::IsNullOrEmpty($resource.resourceName) ? $scope.Substring($scope.LastIndexOf("/")+1, $scope.Length-($scope.LastIndexOf("/")+1)) : $resource.resourceName
            $resource.resourceScope = $scope
            $resource.resourceObject = $object
            $resource.resourcePath = $resourcePath

            # special cases
            switch ($resourceType) {
                "VM" {
                    $vm = $object
                    foreach ($nic in $vm.networkProfile.NetworkInterfaces) {

                        $nicType = "NetworkInterface"
                        $nicScope = $nic.Id
                        $nicId = $nic.Id.split("/")[-1]
                        $nicName = $nicId

                        Write-Host+ -NoTrace -NoSeparator "    $($nic.Id.split("/resourceGroups/")[1])" -ForegroundColor DarkGray

                        $nicResource = $resources | Where-Object {$_.resourceType -eq $nicType -and $_.resourceId -eq $nicId}
                        $nicObject = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $nicId
                        if ($nicResource) {

                            $nicResource.resourceId = $nicName
                            $nicResource.resourceType = $nicType
                            $nicResource.resourceName = $nicName
                            $nicResource.resourceScope = $nicScope
                            $nicResource.resourceParent = $resource.resourceId
                            $nicResource.resourcePath = "$resourceGroupName/$($resource.resourceType)/$($resource.resourceName)/$nicType/$nicName"
                            $nicResource.resourceObject = $nicObject

                        }
                        else {

                            $nicResource = [PSCustomObject]@{
                                resourceId = $nicName
                                resourceType = $nicType
                                resourceName = $nicName
                                resourceScope = $nicScope
                                resourceParent = $resource.resourceId
                                resourcePath = "$resourceGroupName/$($resource.resourceType)/$($resource.resourceName)/$nicType/$nicName"
                                resourceObject = $nicObject
                            }
                            $resources += $nicResource

                        }

                        $nicRole = "Reader"
                        foreach ($resourceSecurityAssignment in ($securityAssignmentsFromFile | 
                            Where-Object {$_.resourceId -eq $nicResource.resourceParent -and $_.securityType -eq "RoleAssignment"} | 
                                Sort-Object -Property assigneeType,assignee -Unique)) {
                                    $securityAssignmentsFromFile += [PSCustomObject]@{
                                        resourceType = $nicResource.resourceType
                                        resourceId = $nicResource.resourceId
                                        securityType = "RoleAssignment"
                                        securityKey = $nicRole
                                        securityValue = "Grant"
                                        assigneeType = $resourceSecurityAssignment.assigneeType
                                        assignee = $resourceSecurityAssignment.assignee
                                    }
                        }

                    }
                }
                "StorageAccount" {
                    $resource.resourceContext = New-AzStorageContext -StorageAccountName $resourceName -UseConnectedAccount -ErrorAction SilentlyContinue
                }
            }

            if ($displayScope) {
                $message = "    $($scope.split("/resourceGroups/")[1].replace("providers/Microsoft.",$null))"
                Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            }

        }

        $duplicateResourceScopes = $resources | Group-Object -Property resourceScope | Where-Object {$_.Count -gt 1}
        if ($duplicateResourceScopes) {
            Write-Host+
            $errorMessage = "ERROR: Duplicate resource scope"
            Write-Host+ -NoTrace "    $errorMessage" -ForegroundColor DarkRed
            foreach ($duplicateResourceScope in $duplicateResourceScopes.Group) {
                Write-Host+ -NoTrace "    $($global:asciiCodes.RightArrowWithHook)  $($duplicateResourceScope.resourceScope)" -ForegroundColor DarkGray
            }
            Write-Host+
            return
        }

        $duplicateResourceNames = $resources | Group-Object -Property resourceType, resourceName | Where-Object {$_.Count -gt 1}
        if ($duplicateResourceNames) {
            Write-Host+
            Write-Host+ -NoTrace "    WARNING: Multiple objects with different scopes but with the same resource type and name" -ForegroundColor DarkYellow
            foreach ($duplicateResourceName in $duplicateResourceNames.Group) {
                Write-Host+ -NoTrace "    $($duplicateResourceName.resourceScope)" -ForegroundColor DarkGray
            }
        }

        Write-Host+
        $message = "<  Resource verification <.>60> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    #endregion VERIFY RESOURCES
    #region PROJECT IDENTITIES

        $projectIdentities = @()
        foreach ($signInName in ($users.signInName | Sort-Object -Unique)) {
            $azureADUser = Get-AzureADUser -Tenant $tenantKey -User $signInName
            if ($azureADUser) {
                $projectIdentities += [PSCustomObject]@{
                    objectType = "User"
                    objectId = $azureADUser.id
                    # signInName = $azureADUser.mail
                    id = $azureADUser.mail
                    displayName = $azureADUser.mail
                    authorized = $azureADUser.accountEnabled
                    accountEnabled = $unauthorizedAzureADUser.accountEnabled
                    reason = $azureADUser.accountEnabled ? $null : "ACCOUNT DISABLED"
                    object = $azureADUser
                    external = $false
                    administrator = $false
                    owner = $false
                    doNotModify = $false
                }
            }
        }

        # add service principals (system assigned identities) to $projectIdentities
        ($securityAssignmentsFromFile | Where-Object {$_.assigneeType -eq "SystemAssignedIdentity"}).assignee | Sort-Object -Unique | Foreach-Object {
            $_assignee = $_
            $systemAssignedIdentity = Get-AzSystemAssignedIdentity -Scope ($resources | Where-Object {$_.resourceId -eq $_assignee}).resourceScope
            $projectIdentities += [PSCustomObject]@{
                objectType = "SystemAssignedIdentity"
                objectId = $systemAssignedIdentity.PrincipalId
                id = $systemAssignedIdentity.Name
                displayName = $systemAssignedIdentity.Name
                authorized = $true
                reason = $null
                object = $systemAssignedIdentity
            }
        }
   
        #region UNAUTHORIZED PROJECT IDENTITIES

            # identify unauthorized project users and role assignments
            # if $User has been specified, skip this step

            $unauthorizedProjectRoleAssignments = @()

            $unauthorizedProjectRoleAssignments = Get-AzRoleAssignment -ResourceGroupName $resourceGroupName | 
                Where-Object {$_.Scope -in $resources.resourceScope -and $_.ObjectId -notin ($projectIdentities | Where-Object {$_.authorized}).objectId}

            foreach ($unauthorizedProjectRoleAssignment in $unauthorizedProjectRoleAssignments) {
                $projectIdentity = $projectIdentities | Where-Object { $_.objectId -eq $unauthorizedProjectRoleAssignment.objectId } 
                if (!$projectIdentity) {
                    try {
                        $unauthorizedAzureADUser = Get-AzureADUser -Tenant $tenantKey -User $unauthorizedProjectRoleAssignment.SignInName
                        $projectIdentities += [PSCustomObject]@{
                            objectType = "User"
                            objectId = $unauthorizedAzureADUser.id
                            # signInName = $unauthorizedAzureADUser.mail
                            id = $unauthorizedAzureADUser.mail
                            displayName = $unauthorizedAzureADUser.mail
                            authorized = $false
                            accountEnabled = $unauthorizedAzureADUser.accountEnabled
                            reason = $unauthorizedAzureADUser.accountEnabled ? "UNAUTHORIZED" : "ACCOUNT DISABLED"
                            object = $unauthorizedAzureADUser
                            external = $true
                            administrator = $false
                            owner = $false
                            doNotModify = $false
                        }   
                    }
                    catch {
                        $projectIdentities += [PSCustomObject]@{
                            objectType = "Unknown"
                            objectId = $unauthorizedProjectRoleAssignment.objectId
                            id = $unauthorizedProjectRoleAssignment.objectId
                            displayName = $unauthorizedProjectRoleAssignment.objectId
                            authorized = $false
                            removeAllRoleAssignments = $true
                            reason = "NOTFOUND"
                            external = $true
                            administrator = $false
                            owner = $false
                            doNotModify = $false
                        } 
                    }
                }
            }

            $resourcesWithUnauthorizedAccessPolicies = @()

            $resourcesWithUnauthorizedAccessPolicies += $resources.resourceObject | 
                Where-Object {$_.PSObject.Properties.Name -eq "AccessPolicies"} | 
                    Where-Object {$_.accessPolicies.objectId -notin ($projectIdentities | Where-Object {$_.authorized}).objectId}

            foreach ($resourceWithUnauthorizedAccessPolicy in $resourcesWithUnauthorizedAccessPolicies) {
                foreach ($accessPolicy in $resourceWithUnauthorizedAccessPolicy.accessPolicies) {
                    $projectIdentity = $projectIdentities | Where-Object {$_.objectId -eq $accessPolicy.objectId} 
                    if (!$projectIdentity) {
                        try {
                            $unauthorizedAzureADUser = Get-AzureADUser -Tenant $tenantKey -User $accessPolicy.ObjectId
                            $projectIdentities += [PSCustomObject]@{
                                objectType = "User"
                                objectId = $unauthorizedAzureADUser.id
                                # signInName = $unauthorizedAzureADUser.mail
                                id = $unauthorizedAzureADUser.mail
                                displayName = $unauthorizedAzureADUser.mail
                                authorized = $false
                                accountEnabled = $unauthorizedAzureADUser.accountEnabled
                                reason = $unauthorizedAzureADUser.accountEnabled ? "UNAUTHORIZED" : "ACCOUNT DISABLED"
                                object = $unauthorizedAzureADUser
                                external = $true
                                administrator = $false
                                owner = $false
                                doNotModify = $false
                            }   
                        }
                        catch {
                            $projectIdentities += [PSCustomObject]@{
                                objectType = "Unknown"
                                objectId = $resourceWithUnauthorizedAccessPolicy.objectId
                                id = $resourceWithUnauthorizedAccessPolicy.objectId
                                displayName = $resourceWithUnauthorizedAccessPolicy.objectId
                                authorized = $false
                                removeAllAccessPolicies = $true
                                reason = "NOTFOUND"
                                external = $true
                                administrator = $false
                                owner = $false
                                doNotModify = $false
                            } 
                        }
                    }
                }
            }

            # this is only here for now b/c i'm building out its use in the next section
            # eventually, it should be moved into the $global:Azure config
            $privilegedAdministratorRoles = @()
            $privilegedAdministratorRoles += @("Owner","Contributor","User Access Administrator","Role Based Access Control Administrator")
            $privilegedAdministratorRoles += 
                switch ($resource.objectType) {
                    "ResourceGroup" {}
                }

            # these are project identities found with security assignments that aren't in the project security assignments file
            # if any of those security assignments are privileged administrative roles, then mark them as authorized
            # otherwise, unauthorized users and identities will be removed later in this function
            foreach ($projectIdentity in $projectIdentities | Where-Object {$_.external -and !$_.authorized -and $_.accountEnabled}) {
                $resourceGroupSecurityAssignments = Get-AzRoleAssignment -ResourceGroupName $resourceGroupName -ObjectId $projectIdentity.objectId
                foreach ($resourceGroupSecurityAssignment in $resourceGroupSecurityAssignments) {
                    if ($resourceGroupSecurityAssignment.RoleDefinitionName -in $privilegedAdministratorRoles) {
                        $projectIdentity.authorized = $true
                        $projectIdentity.administrator = $true
                        $projectIdentity.doNotModify = $true
                        if ($resourceGroupSecurityAssignment.RoleDefinitionName -eq "Owner") {
                            $projectIdentity.owner = $true
                        }
                    }
                }
                $_reason = @(); $_reason += "EXTERNAL"
                $_reason += $projectIdentity.owner ? "OWNER" : ($projectIdentity.administrator ? "ADMINISTRATOR" : $null)
                $projectIdentity.reason = $_reason | Join-String -Separator "/"
            }
        
        #endregion UNAUTHORIZED PROJECT IDENTITIES

        if ($User) {

            $isObjectId = $User -match $global:RegexPattern.Guid
            # Write-Host+ -Iff $($isObjectId) "$User is an object id"
            # $isSignName = $User -match $global:RegexPattern.Mail -or $User -match $global:RegexPattern.UserName.AzureAD
            # Write-Host+ -Iff $($isSignName) "$User is a signInName (email or upn)"

            if ($isObjectId) {
                $projectIdentities = $projectIdentities | Where-Object {$_.objectId -eq $User}
            }
            else {
                $projectIdentities = $projectIdentities | Where-Object {$_.id -eq $User}
            }

            if ($projectIdentities.Count -ne 1) {
                Write-Host+ -Iff $($projectIdentities.Count -eq 0) -NoTrace -NoSeparator  "      ERROR: User `"$User`" not found." -ForegroundColor DarkRed
                Write-Host+ -Iff $($projectIdentities.Count -gt 1) -NoTrace -NoSeparator  "      ERROR: User `"$User`" found $($projectIdentities.Count) times." -ForegroundColor DarkRed
                Write-Host+
                return
            }

            $users = $users | Where-Object {$_.signInName -eq $User}
            $groups = $groups | Where-Object {$_.user -eq $User} 
            $securityAssignmentsFromFile = $securityAssignmentsFromFile | 
                Where-Object {($_.assigneeType -in ("User","SystemAssignedIdentity") -and $_.assignee -eq $User) -or ($_.assigneeType -eq "Group" -and $_.assignee -in ($groups | Where-Object {$_.user -eq $User}).group)}

        }

    #endregion PROJECT IDENTITIES    
    #region VERIFY USERS  

        if (<# !$User -and  #>($projectIdentities[0].objectType -eq "User")) {

            Write-Host+
            $message = "<  User verification <.>60> PENDING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray   
            Write-Host+   

            $members = @()
            $members += $projectIdentities | Where-Object {$_.objectType -eq "User" -and $_.object.userType -eq "Member"} 
            if ($members) {

                $message = "<    Member < >40> Status"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray
                $message = "<    ------ < >40> ------"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray

                foreach ($member in $members) {
                    $message = $member.authorized ? "<    $($member.id) < >40> Verified" : "<    $($member.id) < >40> *** $($member.reason) ***"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor ($member.authorized ? "DarkGray" : "DarkRed")
                }
                
                Write-Host+

            }

            $guests = @()
            $guests += $projectIdentities | Where-Object {$_.objectType -eq "User" -and $_.object.userType -ne "Member"} 
            if ($guests) {

                $message = "<    Guest < >40> Status   Date"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray
                $message = "<    ----- < >40> ------   ----"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray

                foreach ($guest in $guests) {

                    $message = "<    $($guest.id) < >40> "
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray
                
                    if (!$guest) {
                        $fullName = ($users | Where-Object {$_.signInName -eq $guest})[0].fullName

                        if (!$WhatIf) {
                            $invitation = Send-AzureADInvitation -Tenant $tenantKey -Email $guest -DisplayName $fullName -Message $global:AzureProject.Invitation.Message
                            $invitation | Out-Null
                        }

                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine "Invitation sent" -ForegroundColor DarkGreen
                        Write-Host+ -Iff $($WhatIf) -NoTrace -NoTimestamp " (","WhatIf",")" -ForegroundColor Gray, DarkYellow, Gray
                    }
                    else {
                        $externalUserState = $guest.object.externalUserState -eq "PendingAcceptance" ? "Pending " : $guest.object.externalUserState
                        $externalUserStateChangeDateTime = $guest.object.externalUserStateChangeDateTime

                        if ($guest.object.externalUserState -eq "PendingAcceptance") {
                            if (([datetime]::Now - $externalUserStateChangeDateTime).TotalDays -gt 30) {
                                if ($RemoveExpiredInvitations) {
                                    if (!$WhatIf) {
                                        Disable-AzureADUser -Tenant $tenantKey -User $guest
                                    }
                                    $guest.authorized = $false
                                    $guest.reason = "ACCOUNT DISABLED"
                                }
                                else {
                                    $guest.reason = "INVITATION EXPIRED"
                                }
                            }
                        }

                        $externalUserStateChangeDateString = $externalUserStateChangeDateTime.ToString("u").Substring(0,10)
                        $externalUserStateColor = $externalUserState -eq "Pending " ? "DarkYellow" : "DarkGray"
                        $message = "$externalUserState $externalUserStateChangeDateString"
                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor $externalUserStateColor

                        Write-Host+ -Iff $(!$guest.authorized) -NoTrace -NoTimeStamp -NoNewLine " *** $($guest.Reason) ***" -ForegroundColor DarkRed
                        Write-Host+ -Iff $($guest.external -and $guest.administrator) -NoTrace -NoTimeStamp -NoNewLine " *** $($guest.Reason) ***" -ForegroundColor DarkRed

                        Write-Host+
                    }

                }
            }

            Write-Host+
            $message = "    * Use -RemoveExpiredInvitiations to remove accounts with expired invitations"
            Write-Host+ -NoTrace $message -ForegroundColor DarkGray
            
            Write-Host+
            $message = "<  User verification <.>60> SUCCESS"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

        }

    #endregion VERIFY USERS
    #region SECURITY ASSIGNMENTS

        #region GET ROLE ASSIGNMENTS

            $roleAssignments = [PsCustomObject]@()

            #region RESOURCE GROUP ROLE ASSIGNMENTS

                $resourceGroup = $resources | Where-Object {$_.resourceType -eq "ResourceGroup"}
                $resourceGroupDefaultRole = "Reader"
                $resourceGroupRoleAssignments = @()
                foreach ($groupMember in $groups) {
                    $projectIdentity = $projectIdentities | Where-Object {$_.id -eq $groupMember.user -and $_.authorized}
                    $resourceGroupRoleAssignments += [PsCustomObject]@{
                        resourceId = $resourceGroup.resourceId
                        resourceType = $resourceGroup.resourceType
                        resourceName = $resourceGroup.resourceName
                        resourceScope = $resourceGroup.resourceScope
                        role = $resourceGroupDefaultRole
                        groupMember = $true
                        groupId = $groupMember.group
                        objectType = "User"
                        objectId = $projectIdentity.objectId
                        # signInName = $projectIdentity.id
                        resourcePath = $resource.resourcePath
                        authorized = $true
                        options = @()
                    }
                }
                foreach ($projectIdentity in $projectIdentities | Where-Object {$_.objectType -eq "User" -and $_.objectId -notin $resourceGroupRoleAssignments.objectId -and $_.authorized}) {
                    $resourceGroupRoleAssignments += [PsCustomObject]@{
                        resourceId = $resourceGroup.resourceId
                        resourceType = $resourceGroup.resourceType
                        resourceName = $resourceGroup.resourceName
                        resourceScope = $resourceGroup.resourceScope
                        role = $resourceGroupDefaultRole
                        objectType = "User"
                        objectId = $projectIdentity.objectId
                        # signInName = $projectIdentity.id
                        resourcePath = $resource.resourcePath
                        authorized = $true
                        options = @()
                    }
                }
                $roleAssignments += $resourceGroupRoleAssignments

            #endregion RESOURCE GROUP ROLE ASSIGNMENTS

            foreach ($securityAssignment in $securityAssignmentsFromFile | Where-Object {$_.securityType -eq "RoleAssignment"}) {

                if ($securityAssignment.assigneeType -eq "SystemAssignedIdentity") {
                    $systemAssignedIdentity = Get-AzSystemAssignedIdentity -Scope ($resources | Where-Object {$_.resourceId -eq $securityAssignment.assignee}).resourceScope
                    foreach ($resource in ($resources | Where-Object {$_.resourceId -eq $securityAssignment.resourceId})) {
                        $roleAssignments += [PsCustomObject]@{
                            resourceId = $resource.resourceId
                            resourceType = $resource.resourceType
                            resourceName = $resource.resourceName
                            resourceScope = $resource.resourceScope
                            role = $securityAssignment.securityKey
                            objectId = $systemAssignedIdentity.PrincipalId
                            objectType = $securityAssignment.assigneeType
                            resourcePath = $resource.resourcePath
                            authorized = $true
                            options = $securityAssignment.options -split "\s*,\s*"
                        }
                    }
                }

                if ($securityAssignment.assigneeType -eq "Group") {
                    $groupMembers = $groups | Where-Object {$_.group -eq $securityAssignment.assignee}
                    foreach ($groupMember in $groupMembers) {
                        $projectIdentity = $projectIdentities | Where-Object {$_.id -eq $groupMember.user -and $_.authorized}
                        foreach ($resource in ($resources | Where-Object {$_.resourceId -eq $securityAssignment.resourceId})) {
                            $roleAssignments += [PsCustomObject]@{
                                resourceId = $resource.resourceId
                                resourceType = $resource.resourceType
                                resourceName = $resource.resourceName
                                resourceScope = $resource.resourceScope
                                role = $securityAssignment.securityKey
                                groupMember = $true
                                groupId = $groupMember.group
                                objectType = "User"
                                objectId = $projectIdentity.objectId
                                # signInName = $projectIdentity.id
                                resourcePath = $resource.resourcePath
                                authorized = $true
                                options = $securityAssignment.options -split "\s*,\s*"
                            }
                        }
                    }
                }
                elseif ($securityAssignment.assigneeType -eq "User") {
                    $projectIdentity = $projectIdentities | Where-Object {$_.id -eq $securityAssignment.assignee -and $_.authorized}
                    foreach ($resource in ($resources | Where-Object {$_.resourceId -eq $securityAssignment.resourceId})) {
                        $roleAssignments += [PsCustomObject]@{
                            resourceId = $resource.resourceId
                            resourceType = $resource.resourceType
                            resourceName = $resource.resourceName
                            resourceScope = $resource.resourceScope
                            role = $securityAssignment.securityKey
                            objectType = "User"
                            objectId = $projectIdentity.objectId
                            # signInName = $projectIdentity.id
                            resourcePath = $resource.resourcePath
                            authorized = $true
                            options = $securityAssignment.options -split "\s*,\s*"
                        }
                    }
                }

            }

            foreach ($unauthorizedProjectRoleAssignment in $unauthorizedProjectRoleAssignments) {
                $projectIdentity = $projectIdentities | Where-Object {$_.id -eq $unauthorizedProjectRoleAssignment.assignee -and !$_.authorized}
                foreach ($resource in ($resources | Where-Object {$_.resourceId -eq $unauthorizedProjectRoleAssignment.resourceId})) {
                    $roleAssignments += [PsCustomObject]@{
                        resourceId = $resource.resourceId
                        resourceType = $resource.resourceType
                        resourceName = $resource.resourceName
                        resourceScope = $resource.resourceScope
                        role = $securityAssignment.securityKey
                        objectType = "User"
                        objectId = $projectIdentity.objectId
                        # signInName = $projectIdentity.id
                        resourcePath = $resource.resourcePath
                        authorized = $false
                        options = $securityAssignment.options -split "\s*,\s*"
                    }
                }
            }

            $roleAssignments = $roleAssignments | Sort-Object -Property resourcePath

            $uniqueResourcesFromSecurityAssignments = @()
            $uniqueResourcesFromSecurityAssignments += $roleAssignments | Select-Object -Property resourceId, resourceType, objectId<# , signInName #> | Sort-Object -Property * -Unique

            # export $roleAssignments
            if (!$User) {
                $roleAssignments | 
                    Where-Object {$_.resourceType -in $resourceTypeMap.Values} |
                    Select-Object -Property resourceType,resourceId,resourceName,
                        @{Name="securityType";Expression={"RoleAssignment"}},
                        @{Name="securityKey";Expression={$_.role}},
                        @{Name="securityValue";Expression={"Grant"}},
                        @{Name="assigneeType";Expression={$_.groupMember ? "Group" : $_.objectType}},
                        @{Name="assignee";Expression={$_objectId = $_.objectId; $_.groupMember ? $_.groupId : ($projectIdentities | Where-Object {$_objectId -eq $_.objectId}).displayName}},
                        @{Name="options";Expression={$_.options | Join-String -Separator ","}} | 
                    Sort-Object -Property assigneeType, assignee, resourceType, resourceId -Unique |
                        Export-Csv -Path $SecurityExportFile -UseQuotes Always -NoTypeInformation 
            }

        #endregion GET ROLE ASSIGNMENTS
        #region GET ACCESS POLICIES

            $accessPolicyAssignments = [PsCustomObject]@()

            foreach ($resource in ($resources | Where-Object {$_.resourceObject.PSObject.Properties.Name -eq "AccessPolicies"})) {  

                $accessPolicies = $securityAssignmentsFromFile | Where-Object {$_.securityType -eq "AccessPolicy" -and $_.resourceType -eq $resource.resourceType -and $_.resourceId -eq $resource.resourceId}
                foreach ($accessPolicy in $accessPolicies) {  
                    if ($accessPolicy.assigneeType -eq "SystemAssignedIdentity") {
                        $systemAssignedIdentity = Get-AzSystemAssignedIdentity -Scope ($resources | Where-Object {$_.resourceId -eq $accessPolicy.assignee}).resourceScope
                        $accessPolicyAssignments += [PsCustomObject]@{
                            resourceId = $resource.resourceId
                            resourceType = $resource.resourceType
                            resourceName = $resource.resourceName
                            resourceScope = $resource.resourceScope
                            accessPolicy = @{
                                $accessPolicy.securityKey = $accessPolicy.securityValue -split ","
                            }
                            objectType = "SystemAssignedIdentity"
                            objectId = $systemAssignedIdentity.PrincipalId
                            resourcePath = $resource.resourcePath
                            authorized = $true
                            options = $securityAssignment.options -split "\s*,\s*"
                        }
                    }                     
                    elseif ($accessPolicy.assigneeType -eq "Group") {
                        $groupMembers = $groups | Where-Object {$_.group -eq $accessPolicy.assignee}
                        foreach ($groupMember in $groupMembers) {
                            $projectIdentity = $projectIdentities | Where-Object {$_.id -eq $groupMember.user -and $_.authorized}
                            $accessPolicyAssignments += [PsCustomObject]@{
                                resourceId = $resource.resourceId
                                resourceType = $resource.resourceType
                                resourceName = $resource.resourceName
                                resourceScope = $resource.resourceScope
                                accessPolicy = @{
                                    $accessPolicy.securityKey = $accessPolicy.securityValue -split ","
                                }
                                groupMember = $true
                                groupId = $groupMember.group
                                objectType = "User"
                                objectId = $projectIdentity.objectId
                                # signInName = $projectIdentity.id
                                resourcePath = $resource.resourcePath
                                authorized = $true
                                options = $securityAssignment.options -split "\s*,\s*"
                            }
                        }
                    }
                    elseif ($accessPolicy.assigneeType -eq "User") {
                        $projectIdentity = $projectIdentities | Where-Object {$_.id -eq $accessPolicy.assignee -and $_.authorized}
                        $accessPolicyAssignments += [PsCustomObject]@{
                            resourceId = $resource.resourceId
                            resourceType = $resource.resourceType
                            resourceName = $resource.resourceName
                            resourceScope = $resource.resourceScope
                            accessPolicy = @{
                                $accessPolicy.securityKey = $accessPolicy.securityValue -split ","
                            }
                            objectType = "User"
                            objectId = $projectIdentity.objectId
                            # signInName = $projectIdentity.id
                            resourcePath = $resource.resourcePath
                            authorized = $true
                            options = $securityAssignment.options -split "\s*,\s*"
                        }
                    }
                }
               
            }

            foreach ($resourceWithUnauthorizedAccessPolicy in $resourcesWithUnauthorizedAccessPolicies) {
                $unauthorizedAccessPolicies = $resourceWithUnauthorizedAccessPolicy.accessPolicies
                $projectIdentity = $projectIdentities | Where-Object {$_.objectId -eq $unauthorizedAccessPolicies.objectId -and !$_.authorized}
                $resource = $resources | Where-Object {$_.resourceScope -eq $resourceWithUnauthorizedAccessPolicy.ResourceId}
                $accessPolicyPermissionPropertyNames = @("PermissionsToKeys","PermissionsToSecrets","PermissionsToCertificates","PermissionsToStorage")
                foreach ($accessPolicyPermissionPropertyName in $accessPolicyPermissionPropertyNames | Where-Object {$unauthorizedAccessPolicies.$_}) {
                    $accessPolicyAssignments += [PsCustomObject]@{
                        resourceId = $resource.resourceId
                        resourceType = $resource.resourceType
                        resourceName = $resource.resourceName
                        resourceScope = $resource.resourceScope
                        accessPolicy = @{
                            "$accessPolicyPermissionPropertyName" = $unauthorizedAccessPolicies.$accessPolicyPermissionPropertyName | Join-String -Separator ","
                        }
                        objectType = "User"
                        objectId = $projectIdentity.objectId
                        # signInName = $projectIdentity.id
                        resourcePath = $resource.resourcePath
                        authorized = $false
                        options = $securityAssignment.options -split "\s*,\s*"
                    }
                }
            }

            $accessPolicyAssignments = $accessPolicyAssignments | Sort-Object -Property resourcePath
            $uniqueResourcesFromSecurityAssignments += $accessPolicyAssignments | Select-Object -Property resourceId, resourceType, objectId<# , signInName #> | Sort-Object -Property * -Unique

            # export $accessPolicies
            if (!$User) {
                $accessPolicyAssignments | 
                    Where-Object {$_.resourceType -in $resourceTypeMap.Values} |
                    Select-Object -Property resourceType,resourceId,resourceName,
                        @{Name="securityType";Expression={"AccessPolicy"}},
                        @{Name="securityKey";Expression={$_.accessPolicy.Keys[0]}},
                        @{Name="securityValue";Expression={$_.accessPolicy.Values[0] | Join-String -Separator ", " }},  
                        @{Name="assigneeType";Expression={$_.groupMember ? "Group" : $_.objectType}},
                        @{Name="assignee";Expression={$_objectId = $_.objectId; $_.groupMember ? $_.groupId : ($projectIdentities | Where-Object {$_objectId -eq $_.objectId}).displayName}},
                        @{Name="options";Expression={$_.options | Join-String -Separator ","}} | 
                    Sort-Object -Property * -Unique | Sort-Object -Property assigneeType, assignee, resourceType, resourceId |
                Export-Csv -Path $SecurityExportFile -UseQuotes Always -NoTypeInformation -Append
            }   

        #endregion GET ACCESS POLICIES


            Write-Host+
            $message = "<  Security assignments <.>60> PENDING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray 
            # Write-Host+

            Write-Host+
            $message = "<    Example < >40> Status"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray, DarkGray, DarkGray
            $message = "<    ------- < >40> ------"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray, DarkGray, DarkGray
            $message = "<    Reader <.>40> Current"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray, DarkGray, DarkGray
            $message = "<    ^Reader <.>40> Inherited"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray, DarkGray, DarkGray
            $message = "<    +Reader <.>40> Added"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGreen, DarkGray, DarkGray
            $message = "<    -Reader <.>40> Removed"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkRed, DarkGray, DarkGray
            Write-Host+

            foreach ($projectIdentity in $projectIdentities) {
                
                Write-Host+ -NoTrace -NoNewLine "    $($projectIdentity.displayName)" -ForegroundColor Gray

                if ($projectIdentity.objectType -eq "User") {
                    $externalUserState = $assignee.externalUserState -eq "PendingAcceptance" ? "Pending" : $assignee.externalUserState
                    $externalUserStateColor = $assignee.externalUserState -eq "Pending" ? "DarkYellow" : "DarkGray"
                    if ($externalUserState -eq "Pending") {
                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator " (",$externalUserState,")" -ForegroundColor DarkGray,DarkYellow,DarkGray
                    }
                }

                Write-Host+ -Iff $($WhatIf) -NoTrace -NoTimestamp -NoNewLine -NoSeparator " (","WhatIf",")" -ForegroundColor DarkGray,DarkYellow,DarkGray
                Write-Host+ -Iff $(!$projectIdentity.authorized) -NoTrace -NoTimestamp -NoNewLine -NoSeparator " *** $($projectIdentity.reason) *** " -ForegroundColor DarkRed
                Write-Host+ -Iff $($projectIdentity.external -and $projectIdentity.administrator) -NoTrace -NoTimestamp -NoNewLine -NoSeparator " *** $($projectIdentity.reason) *** " -ForegroundColor DarkRed

                Write-Host+
                Write-Host+ -NoTrace "    $($emptyString.PadLeft($projectIdentity.displayName.Length,"-"))" -ForegroundColor Gray
                
                $resourceTypes = @()
                $resourceTypes += ($roleAssignments | Where-Object {$_.objectId -eq $projectIdentity.objectId} | Sort-Object -Property resourcePath -Unique).resourceType 
                if (!$ReferencedResourcesOnly) {
                    $resourceTypes += $global:AzureProject.ResourceType.Keys | Where-Object {$_ -notin $resourceTypes -and $global:AzureProject.ResourceType.$_.Object}
                    # $resourceTypes += $global:AzureProject.ResourceType.Keys | Where-Object {$_ -notin $resourceTypes -and $_ -ne "ResourceGroup" -and $global:AzureProject.ResourceType.$_.Object}
                }

                # sort by resourceScope to ensure children are after parents
                $resourcesToCheck = $resources | Sort-Object -Property resourcePath

                # # restrict resource check to only those specified in the security assignment import file for the current projectIdentity
                # # this won't exclude child resources such as NICs (parent = VM) and StorageContainers (parent = StorageAccount)
                # $resourcesToCheck = $resourcesToCheck | Where-Object {$_.resourceScope -eq "ResourceGroup" -or $_.resourceId -in ($uniqueResourcesFromSecurityAssignments | Where-Object {$_.objectId -eq $projectIdentity.objectId}).resourceId}

                # if the $UserResourcesOnly switch has been specified, then filter $resources to only those relevant to the current assignee
                # NOTE: this is faster, but it prevents the function from finding/removing roleAssignments from other resources
                if ($ReferencedResourcesOnly) {
                    $resourcesToCheck = $resources | Where-Object {$_.resourceId -in (($roleAssignments | Where-Object {$_.objectId -eq $projectIdentity.objectId}).resourceId)}
                }

                $roleAssignmentCount = 0
                foreach ($resource in $resourcesToCheck) { 

                    $unauthorizedRoleAssignment = $false

                    $resourceType = $resource.resourceType
                    $resourceId = $resource.resourceId
                    $resourceName = $resource.resourceName
                    $resourceScope = $resource.resourceScope

                    $resourceParent = $resources | Where-Object {$_.resourceId -eq $resource.resourceParent}
                    $message = "    " + (![string]::IsNullOrEmpty($resourceParent) ? "$($global:asciiCodes.RightArrowWithHook)  " : "") + "$($resourceType)/$($resourceName)"
                    $message = ($message.Length -gt 55 ? $message.Substring(0,55) + "`u{22EF}" : $message) + " : "    

                    #region SET ROLE ASSIGNMENTS

                        $currentRoleAssignments = @()
                        $inheritedRoleAssignments = @()

                        $_allRoleAssignments = Get-AzRoleAssignment -Scope $resourceScope -ObjectId $projectIdentity.objectId | 
                            Where-Object {($resourceScope -eq $_.Scope -or $resourceScope.StartsWith($_.Scope)) -and $_.Scope.Length -le $resourceScope.Length}
                        
                            # get role assignments set at this scope
                        $currentRoleAssignments += $_allRoleAssignments | Where-Object {$_.Scope -eq $resourceScope}
                        
                        # get inherited role assignments which are not already set at this scope
                        # only show inherited role assignments if they are referenced in the security assignment import file
                        $_inheritedRoleAssignments = $_allRoleAssignments | 
                            Where-Object {$_.Scope -ne $resourceScope -and $_.RoleDefinitionName -notin $currentRoleAssignments.RoleDefinitionName} | 
                            Where-Object {$_.Scope -eq ($roleAssignments | Where-Object {$_.objectId -eq $projectIdentity.objectId -and $_.resourceType -eq $resourceType -and $_.resourceId -eq $resourceId}).resourceScope}

                        foreach ($_inheritedRoleAssignment in $_inheritedRoleAssignments) {
                            $_delegationRoleAssignment = $roleAssignments | 
                                Where-Object {$_inheritedRoleAssignment.objectId -eq $_.objectId -and $_inheritedRoleAssignment.Scope -eq $_.resourceScope -and $_inheritedRoleAssignment.RoleDefinitionName -eq $_.role}
                            # ignore inherited role assignments which were flagged (in $roleAssignments) with "hideDelegation"
                            if ($_delegationRoleAssignment.options -notcontains "hideDelegation") {
                                $inheritedRoleAssignments += $_inheritedRoleAssignment
                            }
                            
                        }

                        # merge the filtered assignments together
                        $currentRoleAssignments += $inheritedRoleAssignments 
                        $currentRoleAssignments = $currentRoleAssignments | Sort-Object -Property Scope

                        # if ($currentRoleAssignments.Count -gt 1) {
                        #     $currentRoleAssignments = $currentRoleAssignments | Where-Object {$resourceType -eq "ResourceGroup" -or $_.Scope -ne $resourceGroup.resourceScope}
                        # }

                        $rolesWrittenCount = 0
                        if ($currentRoleAssignments) {
                            Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Format-Leader -Length 60 -Adjust (($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray 
                            foreach ($currentRoleAssignment in $currentRoleAssignments) {
                                $message = $currentRoleAssignment.RoleDefinitionName
                                if ($currentRoleAssignment.RoleDefinitionName -in $inheritedRoleAssignments.RoleDefinitionName) {
                                    $message = "^" + $message
                                }
                                if ($currentRoleAssignments.Count -gt 1 -and $foreach.Current -ne $currentRoleAssignments[-1]) {
                                    $message += ", "
                                }
                                Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGray
                            }
                        }
                        $rolesWrittenCount = $currentRoleAssignments.Count

                        Write-Host+ -Iff $($projectIdentity.doNotModify -and $rolesWrittenCount -gt 0) 

                        # don't update users with the doNotModify flag 
                        # these users should be owner/admins at the subscription scope
                        if (!$projectIdentity.doNotModify) {

                            $requiredRoleAssignments = $roleAssignments | Where-Object {$_.objectId -eq $projectIdentity.objectId -and $_.resourceType -eq $resourceType -and $_.resourceId -eq $resourceId -and $_.resourceName -eq $resourceName}
                            if (![string]::IsNullOrEmpty($resourceName)) {
                                $requiredRoleAssignments =  $requiredRoleAssignments | Where-Object {$_.resourceName -eq $resourceName}
                            }
                            if ($requiredRoleAssignments) {
                                if (!$currentRoleAssignments) {
                                    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Format-Leader -Length 60 -Adjust (($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray 
                                }
                                foreach ($roleAssignment in $requiredRoleAssignments) {
                                    $currentRoleAssignment = @()
                                    $inheritedRoleAssignment = @()
                                    switch ($resourceType) {
                                        default {
                                            $currentRoleAssignment += Get-AzRoleAssignment -Scope $resourceScope -ObjectId $projectIdentity.objectId | Where-Object {$_.Scope -eq $resourceScope -and $_.RoleDefinitionName -eq $roleAssignment.role}
                                            $inheritedRoleAssignment += Get-AzRoleAssignment -Scope $resourceScope -ObjectId $projectIdentity.objectId | Where-Object {$_.Scope.Length -le $resourceScope.Length} 
                                        }
                                        "ResourceGroup" {
                                            $currentRoleAssignment += Get-AzRoleAssignment -Scope $resourceScope -ObjectId $projectIdentity.objectId | Where-Object {$_.Scope -eq $resourceScope -and $_.RoleDefinitionName -eq $roleAssignment.role}
                                        }
                                    }
                                    if (!$currentRoleAssignment) {

                                        if (!$WhatIf) {
                                            New-AzRoleAssignment -Scope $resourceScope -RoleDefinitionName $roleAssignment.role -ObjectId $projectIdentity.objectId -ErrorAction SilentlyContinue | Out-Null
                                        }

                                        $message = "$($rolesWrittenCount -gt 0 ? ", " : $null)"
                                        Write-Host+ -Iff $(![string]::IsNullOrEmpty($message)) -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGray
                                        $message = "+$($roleAssignment.role)"
                                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGreen 
                                        $rolesWrittenCount++   
                                    }
                                    if ($unauthorizedProjectRoleAssignments | Where-Object {$_.SignInName -eq $currentRoleAssignment.SignInName -and $_.RoleDefinitionId -eq $currentRoleAssignment.RoleDefinitionId}) {
                                        $unauthorizedRoleAssignment = $true
                                    }
                                }
                            }

                            $currentRoleAssignmentsThisResourceScope = $currentRoleAssignments | Where-Object {$_.Scope -eq $resourceScope}
                            if ($currentRoleAssignmentsThisResourceScope) {
                                foreach ($currentRoleAssignment in $currentRoleAssignmentsThisResourceScope) {
                                    if ($currentRoleAssignment.RoleDefinitionName -notin $requiredRoleAssignments.role -or ($RemoveUnauthorizedRoleAssignments -and $unauthorizedRoleAssignment)) {

                                        if (!$WhatIf) {
                                            $resourceLocksCanNotDelete = Get-AzResourceLock -Scope $resourceScope | Where-Object {$_.Properties.level -eq "CanNotDelete"}
                                            $resourceLocksCanNotDelete | Foreach-Object {Remove-AzResourceLock -Scope $resourceScope -LockName $_.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null}
                                            Remove-AzRoleAssignment -Scope $resourceScope -RoleDefinitionName $currentRoleAssignment.RoleDefinitionName -ObjectId $projectIdentity.objectId -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                                            $resourceLocksCanNotDelete | Foreach-Object {Set-AzResourceLock -Scope $resourceScope -LockName $_.Name -LockLevel $_.Properties.level -LockNotes $_.Properties.notes -Force} | Out-Null
                                        }

                                        $message = "$($rolesWrittenCount -gt 0 ? ", " : $null)"
                                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGray
                                        $message = "-$($currentRoleAssignment.RoleDefinitionName)"
                                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkRed  
                                        $rolesWrittenCount++
                                    }
                                }
                            }

                            if ($unauthorizedRoleAssignment) {
                                Write-Host+ -NoTrace -NoTimeStamp -NoNewLine " *** UNAUTHORIZED ***" -ForegroundColor DarkRed 
                            }

                            if ($currentRoleAssignments -or $requiredRoleAssignments) {
                                Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8," "))"
                            }

                        }

                        $roleAssignmentCount += $rolesWrittenCount                  

                    #endregion SET ROLE ASSIGNMENTS
                    #region SET ACCESS POLICIES

                        $accessPolicyWrittenCount = 0

                        switch ($resourceType) {
                            "KeyVault" {

                                $currentAccessPolicy = $resource.resourceObject.accessPolicies | 
                                Where-Object {$_.objectId -eq $projectIdentity.objectId}

                                $requiredAccessPolicy = ($accessPolicyAssignments | 
                                    Where-Object {$_.resourceType -eq $resourceType -and $_.resourceId -eq $resourceId} |
                                        Where-Object {$_.objectId -eq $projectIdentity.objectId -and $projectIdentity.authorized}).accessPolicy

                                $accessPolicyPermissionPropertyNames = @("PermissionsToKeys","PermissionsToSecrets","PermissionsToCertificates","PermissionsToStorage")
                                foreach ($accessPolicyPermissionPropertyName in $accessPolicyPermissionPropertyNames) {

                                    $accessPolicyPermissionWritten = $false

                                    $currentAccessPolicyKey = $null
                                    $currentAccessPolicyValue = $null
                                    if ($currentAccessPolicy -and $currentAccessPolicy.$accessPolicyPermissionPropertyName) {
                                        
                                        $currentAccessPolicyKey = $accessPolicyPermissionPropertyName
                                        $currentAccessPolicyValue = $currentAccessPolicy.$accessPolicyPermissionPropertyName
                                        $currentAccessPolicyValueStr = ($currentAccessPolicyValue | Foreach-Object {(Get-Culture).TextInfo.ToTitleCase($_)}) | Join-String -Separator ", "
                                        $message = "<    $($global:asciiCodes.RightArrowWithHook)  AccessPolicy/$($currentAccessPolicyKey) <.>61> $($currentAccessPolicyValueStr)" 
                                        Write-Host+ -NoTrace -NoNewline $message -Parse -ForegroundColor DarkGray,DarkGray,$($projectIdentity.authorized ? "DarkGray" : "DarkRed")
                                        $accessPolicyPermissionWritten = $true

                                        if (!$projectIdentity.authorized) {
                                            Write-Host+
                                        }

                                        $accessPolicyWrittenCount++

                                    }

                                    Write-Host+ -Iff $($projectIdentity.doNotModify -and $accessPolicyPermissionWritten) 

                                    # don't update users with the doNotModify flag 
                                    # these users should be owner/admins at the subscription scope
                                    if (!$projectIdentity.doNotModify) {
            
                                        if (!($requiredAccessPolicy -and $requiredAccessPolicy.$accessPolicyPermissionPropertyName) -and 
                                            ($currentAccessPolicy -and $currentAccessPolicy.$accessPolicyPermissionPropertyName) -and
                                            $projectIdentity.authorized) {

                                            $accessPolicyParams = @{
                                                ResourceGroupName = $resourceGroupName
                                                VaultName = $resource.resourceName
                                                ObjectId = $projectIdentity.objectId
                                            }
                                            $accessPolicyParams += @{ "$currentAccessPolicyKey" = @() }

                                            foreach ($_currentAccessPolicyValue in $currentAccessPolicyValue) {
                                                Write-Host+ -Iff $($accessPolicyPermissionWritten) -NoTrace -NoTimestamp -NoNewLine ", " -ForegroundColor DarkGray
                                                Write-Host+ -NoTrace -NoTimestamp -NoNewLine "-$((Get-Culture).TextInfo.ToTitleCase($_currentAccessPolicyValue))" -ForegroundColor DarkRed
                                                $accessPolicyPermissionWritten = $true
                                            }

                                            if (!$WhatIf) {
                                                $result = Set-AzKeyVaultAccessPolicy @accessPolicyParams -PassThru
                                                $result | Out-Null
                                            }

                                            Write-Host+ -Iff $($accessPolicyPermissionWritten)

                                        }

                                        if ($requiredAccessPolicy -and $requiredAccessPolicy.$accessPolicyPermissionPropertyName -and
                                            $projectIdentity.authorized) {

                                            $accessPolicyParams = @{
                                                ResourceGroupName = $resourceGroupName
                                                VaultName = $resource.resourceName
                                                ObjectId = $projectIdentity.objectId
                                            }
                                            $requiredAccessPolicyKey = $accessPolicyPermissionPropertyName
                                            $requiredAccessPolicyValue = $requiredAccessPolicy.$requiredAccessPolicyKey
                                            # $requiredAccessPolicyValueStr = ($requiredAccessPolicyValue | Foreach-Object {(Get-Culture).TextInfo.ToTitleCase($_)}) | Join-String -Separator ", "
                                            $accessPolicyParams += @{ "$requiredAccessPolicyKey" = $requiredAccessPolicyValue }

                                            if (!$accessPolicyPermissionWritten) {
                                                $message = "<    $($global:asciiCodes.RightArrowWithHook)  AccessPolicy/$($requiredAccessPolicyKey) <.>61> " 
                                                Write-Host+ -NoTrace -NoNewline $message -Parse -ForegroundColor DarkGray
                                            }

                                            if (![string]::IsNullOrEmpty($currentAccessPolicyKey) -and $currentAccessPolicyKey -eq $requiredAccessPolicyKey) {
                                                foreach ($_currentAccessPolicyValue in $currentAccessPolicyValue) {
                                                    if ($_currentAccessPolicyValue -notin $requiredAccessPolicyValue) {
                                                        Write-Host+ -Iff $($accessPolicyPermissionWritten) -NoTrace -NoTimestamp -NoNewLine ", " -ForegroundColor DarkGray
                                                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "-$((Get-Culture).TextInfo.ToTitleCase($_currentAccessPolicyValue))" -ForegroundColor DarkRed
                                                        $accessPolicyPermissionWritten = $true
                                                    }
                                                }
                                            }

                                            if (!$WhatIf) {
                                                $result = Set-AzKeyVaultAccessPolicy @accessPolicyParams -PassThru
                                                $result | Out-Null
                                            }

                                            $_requiredAccessPolicyValueToAdd = @()
                                            foreach ($_requiredAccessPolicyValue in $requiredAccessPolicyValue) {
                                                if ($_requiredAccessPolicyValue -notin $currentAccessPolicyValue) {
                                                    $_requiredAccessPolicyValueToAdd += "+$_requiredAccessPolicyValue"
                                                }
                                            }
                                            if ($_requiredAccessPolicyValueToAdd) {
                                                Write-Host+ -Iff $($accessPolicyPermissionWritten) -NoTrace -NoTimestamp -NoNewLine ", " -ForegroundColor DarkGray
                                                $_requiredAccessPolicyValueToAddStr = ($_requiredAccessPolicyValueToAdd | Foreach-Object {(Get-Culture).TextInfo.ToTitleCase($_)}) | Join-String -Separator ", "
                                                Write-Host+ -NoTrace -NoTimestamp -NoNewLine $_requiredAccessPolicyValueToAddStr -ForegroundColor DarkGreen
                                                $accessPolicyPermissionWritten = $true
                                            }

                                            Write-Host+ -Iff $($accessPolicyPermissionWritten)

                                            $accessPolicyWrittenCount++

                                        }

                                    }
                                }


                                # # remove all access policies and break
                                # if (!$projectIdentity.authorized -and $projectIdentity.removeAllAccessPolicies) {
                                #     $accessPolicyParams = @{
                                #         ResourceGroupName = $resourceGroupName
                                #         VaultName = $resource.resourceName
                                #         ObjectId = $projectIdentity.objectId
                                #     }
                                    
                                #     if (!$WhatIf) {
                                #         $result = Remove-AzKeyVaultAccessPolicy @accessPolicyParams -PassThru
                                #         $result | Out-Null
                                #         break
                                #     }
                                # }

                                
                            }
                        }

                    #endregion SET ACCESS POLICIES
                
                }

                if ($roleAssignmentCount -eq 0 -and !$accessPolicyWrittenCount -eq 0) {
                    Write-Host+ -NoTrace "    none" -ForegroundColor DarkGray
                } 

                Write-Host+ 

            }

            $message = "<  Security assignment <.>60> SUCCESS"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

        #endregion SECURITY ASSIGNMENTS

    Write-Host+

    Set-CursorVisible

    return

}
Set-Alias -Name azProjGrant -Value Grant-AzProjectRole -Scope Global

function global:Get-AzAvailableVmSizes {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("Location")][string]$ResourceLocation,
        [Parameter(Mandatory=$false)][string]$VmSize,
        [switch]$HasSufficientQuota
    )

    # Get the list of VM SKUs for the given location
    $vmSKU = Get-AzComputeResourceSku -Location $ResourceLocation | Where-Object ResourceType -eq "virtualMachines" | Select-Object Name, Family
    $vmUsage = Get-AzVMUsage -Location $ResourceLocation

    $vmSizes = Get-AzVmSize -Location $ResourceLocation | Where-Object {$_.Name -notlike "%Promo%"}
    if (![string]::IsNullOrEmpty($VmSize)) {
        $vmSizes = $vmSizes | Where-Object {$_.Name -eq $VmSize}
    }

    $availableVmSizes = @()
    $vmSizes | Foreach-Object {
        $_vmSizeName = $_.Name
        $_vmNumberOfCores = $_.NumberOfCores
        $_vmFamilyKey = ($vmSKU | Where-Object {$_.Name -eq $_vmSizeName}).Family
        $_vmUsage = $vmUsage | Where-Object {$_.Name.Value -eq $_vmFamilyKey} 
        $_vmFamilyName = $_vmUsage.Name.LocalizedValue 
        $_availableVmSize = [PSCustomObject]@{
            Name = $_vmSizeName
            Family = $_vmFamilyName
            NumberOfCores = $_vmNumberOfCores
            Usage = $_vmUsage.CurrentValue
            Quota = $_vmUsage.Limit
            HasSufficientQuota = $null
        }
        $_availableVmSize.HasSufficientQuota = $_availableVmSize.Quota - $_availableVmSize.Usage - $_availableVmSize.NumberOfCores -ge 0
        $availableVmSizes += $_availableVmSize

    }

    return $HasSufficientQuota ? ($availableVmSizes | Where-Object {$_.HasSufficientQuota}) : $availableVmSizes

}

function Get-AzProjectStorageAccountParameters {

    # get/read/update StorageAccountPerformanceTier
    $storageAccountPerformanceTierDefault = Read-AzProjectVariable -Name StorageAccountPerformanceTier
    if ([string]::IsNullOrEmpty($StorageAccountPerformanceTier) -and ![string]::IsNullOrEmpty($storageAccountPerformanceTierDefault)) {
        $StorageAccountPerformanceTier = $storageAccountPerformanceTierDefault
    }
    if ([string]::IsNullOrEmpty($StorageAccountPerformanceTier)) {
        $storageAccountPerformanceTiers = @("Standard","Premium")
        $storageAccountPerformanceTierDefault = "Standard"
        $storageAccountPerformanceTier = Request-AzProjectVariable -Name "StorageAccountPerformanceTier" -Selections $storageAccountPerformanceTiers -Default $storageAccountPerformanceTierDefault
    }
    Write-AzProjectVariable -Name StorageAccountPerformanceTier -Value $storageAccountPerformanceTier

    # get/read/update StorageAccountRedundancyConfiguration
    $storageAccountRedundancyConfigurationDefault = Read-AzProjectVariable -Name StorageAccountRedundancyConfiguration
    if ([string]::IsNullOrEmpty($StorageAccountRedundancyConfiguration) -and ![string]::IsNullOrEmpty($storageAccountRedundancyConfigurationDefault)) {
        $StorageAccountRedundancyConfiguration = $storageAccountRedundancyConfigurationDefault
    }
    if ([string]::IsNullOrEmpty($StorageAccountRedundancyConfiguration)) {
        $storageAccountRedundancyConfigurations = @("LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS")
        $storageAccountRedundancyConfigurationDefault = "LRS"
        $storageAccountRedundancyConfiguration = Request-AzProjectVariable -Name "StorageAccountRedundancyConfiguration" -Selections $storageAccountRedundancyConfigurations -Default $storageAccountRedundancyConfigurationDefault
    }
    Write-AzProjectVariable -Name StorageAccountRedundancyConfiguration -Value $storageAccountRedundancyConfiguration

    $storageAccountSku = "$($StorageAccountPerformanceTier)_$($storageAccountRedundancyConfiguration)"

    # get/read/update StorageAccountKind
    $storageAccountKindDefault = Read-AzProjectVariable -Name StorageAccountKind
    if ([string]::IsNullOrEmpty($StorageAccountKind) -and ![string]::IsNullOrEmpty($storageAccountKindDefault)) {
        $StorageAccountKind = $storageAccountKindDefault
    }
    if ([string]::IsNullOrEmpty($StorageAccountKind)) {
        $storageAccountKinds = @("StorageV2","BlockBlobStorage","FileStorage","Storage","BlobStorage")
        $storageAccountKindDefault = "StorageV2"
        $storageAccountKind = Request-AzProjectVariable -Name "StorageAccountKind" -Selections $storageAccountKinds -Default $storageAccountKindDefault
    }
    Write-AzProjectVariable -Name StorageAccountKind -Value $storageAccountKind

    return [PSCustomObject]@{
        StorageAccountPerformanceTier = $storageAccountPerformanceTier
        StorageAccountRedundancyConfiguration = $storageAccountRedundancyConfiguration
        StorageAccountSku = $storageAccountSku
        StorageAccountKind = $storageAccountKind
    }

}

function Get-AzProjectStorageContainerParameters {

    # get/read/update StorageContainerName
    $storageContainerNameDefault = Read-AzProjectVariable -Name StorageContainerName
    if ([string]::IsNullOrEmpty($StorageContainerName) -and ![string]::IsNullOrEmpty($storageContainerNameDefault)) {
        $StorageContainerName = $storageContainerNameDefault
    }
    if ([string]::IsNullOrEmpty($StorageContainerName)) {
        $StorageContainerNameDefault = "data"
        $StorageContainerName = Request-AzProjectVariable -Name "StorageContainerName" -Default $storageContainerNameDefault
    }
    Write-AzProjectVariable -Name StorageContainerName -Value $StorageContainerName

    return [PSCustomObject]@{
        StorageContainerName = $StorageContainerName
    }

}

function Remove-AzProjectVmParameters {

    Write-AzProjectVariable -Name VmSize -Value "None"
    Write-AzProjectVariable -Name VmImagePublisher -Delete
    Write-AzProjectVariable -Name VmImageOffer -Delete
    Write-AzProjectVariable -Name ResourceAdminUsername -Delete
    Write-AzProjectVariable -Name CurrentAzureUserId -Delete
    Write-AzProjectVariable -Name CurrentAzureUserEmail -Delete

}

function Get-AzProjectVmParameters {

    $ResourceLocation = $global:AzureProject.ResourceLocation
    $Prefix = $global:AzureProject.Prefix

    # get/read/update vmSize
    $vmSizeDefault = Read-AzProjectVariable -Name vmSize
    $vmSizeDefault = $vmSizeDefault -ne "None" ? $vmSizeDefault : $null
    if ([string]::IsNullOrEmpty($vmSize) -and ![string]::IsNullOrEmpty($vmSizeDefault)) {
        $vmSize = $vmSizeDefault
    }
    if ([string]::IsNullOrEmpty($vmSize)) {
        $availableVmSizes = Get-AzAvailableVmSizes -ResourceLocation $ResourceLocation # -HasSufficientQuota
        $vmSizeDefault = $vmSizeDefault ?? "Standard_D4s_v3"
        $vmSizeSelections = @()
        $vmSizeSelections += $availableVmSizes.Name | Sort-Object
        $vmSize = Request-AzProjectVariable -Name "VmSize" -Selections $vmSizeSelections -Default $vmSizeDefault -AllowNone:$($AllowNone:IsPresent)
    }
    Write-AzProjectVariable -Name VmSize -Value $vmSize

    # need to look at project providers and see if compute is included
    if ($vmSize -ne "None") {

        # get/read/update VmImagePublisher
        $vmImagePublisherDefault = Read-AzProjectVariable -Name VmImagePublisher
        if ([string]::IsNullOrEmpty($vmImagePublisher) -and ![string]::IsNullOrEmpty($vmImagePublisherDefault)) {
            $vmImagePublisher = $vmImagePublisherDefault
        }
        if ([string]::IsNullOrEmpty($vmImagePublisher)) {
            $vmImagePublishers = @("microsoft-dsvm")
            $vmImagePublisher = Request-AzProjectVariable -Name "VmImagePublisher" -Suggestions $vmImagePublishers -Selections $vmImagePublishers
        }
        Write-AzProjectVariable -Name VmImagePublisher -Value $vmImagePublisher

        # get/read/update VmImageOffer
        $vmImageOfferDefault = Read-AzProjectVariable -Name VmImageOffer
        if ([string]::IsNullOrEmpty($vmImageOffer) -and ![string]::IsNullOrEmpty($vmImageOfferDefault)) {
            $vmImageOffer = $vmImageOfferDefault
        }
        if ([string]::IsNullOrEmpty($vmImageOffer)) {
            $vmImageOffers = @("linux","windows")
            $vmImageOffer = Request-AzProjectVariable -Name "VmImageOffer" -Suggestions $vmImageOffers -Selections $vmImageOffers
        }
        Write-AzProjectVariable -Name VmImageOffer -Value $vmImageOffer

        $resourceAdminUsername = "$($Prefix)$($ProjectName)adm"
        Write-AzProjectVariable -Name ResourceAdminUsername -Value $resourceAdminUsername

        $authorizedIp = $(curl -s https://api.ipify.org)
        Write-AzProjectVariable -Name AuthorizedIp -Value $authorizedIp

        $currentAzureUser = Get-AzureAdUser -Tenant $tenantKey -User (Get-AzContext).Account.Id
        $currentAzureUserId = $currentAzureUser.id
        $currentAzureUserEmail = $currentAzureUser.mail
        Write-AzProjectVariable -Name CurrentAzureUserId -Value $currentAzureUserId
        Write-AzProjectVariable -Name CurrentAzureUserEmail -Value $currentAzureUserEmail

    }
    else {

        Remove-AzProjectVmParameters

    }

    return [PSCustomObject]@{
        VmSize = $vmSize
        VmImagePublisher = $vmImagePublisher
        VmImageOffer = $vmImageOffer
        ResourceAdminUserName = $resourceAdminUsername
        AuthorizedIp = $authorizedIp
        CurrentAzureUserId = $currentAzureUserId
        CurrentAzureUserEmail = $currentAzureUserEmail
    }

}

function global:Deploy-AzProject {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    switch ($global:AzureProject.DeploymentType) {
        "Overwatch" {  
            Deploy-AzProjectWithOverwatch -Tenant $tenantKey -Project $ProjectName
        }
        "DSVM" {
            Deploy-AzProjectWithDSVM -Tenant $tenantKey -Project $ProjectName
        }
    }
    
    Set-AzProjectDefaultResourceScopes
    Get-AzProjectDeployedResources

    return

}
Set-Alias -Name azProjDeploy -Value Deploy-AzProject -Scope Global

function global:Deploy-AzProjectWithOverwatch {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}
    
    $resourceGroupName = $global:AzureProject.ResourceType.ResourceGroup.Name
    $resourceLocation = $global:AzureProject.ResourceLocation
    
    Write-Host+
    $message = "<  Project '$ProjectName' Deployment <.>60> PENDING" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    #region RESOURCE GROUP

        $message = "<    ResourceGroups/$($resourceGroupName) <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
        
        $resourceExists = $false
        $resourceSuccess = $false
        $resourceGroup = Get-AzResourceGroup -Name $global:AzureProject.ResourceType.ResourceGroup.Name -ErrorAction SilentlyContinue
        if ($resourceGroup) {
            $resourceExists = $true
            $resourceSuccess = $true
        }
        else {
            $resourceGroup = New-AzResourceGroup+ -Tenant $tenantKey -ResourceGroupName $resourceGroupName -Location $resourceLocation
            if ($resourceGroup) {
                $global:AzureProject.ResourceType.ResourceGroup.Object = $resourceGroup
                $resourceSuccess = $true
            }
        }

        $messageErase = "$($emptyString.PadLeft(8,"`b")) "
        $messageExists = $resourceExists ? "EXISTS" : $null
        $messageExistsDelimiter = $resourceExists ? "/" : $null
        $messageStatus = "$($resourceSuccess ? "SUCCESS" : "FAIL")$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $messageErase, $messageExists, $messageExistsDelimiter, $messageStatus -ForegroundColor DarkGray, DarkYellow, DarkGray, ($resourceSuccess ? "DarkGreen" : "DarkRed")

    #endregion RESOURCE GROUP
    #region RESOURCE IMPORT

        # Write-Host+ -NoTrace -NoSeparator "    $ResourceImportFile" -ForegroundColor DarkGray
        # $resources = @(); $resources += [PSCustomObject]@{resourceType = "ResourceGroup"; resourceName = $resourceGroupName; resourceId = "ResourceGroup-$resourceGroupName"; resourceScope = $global:AzureProject.ResourceType.ResourceGroup.Scope; resourceObject = $null; resourcePath = $null}
        $resources += Import-AzProjectFile -Path $ResourceImportFile | 
            Select-Object -Property resourceType, resourceName, resourceId, @{Name="resourceScope"; Expression={$null}}, @{Name="resourcePath"; Expression={$null}}, @{Name="resourceObject"; Expression={$null}}, @{Name="resourceContext"; Expression={$null}}, resourceParent
                # Sort-Object -Property resourceType, resourceName, resourceId   

        $duplicateResourceIds = $resources | Group-Object -Property resourceId | Where-Object {$_.Count -gt 1}
        if ($duplicateResourceIds) {
            $errorMessage = "ERROR: Duplicate resource ids found in $(Split-Path -Path $ResourceImportFile -Leaf)."
            Write-Host+ -NoTrace "    $errorMessage" -ForegroundColor DarkRed
            foreach ($duplicateResourceId in $duplicateResourceIds) {
                Write-Host+ -NoTrace "    $($global:asciiCodes.RightArrowWithHook)  Resource id '$($duplicateResourceId.Name)' occurs $($duplicateResourceId.Count) times" -ForegroundColor DarkGray
            }
            Write-Host+
            return
        }

    #endregion RESOURCE IMPORT   
    #region CREATE RESOURCES

        $deploymentSuccess = $true
        foreach ($resource in $resources) {

            $resourceExists = $false
            $resourceSuccess = $false

            $resourceType = $resource.resourceType
            $resourceName = ![string]::IsNullOrEmpty($resource.resourceName) ? $resource.resourceName : $global:AzureProject.ResourceType.$resourceType.Name
            $resourcePath = $resourceGroupName -eq $resourceName ? $resourceGroupName : "$resourceGroupName/$resourceType/$resourceName"  
            $resourceParent = $resources | Where-Object {$_.resourceId -eq $resource.resourceParent}

            $resourceTypeAndName = "$($resourceType)/$($resourceName)"
            $resourceTypeAndName = ($resourceTypeAndName.Length -gt 44 ? $resourceTypeAndName.Substring(0,44) + " `u{22EF} " : $resourceTypeAndName)
            $message = "<    $(![string]::IsNullOrEmpty($resourceParent) ? "$($global:asciiCodes.RightArrowWithHook)  " : $null)$($resourceTypeAndName) <.>60> PENDING"
            Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray

            # set scope
            $scope = $null
            switch ($resourceType) {
                default {
                    if ([string]::IsNullOrEmpty($resource.resourceScope)) {
                        $scope = $global:AzureProject.ResourceType.$ResourceType.Scope
                        $scope = $scope.Substring(0,$scope.LastIndexOf("/")+1) + $ResourceName
                    }
                    else {
                        $scope = $resource.resourceScope
                    }
                }
                {$_ -like "DataFactory*"} {
                    if ([string]::IsNullOrEmpty($resource.resourceScope)) {
                        $scope = $global:AzureProject.ResourceType.DataFactory.Scope
                        $scope = $scope.Substring(0,$scope.LastIndexOf("/")+1) + $ResourceName
                    }
                    else {
                        $scope = $resource.resourceScope
                    }
                }
                "StorageContainer" {
                    $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount" -and $_.resourceId -eq $resource.resourceParent}
                    $scope = "$($global:AzureProject.ScopeBase)/Microsoft.Storage/storageAccounts/$($_storageAccount.resourceName)/blobServices/default/containers/$($resourceName)"
                }
            }

            # get object, if it exists
            $object = $null
            switch ($resourceType) {
                default {
                    $getAzExpression = "Get-Az$resourceType -ResourceGroupName $resourceGroupName"
                    $getAzExpression += $resourceType -ne "ResourceGroup" ? " -Name $resourceName" : $null
                    $getAzExpression += " -ErrorAction SilentlyContinue 2>&1"
                    $object = Invoke-Expression $getAzExpression
                }
                "StorageContainer" {
                    $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount" -and $_.resourceId -eq $resource.resourceParent}
                    $object = Get-AzStorageContainer -Context $_storageAccount.resourceContext -Name $resourceName -ErrorAction SilentlyContinue
                }
            }

            if ($object) { 
                $resourceExists = $true
                $resourceSuccess = $true
            }

            # create object
            try {
                switch ($resourceType) {
                    default {
                        if (!$object) {
                            $getAzExpression = "New-Az$resourceType -ResourceGroupName $resourceGroupName -Name $resourceName -Location $resourceLocation"
                            $object = Invoke-Expression $getAzExpression
                        }
                    }
                    "StorageAccount" {
                        if (!$object) {
                            $_storageAccountParams = @{
                                Name = $resourceName
                                ResourceGroupName = $resourceGroupName
                                Location = $resourceLocation
                                SKU = $global:AzureProject.ResourceType.$resourceType.Parameters.StorageAccountSku
                                Kind = $global:AzureProject.ResourceType.$resourceType.Parameters.StorageAccountKind
                            }
                            $object = New-AzStorageAccount+ @_storageAccountParams
                        }
                        $resource.resourceContext = New-AzStorageContext -StorageAccountName $resourceName -UseConnectedAccount -ErrorAction SilentlyContinue
                    }
                    "StorageContainer" {    
                        if (!$object) {
                            $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount" -and $_.resourceId -eq $resource.resourceParent}
                            $object = New-AzStorageContainer+ -Context $_storageAccount.resourceContext -Name $resourceName
                        }
                    }
                    "MLWorkspace" {
                        if (!$object) {
                            $_storageAccount = $resources | Where-Object {$_.resourceType -eq "StorageAccount"}
                            $_keyVault = $resources | Where-Object {$_.resourceType -eq "keyVault"}
                            $_applicationInsights = $resources | Where-Object {$_.resourceType -eq "ApplicationInsights"}
                            $_mlWorkspaceParams = @{
                                Name = $resourceName
                                ResourceGroupName = $resourceGroupName
                                Location = $resourceLocation
                                ApplicationInsightID = $_applicationInsights.resourceScope
                                KeyVaultId = $_keyVault.resourceScope
                                StorageAccountId = $_storageAccount.resourceScope
                                IdentityType = 'SystemAssigned'
                            }
                            $object = New-AzMLWorkspace @_mlWorkspaceParams
                        }
                    }
                }
            }
            catch {
                Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkRed
            }

            $resource.resourceName = [string]::IsNullOrEmpty($resource.resourceName) ? $scope.Substring($scope.LastIndexOf("/")+1, $scope.Length-($scope.LastIndexOf("/")+1)) : $resource.resourceName
            $resource.resourceScope = $scope
            $resource.resourceObject = $object
            $resource.resourcePath = $resourcePath

            if ($object) { 
                $resourceSuccess = $true
            }
            else {
                $deploymentSuccess = $false
            }

            $messageErase = "$($emptyString.PadLeft(8,"`b")) "
            $messageExists = $resourceExists ? "EXISTS" : $null
            $messageExistsDelimiter = $resourceExists ? "/" : $null
            $messageStatus = "$($resourceSuccess ? "SUCCESS" : "FAIL")$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $messageErase, $messageExists, $messageExistsDelimiter, $messageStatus -ForegroundColor DarkGray, DarkYellow, DarkGray, ($resourceSuccess ? "DarkGreen" : "DarkRed")

        }

    #endregion CREATE RESOURCES
    
    Write-Host+
    $message = "<  Project '$ProjectName' Deployment <.>60> $($deploymentSuccess ? "SUCCESS" : "FAIL")" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($deploymentSuccess ? "DarkGreen" : "DarkRed")

    if ($deploymentSuccess) {
        # scan resource group and create resource import file
        Export-AzProjectResourceFile -Project $ProjectName
    }
    
}

function global:Deploy-AzProjectWithDSVM {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    if ($azProjectVmParameters.VmSize -eq "None") {
        Write-Host+ -NoTrace "VmSize cannot be null for a DSVM deployment." -ForegroundColor DarkRed
        return
    }

    $azProjectStorageAccountParameters = $global:AzureProject.ResourceType.StorageAccount.Parameters
    # $azProjectStorageContainerParameters = $global:AzureProject.ResourceType.StorageContainer.Parameters
    $azProjectVmParameters = $global:AzureProject.ResourceType.VM.Parameters

    $env:SUBSCRIPTION_ID = $global:Azure.$tenantKey.Subscription.Id
    $env:TENANT_ID = $global:Azure.$tenantKey.Tenant.Id
    $env:RESOURCE_LOCATION = $global:AzureProject.ResourceLocation
    $env:RESOURCE_PREFIX = "$($global:AzureProject.Prefix)$($global:AzureProject.Name)"
    $env:RESOURCE_GROUP_NAME = $global:AzureProject.ResourceType.ResourceGroup.Name
    $env:PROJECT_GROUP = $global:AzureProject.GroupName
    $env:PROJECT_NAME = $global:AzureProject.Name
    $env:VM_SIZE = $azProjectVmParameters.VmSize
    $env:RESOURCE_ADMIN_USERNAME = $azProjectVmParameters.ResourceAdminUserName
    $env:STORAGE_ACCOUNT_TIER = $azProjectStorageAccountParameters.StorageAccountPerformanceTier 
    $env:STORAGE_ACCOUNT_KIND = $azProjectStorageAccountParameters.StorageAccountKind
    $env:STORAGE_ACCOUNT_REPLICATION_TYPE = $azProjectStorageAccountParameters.StorageAccountRedundancyConfiguration 
    $env:AUTHORIZED_IP = $azProjectVmParameters.AuthorizedIp
    $env:USER_ID = $azProjectVmParameters.CurrentAzureUserId
    $env:USER_EMAIL = $azProjectVmParameters.CurrentAzureUserEmail

    Set-Location "$($Location.Data)\azure\deployment\vmImages\$($azProjectVmParameters.VmImagePublisher)\$($azProjectVmParameters.VmImageOffer)"

    Write-Host+
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "Ready to deploy DSVM with Terraform via bash" -ForegroundColor Gray
    # Write-Host+
    # bash .\echoEnvVars.sh
    Write-Host+
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine "Continue (Y/N)? " -ForegroundColor Gray
    $response = Read-Host
    if ($response -eq $global:emptyString -or $response.ToUpper().Substring(0,1) -ne "Y") {
        Set-Location $global:Location.Root
        Write-Host+
        return
    }
    Write-Host+

    try {
        bash .\deploy.sh
        Set-Location $global:Location.Root
        Export-AzProjectResourceFile -Project $ProjectName
    }
    catch {
        throw $_
    }
    finally {
        Set-Location $global:Location.Root
    }

    return

}

Remove-PSSession+
