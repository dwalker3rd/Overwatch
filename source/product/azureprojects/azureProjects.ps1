
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

function script:Request-AzProjectVariable {

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
        Write-Host+ -NoTrace "Suggestions: $($Suggestions -join ", ")" -ForegroundColor DarkGray
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

function script:Read-AzProjectVariable {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name
    )
    
    $iniContent = Get-Content $global:AzureProjectIniFile

    $value = $iniContent | Where-Object {$_ -like "$Name*"}
    if (![string]::IsNullOrEmpty($value)) {
        return $value.split("=")[1].Trim()
    } else {
        return
    }

}

function script:Write-AzProjectVariable {
    
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
    
    $iniContent = Get-Content $global:AzureProjectIniFile -Raw

    $valueUpdated = $false
    if (![string]::IsNullOrEmpty($iniContent)) {
        $targetDefinition = [regex]::Match($iniContent,"($Name)\s?=\s?(.*)").Groups[0].Value
        if (![string]::IsNullOrEmpty($targetDefinition)) {
            if ($Delete) {
                $iniContent = $iniContent.Replace("$targetDefinition\r\n","")
            }
            else {
                $iniContent = $iniContent.Replace($targetDefinition,"$Name = $Value")
            }
            Set-Content -Path $global:AzureProjectIniFile -Value $iniContent.Trim()
            $valueUpdated = $true
        }
    }
    if (!$valueUpdated) {
        Add-Content -Path $global:AzureProjectIniFile -Value "$Name = $Value"
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

    $global:AzureProjectIniFile = "$($global:Azure.Group.$GroupName.Project.$ProjectName.Location.Data)\$ProjectName.ini"
    if (!(Test-Path $global:AzureProjectIniFile)) {
        New-Item -Path $global:AzureProjectIniFile -ItemType File | Out-Null
    }

    Write-AzProjectVariable -Name Tenant -Value $Tenant
    Write-AzProjectVariable -Name SubscriptionId -Value $subscriptionId
    Write-AzProjectVariable -Name TenantId -Value $tenantId
    Write-AzProjectVariable -Name GroupName -Value $GroupName
    Write-AzProjectVariable -Name ProjectName -Value $ProjectName
    Write-AzProjectVariable -Name ResourceGroupName -Value $resourceGroupName
   

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

    # get/read/update Prefix
    if ([string]::IsNullOrEmpty($Prefix)) {
        $prefixDefault = Read-AzProjectVariable -Name Prefix
        $prefixes = 
            $global:Azure.Group.Keys | 
                Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                    Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.Prefix} |
                        Sort-Object -Unique
        $prefixes = $prefixes | Sort-Object -Unique
        $Prefix = Request-AzProjectVariable -Name "Prefix" -Suggestions $prefixes -Default $prefixDefault
    }
    # Write-Host+ -NoTrace "Prefix = $Prefix" -ForegroundColor DarkGray
    Write-AzProjectVariable -Name Prefix -Value $Prefix
    # Write-Host+

    # get/read/update ResourceLocation
    $azLocations = Get-AzLocation | Where-Object {$_.providers -contains "Microsoft.Compute"} | 
        Select-Object -Property displayName, location | Sort-Object -Property location
    if ([string]::IsNullOrEmpty($ResourceLocation)) {
        $resourceLocationDefault = Read-AzProjectVariable -Name ResourceLocation
        $resourceLocationSuggestions = 
            $global:Azure.Group.Keys | 
                Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                    Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.ResourceLocation} |
                        Sort-Object -Unique
        $resourceLocationSelections = $azLocations.Location
        $ResourceLocation = Request-AzProjectVariable -Name "ResourceLocation" -Suggestions $resourceLocationSuggestions -Selections $resourceLocationSelections -Default $resourceLocationDefault
    }
    # Write-Host+ -NoTrace "ResourceLocation = $ResourceLocation" -ForegroundColor DarkGray
    Write-AzProjectVariable -Name ResourceLocation -Value $ResourceLocation
    # Write-Host+ 

    $global:Azure.Group.$groupName.Project.$projectName += @{
        IniFile = $global:AzureProjectIniFile
        Prefix = $Prefix
        Invitation = @{
            Message = "You have been invited by $($global:Azure.$tenantKey.DisplayName) to collaborate on project $projectNameUpperCase."
        }
        ConnectedAccount = $_connectedAccount
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
                Name =  ![string]::IsNullOrEmpty($StorageAccountName) ? $StorageAccountName : $azureProjectsConfig.Templates.Resources.StorageAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectName)
                Scope = $null
                Object = $null
                Context = $null
                Parameters = @{}
            }
            StorageContainer = @{
                Name = ![string]::IsNullOrEmpty($StorageContainerName) ? $StorageContainerName : $projectName
                Scope = $null
                Object = $null
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
        }
    }

    $global:Azure.Group.$groupName.Project.$projectName += @{
        ScopeBase = "/subscriptions/$($global:Azure.$tenantKey.Subscription.Id)/resourceGroups/$($global:Azure.Group.$groupName.Project.$projectName.ResourceType.ResourceGroup.Name)/providers"
    }

    $deploymentTypeDefault = "Standard"
    $deploymentTypeSelections = @("Basic","Standard")
    $DeploymentType = Request-AzProjectVariable -Name "DeploymentType" --Selections $deploymentTypeSelections -Default $deploymentTypeDefault

    $global:Azure.Group.$groupName.Project.$projectName.ResourceType.StorageAccount.Parameters = Get-AzProjectStorageParameters
    switch ($DeploymentType) {
        "Basic" {
            Remove-AzProjectVmParameters
        }
        "Standard" {
            $global:Azure.Group.$groupName.Project.$projectName.ResourceType.Vm.Parameters = Get-AzProjectVmParameters
        }
    }

    $global:AzureProject = $global:Azure.Group.$groupName.Project.$projectName

    Set-AzProjectDefaultResourceScopes
    Get-AzProjectDeployedResources

    $global:AzureProject.Initialized = $true
    # $global:AzureProject = $global:Azure.Group.$groupName.Project.$projectName

    return

}
Set-Alias -Name azProjInit -Value Initialize-AzProject -Scope Global

function global:Set-AzProjectDefaultResourceScopes {

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

    return

}

function global:Get-AzProjectDeployedResources {

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
        $mlWorkspaces = get-azresource -resourcegroupname $global:AzureProject.ResourceType.ResourceGroup.Name | Where-Object {$_.ResourceType -eq "Microsoft.MachineLearningServices/workspaces"}
        if ($mlWorkspaces) {
            az login --output None # required until https://github.com/Azure/azure-cli/issues/20150 is resolved
            $global:AzureProject.ResourceType.MLWorkspace.Object = Get-AzMlWorkspace -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.MLWorkspace.Name -ErrorAction SilentlyContinue
        }
    }

}

function global:Export-AzProjectResourceFile {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$true)][Alias("ResourceGroup")][string]$ResourceGroupName,
        [switch]$Overwrite
    )

    $resourceImport = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
    if ((Test-Path $ResourceImport) -and !$Overwrite) {
        Write-Host+
        Write-Host+ -NoTrace "WARNING: $(Split-Path -Path $ResourceImport -Leaf) already exists." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace "Use the -Overwrite switch to overwrite this resource import file." -ForegroundColor DarkGray
        Write-Host+
        return
    }   

    $resourceTypeMap = [PSCustomObject]@{
        "Microsoft.Storage/storageAccounts" = "StorageAccount"
        "Microsoft.Compute/virtualMachines" = "VM"
        "Microsoft.KeyVault/vaults" = "KeyVault"
        "Microsoft.DataFactory/factories" = "DataFactory"
        "Microsoft.Network/networkInterfaces" = "NetworkInterface"
        "Microsoft.Network/bastionHosts" = "Bastion"
    }

    $resources = @()
    foreach ($resource in (Get-AzResource -ResourceGroupName $ResourceGroupName)) {

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

    $resources | Export-Csv -Path $resourceImport -UseQuotes Always -NoTypeInformation

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
                if ($diff -in ('""',"''")) {
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

    # content is a string; convert to an array
    $content = $content -split '\r?\n'

    # property names are in the first row
    $propertyNames = ($content -split '\r?\n')[0] -split ","

    # convert remaining rows to an object
    $_object = $content[1..$content.Length] | 
        ConvertFrom-String -Delimiter "," -PropertyNames $propertyNames |
            Select-Object -Property $propertyNames

    return $_object

}

function global:Grant-AzProjectRole {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UPN","Id","UserId","Email","Mail")][string]$User,
        [switch]$ReferencedResourcesOnly,
        [switch]$RemoveUnauthorizedRoleAssignments,
        [switch]$RemoveExpiredInvitations
    )

    function Get-AzProjectResourceFromScope {

        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Scope
        )

        $resourceName = $Scope.Split("/")[-1]
        $provider = $Scope.Replace($global:AzureProject.ScopeBase,"")
        $provider = $provider.Substring(1,$provider.LastIndexOf("/")-1)
    
        $resourceType = switch ($provider) {
            "Microsoft.Storage/storageAccounts" {"StorageAccount"}
            "Microsoft.Storage/storageAccounts/$($global:AzureProject.ResourceType.StorageAccount.Name)/blobServices/default/containers" {"StorageContainer"}
            "Microsoft.Network/bastionHosts" {"Bastion"}
            "Microsoft.Compute/virtualMachines" {"VM"}
            "Microsoft.MachineLearningServices/workspaces" {"MLWorkspace"}
            "Microsoft.DocumentDB/databaseAccounts" {"CosmosDBAccount "}
            "Microsoft.SqlVirtualMachine/SqlVirtualMachines" {"SqlVM"}
            "Microsoft.KeyVault/vaults" {"KeyVault"}
            "Microsoft.DataFactory/factories" {"DataFactory"}
            "Microsoft.Batch/BatchAccounts" {"BatchAccount"}
        }
    
        return [PSCustomObject]@{
            resourceType = $resourceType
            resourceName = $resourceName
            resourceId = $resourceType + "-" + $resourceName
        }
    
    } 
    
    function Get-AzProjectResourceScope {

        param(
            [Parameter(Mandatory=$true,Position=0)][string]$ResourceType,
            [Parameter(Mandatory=$true,Position=1)][string]$ResourceName
        )
    
        $scope = $global:AzureProject.ResourceType.$ResourceType.Scope
        $scope = ![string]::IsNullOrEmpty($ResourceName) ? ($scope -replace "$($global:AzureProject.ResourceType.$ResourceType.Name)`$", $ResourceName) : $scope
    
        return $scope
    
    }

    Set-CursorInvisible

    $emptyString = ""
    $resourceTypeOrderedList = [ordered]@{
        ResourceGroup = 20
        StorageAccount = 30
        StorageContainer = 35
        VM = 40
        NetworkInterface = 45
        Bastion = 110
        MLWorkspace = 120
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
    $message = "<  -RemoveUnauthorizedRoleAssignments < >40> Removes role assignments not explicity specified in the import files."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    $message = "<  -RemoveExpiredInvitations < >40> Removes accounts with invitations pending more than 30 days."
    Write-Host+ -NoTrace -NoTimeStamp -Parse $message -ForegroundColor DarkGray
    Write-Host+

    if ($User -and $RemoveUnauthorizedRoleAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$RemoveUnauthorizedRoleAssignments switch cannot be used with the `$User parameter." -ForegroundColor Red
        Write-Host+
        return
    }
    if ($User -and $RemoveExpiredInvitations) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$RemoveExpiredInvitations switch cannot be used with the `$User parameter." -ForegroundColor Red
        Write-Host+
        return
    }

    if ($ReferencedResourcesOnly -and $RemoveUnauthorizedRoleAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$ReferencedResourcesOnly and `$RemoveUnauthorizedRoleAssignments switches cannot be used together." -ForegroundColor Red
        Write-Host+
        return
    }

    if ($RemoveUnauthorizedRoleAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  The `"RemoveUnauthorizedRoleAssignments`" switch has been specified." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Role assignments not specified in `"$ProjectName-roleAssignments-import.csv`" will be removed." -ForegroundColor Gray
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

    if ($User) {

        $isUserId = $User -match $global:RegexPattern.Guid
        $isGuestUserPrincipalName = $User -match $global:RegexPattern.UserNameFormat.AzureAD -and $User -like "*#EXT#*"
        $isEmail = $User -match $global:RegexPattern.Mail
        $isMemberUserPrincipalName = $User -match $global:RegexPattern.UserNameFormat.AzureAD

        $isValidUser = $isUserId -or $isEmail -or $isMemberUserPrincipalName -or $isGuestUserPrincipalName
        if (!$isValidUser) {
            throw "'$User' is not a valid object id, userPrincipalName or email address."
        }
        
    }

    #region DATAFILES

        $message = "<  Data validation <.>60> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        $UserImport = "$($global:AzureProject.Location.Data)\$ProjectName-users-import.csv"
        $GroupImport = "$($global:AzureProject.Location.Data)\$ProjectName-groups-import.csv"
        $ResourceImport = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
        $RoleAssignmentImport = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments-import.csv"
        $RoleAssignmentExport = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments-export.csv"

        if (!(Test-Path $UserImport)) {
            Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $UserImport -Leaf) not found." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        if (!(Test-Path $GroupImport)) {
            $groupsInUse = Select-String -Path $RoleAssignmentImport -Pattern "group" -Quiet
            if ($groupsInUse) {
                Write-Host+ -NoTrace "    ($groupsInUse ? 'ERROR' : 'WARNING'): $(Split-Path -Path $GroupImport -Leaf) not found." -ForegroundColor ($groupsInUse ? "DarkRed" : "DarkYellow")
                Write-Host+
                return
            }
        }

        if (!(Test-Path $ResourceImport)) {
            Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $ResourceImport -Leaf) not found." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        if (!(Test-Path $RoleAssignmentImport)) {
            Write-Host+ -NoTrace "    ERROR: $(Split-Path -Path $RoleAssignmentImport -Leaf) not found." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        #region USER IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $UserImport" -ForegroundColor DarkGray
            $users = @()
            $users += Import-AzProjectFile $UserImport
            if ($User) {
                # if $User has been specified, filter $users to the specified $User only
                $users = $users | Where-Object {$_.signInName -eq $User}
                if ($users.Count -eq 0) {
                    Write-Host+ -NoTrace -NoSeparator  "      ERROR: User $User not referenced in project `"$($ProjectName)`"'s import files." -ForegroundColor Red
                    Write-Host+
                    return
                }
                $azureADUser = Get-AzureADUser -Tenant $tenantKey -User $User
                if (!$azureADUser) {
                    Write-Host+ -NoTrace -NoSeparator  "      ERROR: $User not found in Azure tenant `"$Tenant`"" -ForegroundColor Red
                    Write-Host+
                    return
                }
                $User = $azureADUser.mail
            }

        #endregion USER IMPORT
        #region GROUP IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $GroupImport" -ForegroundColor DarkGray
            $groups = @()
            if (Test-Path $GroupImport) {
                $groups += Import-AzProjectFile $GroupImport
                if ($User) {
                    # if $User has been specified, filter $groups to only those containing $User
                    $groups = $groups | Where-Object {$_.user -eq $User}
                }
            }

        #endregion GROUP IMPORT
        #region RESOURCE IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $ResourceImport" -ForegroundColor DarkGray
            $resources = @(); $resources += [PSCustomObject]@{resourceType = "ResourceGroup"; resourceName = $resourceGroupName; resourceId = "ResourceGroup-$resourceGroupName"; resourceScope = $global:AzureProject.ResourceType.ResourceGroup.Scope; resourceObject = $null; resourcePath = $null}
            $resources += Import-AzProjectFile -Path $ResourceImport | Select-Object -Property resourceType, resourceName, resourceId, @{Name="resourceScope"; Expression={$null}}, @{Name="resourcePath"; Expression={$null}}, @{Name="resourceObject"; Expression={$null}}, @{Name="resourceContext"; Expression={$null}}, resourceParent | Sort-Object -Property resourceType, resourceName, resourceId   

            $duplicateResourceIds = $resources | Group-Object -Property resourceId | Where-Object {$_.Count -gt 1}
            if ($duplicateResourceIds) {
                $errorMessage = "ERROR: Duplicate resource ids found in $(Split-Path -Path $ResourceImport -Leaf)."
                Write-Host+ -NoTrace "    $errorMessage" -ForegroundColor DarkRed
                foreach ($duplicateResourceId in $duplicateResourceIds) {
                    Write-Host+ -NoTrace "    $($global:asciiCodes.RightArrowWithHook)  Resource id '$($duplicateResourceId.Name)' occurs $($duplicateResourceId.Count) times" -ForegroundColor DarkGray
                }
                Write-Host+
                return
            }

        #endregion RESOURCE IMPORT
        #region ROLE ASSIGNMENTS IMPORT

            Write-Host+ -NoTrace -NoSeparator "    $RoleAssignmentImport" -ForegroundColor DarkGray
            $roleAssignmentsFromFile = Import-AzProjectFile -Path $RoleAssignmentImport
            if ($User) {
                # if $User has been specified, filter $roleAssignmentsFromFile to those relevent to $User
                $roleAssignmentsFromFile = $roleAssignmentsFromFile | Where-Object {$_.assigneeType -eq "user" -and $_.assignee -eq $User -or ($_.assigneeType -eq "group" -and $_.assignee -in $groups.group)}
            }

        #endregion ROLE ASSIGNMENTS IMPORT

        # if the $ReferencedResourcesOnly switch has been specified, then filter $resources to only those relevant to $users
        # NOTE: this is faster, but it prevents the function from finding/removing roleAssignments from other resources
        if ($ReferencedResourcesOnly) {
          $resources = $resources | Where-Object {$_.resourceId -in $roleAssignmentsFromFile.resourceId}
        }

        $missingUsers = @()
        # if (!$User) {
            $missingUsers += $groups | Where-Object {$_.user -notin $users.signInName} | Select-Object -Property @{Name="signInName"; Expression={$_.user}}, @{Name="source"; Expression={"Groups"}}
            $missingUsers += $roleAssignmentsFromFile | Where-Object {$_.assigneeType -eq "user" -and $_.assignee -notin $users.signInName} | Select-Object -Property @{Name="signInName"; Expression={$_.assignee}}, @{Name="source"; Expression={"Role Assignments"}}
        # }

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
                        $nicName = $nic.Id.split("/")[-1]
                        $nicScope = $nic.Id
                        $nicObject = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $nicName

                        $nicResource = $resources | Where-Object {$_.resourceType -eq $nicType -and $_.resourceScope -eq $nicScope}
                        if (!$nicResource) {

                            Write-Host+ -NoTrace -NoSeparator "    $($nic.Id.split("/resourceGroups/")[1])" -ForegroundColor DarkGray

                            if ([string]::IsNullOrEmpty($global:AzureProject.ResourceType.NetworkInterface.VmName) -or $global:AzureProject.ResourceType.NetworkInterface.VmName -eq $vm.Name) {
                                if ($global:AzureProject.ResourceType.NetworkInterface.Scope -notcontains $nicScope) {
                                    $global:AzureProject.ResourceType.NetworkInterface += @{
                                        VmName = $vm.Name
                                        Name = $nicName
                                        Scope = $nicScope 
                                        Object = $nicObject
                                    }
                                }
                            }

                            $nicResource = [PSCustomObject]@{
                                resourceId = $nicType + "-" + $nicName
                                resourceType = $nicType
                                resourceName = $nicName
                                resourceScope = $nicScope
                                resourceParent = $resource.resourceId
                                resourcePath = "$resourceGroupName/$($resource.resourceType)/$($resource.resourceName)/$nicType/$nicName"
                            }
                            $resources += $nicResource

                        }

                        $nicRole = "Reader"
                        foreach ($resourceRoleAssignment in ($roleAssignmentsFromFile | Where-Object {$_.resourceId -eq $nicResource.resourceId -and $_.role -ne $nicRole} | Sort-Object -Property assigneeType,assignee -Unique)) {
                            $roleAssignmentsFromFile += [PSCustomObject]@{
                                resourceId = $nicResource.resourceId
                                role = $nicRole
                                assigneeType = $resourceRoleAssignment.assigneeType
                                assignee = $resourceRoleAssignment.assignee
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
            # Write-Host+ -NoTrace -NoNewLine "    Continue (Y/N)? " -ForegroundColor DarkYellow
            # $response = Read-Host
            # if ($response -eq $global:emptyString -or $response.ToUpper().Substring(0,1) -ne "Y") {
            #     Write-Host+
            #     return
            # }
        }

        Write-Host+
        $message = "<  Resource verification <.>60> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    #endregion VERIFY RESOURCES

    #region VERIFY USERS

        Write-Host+
        $message = "<  User verification <.>60> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray   
        Write-Host+ 

        $signInNames = @()
        $signInNames += $users.signInName | Sort-Object -Unique

        # Initialize-AzureConfig
        # Connect-AzureAD -Tenant $tenantKey

        $authorizedProjectUsers = @()
        $unauthorizedProjectUsers = @()
        foreach ($signInName in $signInNames) {
            $azureADUser = Get-AzureADUser -Tenant $tenantKey -User $signInName
            if ($azureADUser) {
                if ($azureADUser.accountEnabled) {
                    $authorizedProjectUsers += $azureADUser
                }
                else {
                    $unauthorizedProjectUsers += $azureADUser
                }
            }
        }
        $authorizedProjectUsers | Add-Member -NotePropertyName authorized -NotePropertyValue $true
        $authorizedProjectUsers | Add-Member -NotePropertyName reason -NotePropertyValue ""
        $unauthorizedProjectUsers | Add-Member -NotePropertyName authorized -NotePropertyValue $false
        $unauthorizedProjectUsers | Add-Member -NotePropertyName reason -NotePropertyValue "ACCOUNT DISABLED"

        #region UNAUTHORIZED

            # identify unauthorized project users and role assignments
            # if $User has been specified, skip this step
            $unauthorizedProjectRoleAssignments = @()
            if (!$User) {
                $projectRoleAssignments = Get-AzRoleAssignment -ResourceGroupName $ResourceGroupName | 
                    Where-Object {$_.ObjectType -eq "User" -and $_.RoleDefinitionName -ne "Owner" -and $_.Scope -like "*$ResourceGroupName*" -and $_.SignInName -notlike "*admin_path.org*"}
                $unauthorizedProjectRoleAssignments = ($projectRoleAssignments | Where-Object {$authorizedProjectUsers.userPrincipalName -notcontains $_.SignInName})
                foreach ($invalidProjectRoleAssignment in $unauthorizedProjectRoleAssignments) {
                    $unauthorizedAzureADUser = Get-AzureADUser -Tenant $tenantKey -User $invalidProjectRoleAssignment.SignInName
                    $unauthorizedAzureADUser | Add-Member -NotePropertyName authorized -NotePropertyValue $false
                    $unauthorizedAzureADUserReason = !$unauthorizedAzureADUser.accountEnabled ? "ACCOUNT DISABLED" : "UNAUTHORIZED"
                    $unauthorizedAzureADUser | Add-Member -NotePropertyName reason -NotePropertyValue $unauthorizedAzureADUserReason
                    if ($unauthorizedAzureADUser.mail -notin $unAuthorizedProjectUsers.mail) {
                        $unauthorizedProjectUsers += $unauthorizedAzureADUser
                        $signInNames += $unauthorizedAzureADUser.mail
                    }
                }
                $signInNames = $signInNames | Sort-Object -Unique
            }
        
        #endregion UNAUTHORIZED

        $members = @()
        $members += $authorizedProjectUsers | Where-Object {$_.userType -eq "Member"} 
        $members += $unauthorizedProjectUsers | Where-Object {$_.userType -eq "Member"} 
        if ($members) {

            $message = "<    Member < >40> Status"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray
            $message = "<    ------ < >40> ------"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray

            foreach ($member in $members) {
                $message = $member.authorized ? "<    $($member.mail) < >40> Verified" : "<    $($member.mail) < >40> *** $($member.reason) ***"
                Write-Host+ -NoTrace -Parse $message -ForegroundColor ($member.authorized ? "DarkGray" : "DarkRed")
            }
            
            Write-Host+

        }

        $guests = @()
        $guests += $authorizedProjectUsers | Where-Object {$_.userType -ne "Member"} 
        $guests += $unauthorizedProjectUsers | Where-Object {$_.userType -ne "Member"} 
        if ($guests) {

            $message = "<    Guest < >40> Status   Date"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray
            $message = "<    ----- < >40> ------   ----"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkGray

            foreach ($signInName in $signInNames | Where-Object {$_ -notin $members.mail}) {

                $guest = $guests | Where-Object {$_.mail -eq $signInName}

                $message = "<    $($guest.mail) < >40> "
                Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray
            
                if (!$guest) {
                    $fullName = ($users | Where-Object {$_.signInName -eq $signInName})[0].fullName
                    $invitation = Send-AzureADInvitation -Tenant $tenantKey -Email $signInName -DisplayName $fullName -Message $global:AzureProject.Invitation.Message
                    $invitation | Out-Null
                    Write-Host+ -NoTrace -NoTimeStamp "Invitation sent" -ForegroundColor DarkGreen
                }
                else {
                    $externalUserState = $guest.externalUserState -eq "PendingAcceptance" ? "Pending " : $guest.externalUserState
                    $externalUserStateChangeDateTime = $guest.externalUserStateChangeDateTime

                    if ($guest.externalUserState -eq "PendingAcceptance") {
                        if (([datetime]::Now - $externalUserStateChangeDateTime).TotalDays -gt 30) {
                            if ($RemoveExpiredInvitations) {
                                Disable-AzureADUser -Tenant $tenantKey -User $guest
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

                    if (!$guest.authorized) {
                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine " *** $($guest.Reason) ***" -ForegroundColor DarkRed
                    }

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

    #endregion VERIFY USERS

    #region ROLEASSIGNMENT

        $roleAssignments = [PsCustomObject]@()
        foreach ($roleAssignment in $roleAssignmentsFromFile) {

            if ($roleAssignment.assigneeType -eq "group") {
                $members = $groups | Where-Object {$_.group -eq $roleAssignment.assignee}
                foreach ($member in $members) {
                    foreach ($resource in ($resources | Where-Object {$_.resourceId -eq $roleAssignment.resourceId})) {
                        $roleAssignments += [PsCustomObject]@{
                            resourceId = $roleAssignment.resourceId
                            resourceType = $resource.resourceType
                            resourceName = $resource.resourceName
                            role = $roleAssignment.role
                            # assigneeType = "user"
                            signInName = $member.user
                            resourceTypeSortOrder = $resourceTypeOrderedList.($resource.resourceType) ?? $resourceTypeSortOrder.default
                            authorized = $true
                        }
                    }
                }
            }
            elseif ($roleAssignment.assigneeType -eq "user") {
                foreach ($resource in ($resources | Where-Object {$_.resourceId -eq $roleAssignment.resourceId})) {
                    $roleAssignments += [PsCustomObject]@{
                        resourceId = $roleAssignment.resourceId
                        resourceType = $resource.resourceType
                        resourceName = $resource.resourceName
                        role = $roleAssignment.role
                        # assigneeType = $roleAssignment.assigneeType
                        signInName = $roleAssignment.assignee
                        resourceTypeSortOrder = $resourceTypeOrderedList.($resource.resourceType) ?? $resourceTypeSortOrder.default
                        authorized = $true
                    }
                }
            }

        }

        foreach ($unauthorizedProjectRoleAssignment in $unauthorizedProjectRoleAssignments) {
            $resourceFromScope = Get-AzProjectResourceFromScope -Scope $unauthorizedProjectRoleAssignment.Scope
            $roleAssignments += [PsCustomObject]@{
                resourceId = $resourceFromScope.resourceType + "-" + $resourceFromScope.resourceName
                resourceType = $resourceFromScope.resourceType
                resourceName = $resourceFromScope.resourceName
                role = $unauthorizedProjectRoleAssignment.RoleDefinitionName
                # assigneeType = $roleAssignment.assigneeType
                signInName = ($unauthorizedProjectUsers | Where-Object {$_.userPrincipalName -eq $unauthorizedProjectRoleAssignment.SignInName}).mail
                resourceTypeSortOrder = $resourceTypeOrderedList.($resourceFromScope.resourceType) ?? $resourceTypeSortOrder.default
                authorized = $false
            }
        }

        $roleAssignments = $roleAssignments | Sort-Object -Property resourceTypeSortOrder, resourceType, resourceName
        if ($User) {
            # if $User has been specified, filter $roleAssignments to those relevant to $User
            $roleAssignments = $roleAssignments | Where-Object {$_.signInName -eq $User}
        }
        # export $roleAssignments
        # if $User has been specified, skip this step
        if (!$User) {
            $roleAssignments | Select-Object -Property resourceType,resourceName,role,signInName | Export-Csv -Path $RoleAssignmentExport -UseQuotes Always -NoTypeInformation  
        }

        Write-Host+
        $message = "<  Role assignment <.>60> PENDING"
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

        foreach ($signInName in $signInNames) {
            
            Write-Host+ -NoTrace -NoNewLine "    $signInName" -ForegroundColor Gray

            $assignee = Get-AzureADUser -Tenant $tenantKey -User $signInName
            if (!$assignee) {
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator " (NotFound)" -ForegroundColor DarkGray,DarkRed,DarkGray
                Write-Host+
                continue
            }

            $externalUserState = $assignee.externalUserState -eq "PendingAcceptance" ? "Pending" : $assignee.externalUserState
            $externalUserStateColor = $assignee.externalUserState -eq "Pending" ? "DarkYellow" : "DarkGray"
            if ($externalUserState -eq "Pending") {
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -NoSeparator " (",$externalUserState,")" -ForegroundColor DarkGray,DarkYellow,DarkGray
            }
            Write-Host+

            Write-Host+ -NoTrace "    $($emptyString.PadLeft($signInName.Length,"-"))" -ForegroundColor Gray

            $identity = $assignee.identities | Where-Object {$_.issuer -eq $global:Azure.$tenantKey.Tenant.Domain}
            $signInType = $identity.signInType
            $signIn = $signInType -eq "userPrincipalName" ? $assignee.userPrincipalName : $signInName
            
            $resourceTypes = @()
            $resourceTypes += ($roleAssignments | Where-Object {$_.signInName -eq $signInName} | Sort-Object -Property resourceTypeSortOrder,resourceType -Unique ).resourceType 
            if (!$ReferencedResourcesOnly) {
                $resourceTypes += $global:AzureProject.ResourceType.Keys | Where-Object {$_ -notin $resourceTypes -and $_ -ne "ResourceGroup" -and $global:AzureProject.ResourceType.$_.Object}
            }

            # sort by resourceScope to ensure children are after parents
            $resourcesToCheck = $resources | Sort-Object -Property resourcePath

            # if the $UserResourcesOnly switch has been specified, then filter $resources to only those relevant to the current assignee
            # NOTE: this is faster, but it prevents the function from finding/removing roleAssignments from other resources
            if ($ReferencedResourcesOnly) {
                $resourcesToCheck = $resources | Where-Object {$_.resourceId -in (($roleAssignments | Where-Object {$_.signInName -eq $signInName}).resourceId)}
            }

            $roleAssignmentCount = 0
            foreach ($resource in $resourcesToCheck) { #| Where-Object {$_.resourceType -eq $resourceType}) {

                $unauthorizedRoleAssignment = $false

                $resourceType = $resource.resourceType
                $resourceName = ![string]::IsNullOrEmpty($resource.resourceName) ? $resource.resourceName : ($global:AzureProject.ResourceType.($resourceType).Scope).split("/")[-1]
                $resourceScope = $resource.resourceScope ?? (Get-AzProjectResourceScope -ResourceType $resourceType -ResourceName $resourceName)

                $resourceParent = $resources | Where-Object {$_.resourceId -eq $resource.resourceParent}
                $message = "    " + (![string]::IsNullOrEmpty($resourceParent) ? "$($global:asciiCodes.RightArrowWithHook)  " : "") + "$($resourceType)/$($resourceName)"
                $message = ($message.Length -gt 55 ? $message.Substring(0,55) + "`u{22EF}" : $message) + " : "    

                $currentRoleAssignments = Get-AzRoleAssignment -Scope $resourceScope -SignInName $signIn | Sort-Object -Property Scope
                # exclude currentRoleAssignments for resources that are children of $resourceScope
                $currentRoleAssignments = $currentRoleAssignments | Where-Object {($resourceScope -eq $_.Scope -or $resourceScope.StartsWith($_.Scope)) -and $_.Scope.Length -le $resourceScope.Length}
                if ($currentRoleAssignments) {
                    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Format-Leader -Length 60 -Adjust (($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray 
                    foreach ($currentRoleAssignment in $currentRoleAssignments) {
                        $message = $currentRoleAssignment.RoleDefinitionName
                        if ($currentRoleAssignment.Scope -ne $resourceScope -and $resourceScope -like "$($currentRoleAssignment.Scope)*") {
                            $message = "^" + $message
                        }
                        if ($currentRoleAssignments.Count -gt 1 -and $foreach.Current -ne $currentRoleAssignments[-1]) {
                            $message += ", "
                        }
                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGray
                    }
                }
                $rolesWrittenCount = $currentRoleAssignments.Count

                $requiredRoleAssignments = $roleAssignments | Where-Object {$_.signInName -eq $signInName -and $_.resourceType -eq $resourceType}
                if (![string]::IsNullOrEmpty($resourceName)) {
                    $requiredRoleAssignments =  $requiredRoleAssignments | Where-Object {$_.resourceName -eq $resourceName}
                }
                if ($requiredRoleAssignments) {
                    if (!$currentRoleAssignments) {
                        Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Format-Leader -Length 60 -Adjust (($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray 
                    }
                    foreach ($roleAssignment in $requiredRoleAssignments) {
                        $currentRoleAssignment = Get-AzRoleAssignment -Scope $resourceScope -SignInName $signIn -RoleDefinitionName $roleAssignment.role
                        if (!$currentRoleAssignment -and ($currentRoleAssignment.RoleDefinitionName -ne $roleAssignment.role)) {
                            New-AzRoleAssignment+ -Scope $resourceScope -RoleDefinitionName $roleAssignment.role -SignInNames $signIn -ErrorAction SilentlyContinue | Out-Null
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

                $currentRoleAssignmentsThisResourceScope = $currentRoleAssignments | Where-Object {$_.Scope -eq $global:AzureProject.ResourceType.($resourceType).Scope}
                if ($currentRoleAssignmentsThisResourceScope) {
                    foreach ($currentRoleAssignment in $currentRoleAssignmentsThisResourceScope) {
                        if ($currentRoleAssignment.RoleDefinitionName -notin $requiredRoleAssignments.role -or ($RemoveUnauthorizedRoleAssignments -and $unauthorizedRoleAssignment)) {

                            $resourceLocksCanNotDelete = Get-AzResourceLock -Scope $resourceScope | Where-Object {$_.Properties.level -eq "CanNotDelete"}
                            $resourceLocksCanNotDelete | Foreach-Object {Remove-AzResourceLock -Scope $resourceScope -LockName $_.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null}

                            Remove-AzRoleAssignment -Scope $resourceScope -RoleDefinitionName $currentRoleAssignment.RoleDefinitionName -SignInName $signIn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null

                            $resourceLocksCanNotDelete | Foreach-Object {Set-AzResourceLock -Scope $resourceScope -LockName $_.Name -LockLevel $_.Properties.level -LockNotes $_.Properties.notes -Force} | Out-Null

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

                $roleAssignmentCount += $rolesWrittenCount
            
            }

            if ($roleAssignmentCount -eq 0) {
                Write-Host+ -NoTrace "    none" -ForegroundColor DarkGray
            }

            Write-Host+

        }

        $message = "<  Role assignment <.>60> SUCCESS"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    #endregion ROLEASSIGNMENT

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

function Get-AzProjectStorageParameters {

    # get/read/update StorageAccountPerformanceTier
    $storageAccountPerformanceTiers = @("Standard","Premium")
    $storageAccountPerformanceTierDefault = "Standard"
    $storageAccountPerformanceTier = Request-AzProjectVariable -Name "StorageAccountPerformanceTier" -Selections $storageAccountPerformanceTiers -Default $storageAccountPerformanceTierDefault
    Write-AzProjectVariable -Name StorageAccountPerformanceTier -Value $storageAccountPerformanceTier

    # get/read/update StorageAccountRedundancyConfiguration
    $storageAccountRedundancyConfigurations = @("LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS")
    $storageAccountRedundancyConfigurationDefault = "LRS"
    $storageAccountRedundancyConfiguration = Request-AzProjectVariable -Name "StorageAccountRedundancyConfiguration" -Selections $storageAccountRedundancyConfigurations -Default $storageAccountRedundancyConfigurationDefault
    Write-AzProjectVariable -Name StorageAccountRedundancyConfiguration -Value $storageAccountRedundancyConfiguration

    $storageAccountSku = "$($StorageAccountPerformanceTier)_$($storageAccountRedundancyConfiguration)"

    # get/read/update StorageAccountKind
    $storageAccountKinds = @("StorageV2","BlockBlobStorage","FileStorage","Storage","BlobStorage")
    $storageAccountKindDefault = "BlobStorage"
    $storageAccountKind = Request-AzProjectVariable -Name "StorageAccountKind" -Selections $storageAccountKinds -Default $storageAccountKindDefault
    Write-AzProjectVariable -Name StorageAccountKind -Value $storageAccountKind

    return [PSCustomObject]@{
        StorageAccountPerformanceTier = $storageAccountPerformanceTier
        StorageAccountRedundancyConfiguration = $storageAccountRedundancyConfiguration
        StorageAccountSku = $storageAccountSku
        StorageAccountKind = $storageAccountKind
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

    param(
        [switch]$AllowNone
    )

    $ResourceLocation = $global:AzureProject.ResourceLocation
    $Prefix = $global:AzureProject.$ProjectName.Prefix

    # get/read/update VmSize
    $availableVmSizes = Get-AzAvailableVmSizes -ResourceLocation $ResourceLocation -HasSufficientQuota
    $vmSizeDefault = (Read-AzProjectVariable -Name vmSize) ?? "Standard_D4s_v3"
    $vmSizeSuggestions = @()
    $vmSizeSuggestions +=  
        $global:AzureProject.Keys | 
            Foreach-Object { $_projectName = $_; $global:AzureProject.$_projectName.vmSize} |
                Sort-Object -Unique
    $vmSizeSelections = @()
    $vmSizeSelections += $availableVmSizes.Name | Sort-Object
    $vmSize = Request-AzProjectVariable -Name "VmSize" -Suggestions $vmSizeSuggestions -Selections $vmSizeSelections -Default $vmSizeDefault -AllowNone:$($AllowNone:IsPresent)
    Write-AzProjectVariable -Name VmSize -Value $vmSize

    # need to look at project providers and see if compute is included
    if ($vmSize -ne "None") {

        # get/read/update VmImagePublisher
        $vmImagePublishers = @("microsoft-dsvm")
        $vmImagePublisher = Request-AzProjectVariable -Name "VmImagePublisher" -Suggestions $vmImagePublishers -Selections $vmImagePublishers
        Write-AzProjectVariable -Name VmImagePublisher -Value $vmImagePublisher

        # get/read/update VmImageOffer
        $vmImageOffers = @("linux","windows")
        $vmImageOffer = Request-AzProjectVariable -Name "VmImageOffer" -Suggestions $vmImageOffers -Selections $vmImageOffers
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
        [Parameter(Mandatory=$true)][ValidateSet("Basic","Standard")][string]$DeploymentType,
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    switch ($DeploymentType) {
        "Basic" {  
            Deploy-AzProjectBasic -Tenant $tenantKey -Project $ProjectName
        }
        "Standard" {
            Deploy-AzProjectStandard -Tenant $tenantKey -Project $ProjectName
        }
    }
    
    Set-AzProjectDefaultResourceScopes
    Get-AzProjectDeployedResources

    return

}
Set-Alias -Name azProjDeploy -Value Deploy-AzProject -Scope Global

function global:Deploy-AzProjectBasic {

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
    $message = "<  Resource creation <.>60> PENDING" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    #region RESOURCE GROUP

        $message = "<    ResourceGroup/$($resourceGroupName) <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
        
        $resourceGroup = Get-AzResourceGroup -Name $global:AzureProject.ResourceType.ResourceGroup.Name -ErrorAction SilentlyContinue
        if ($resourceGroup) {
            $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
        }
        else {
            $resourceGroup = New-AzResourceGroup+ -Tenant $tenantKey -ResourceGroupName $resourceGroupName -Location $resourceLocation
            $global:AzureProject.ResourceType.ResourceGroup.Object = $resourceGroup
            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }

    #endregion RESOURCE GROUP
    #region STORAGE ACCOUNT

        $azProjectStorageParameters = $global:AzureProject.ResourceType.StorageAccount.Parameters

        $storageAccountName = $global:AzureProject.ResourceType.StorageAccount.Name
        $message = "<      StorageAccount/$storageAccountName <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray

        $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
        if ($storageAccount) {
            $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
        }
        else {
            $storageAccount = New-AzStorageAccount+ -ResourceGroupName $resourceGroupName -Name $storageAccountName -Location $resourceLocation -SKU $azProjectStorageParameters.StorageAccountSku
            $global:AzureProject.ResourceType.StorageAccount.Object = $storageAccount
            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
        $storageAccountContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
        $global:AzureProject.ResourceType.StorageAccount.Context = $storageAccountContext

    #endregion STORAGE ACCOUNT
    #region STORAGE CONTAINER

        $StorageContainerName = (![string]::IsNullOrEmpty($StorageContainerName) ? $StorageContainerName : "data").ToLower()
        $message = "<      $($global:asciiCodes.RightArrowWithHook)  StorageContainer/$StorageContainerName <.>60> PENDING"
        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray

        $storageContainer = Get-AzStorageContainer -Context $storageAccountContext -Name $StorageContainerName -ErrorAction SilentlyContinue
        if ($storageContainer) {
            $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
        }
        else {
            $storageContainer = New-AzStorageContainer+ -Context $storageAccountContext -Name $StorageContainerName -Permission Off
            $global:AzureProject.ResourceType.StorageContainer.Object = $storageContainer
            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }

    #endregion STORAGE CONTAINER
    
    Write-Host+
    $message = "<  Resource creation <.>60> SUCCESS" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    # scan resource group and create resource import file
    Export-AzProjectResourceFile -ResourceGroupName $resourceGroupName -Project $ProjectName
    
}
Set-Alias -Name azProjNew -Value New-AzProject -Scope Global

function global:Deploy-AzProjectStandard {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    if ($azProjectVmParameters.VmSize -eq "None") {
        Write-Host+ -NoTrace "VmSize cannot be null for a Microsoft DSVM project." -ForegroundColor DarkRed
        return
    }

    $azProjectStorageParameters = $global:AzureProject.ResourceType.StorageAccount.Parameters
    $azProjectVmParameters = $global:AzureProject.ResourceType.VM.Parameters

    $env:SUBSCRIPTION_ID = $global:Azure.$tenantKey.Subscription.Id
    $env:TENANT_ID = $global:Azure.$tenantKey.Tenant.Id
    $env:RESOURCE_LOCATION = $global:AzureProject.ResourceLocation
    $env:RESOURCE_PREFIX = $global:AzureProject.Prefix
    $env:RESOURCE_GROUP_NAME = $global:AzureProject.ResourceType.ResourceGroup.Name
    $env:VM_SIZE = $azProjectVmParameters.VmSize
    $env:RESOURCE_ADMIN_USERNAME = $azProjectVmParameters.ResourceAdminUserName
    $env:STORAGE_ACCOUNT_TIER = $azProjectStorageParameters.StorageAccountSku 
    $env:AUTHORIZED_IP = $azProjectVmParameters.AuthorizedIp
    $env:USER_ID = $azProjectVmParameters.CurrentAzureUserId
    $env:USER_EMAIL = $azProjectVmParameters.CurrentAzureUserEmail

    Set-Location "$($Location.Data)\azure\deployment\vmImages\$VmImagePublisher\$VmImageOffer"

    bash .\echoEnvVars.sh
    
    Set-Location $global:Location.Root

    # scan resource group and create resource import file
    Export-AzProjectResourceFile -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Project $ProjectName

    return

}

Remove-PSSession+
