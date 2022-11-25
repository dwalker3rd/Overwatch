#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"

$global:Product = @{Id="AzureProjects"}
. $PSScriptRoot\definitions.ps1

function Initialize-AzProject {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$Project,
        [Parameter(Mandatory=$true)][string]$Group,
        [Parameter(Mandatory=$false)][Alias("StorageAccount")][string]$StorageAccountName,
        [Parameter(Mandatory=$false)][Alias("StorageContainer")][string]$StorageContainerName,
        [Parameter(Mandatory=$false)][string]$Prefix,
        [switch]$Force
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    Connect-AzureAD -Tenant $tenantKey

    # add new tenant to AzureProjects
    if ($null -eq $global:AzureProjects.Tenant.$tenantKey) {
        $global:AzureProjects.Tenant += @{
            $tenantKey = @{
                Name = $tenantKey
                DisplayName = $Tenant
                Location = @{
                    Data = "$($global:AzureProjects.Location.Data)\$tenantKey"
                }
                Group= @{}
                ConnectedAccount = Connect-AzAccount+ -Tenant $tenantKey
            }
        }
    }

    # create tenant directory
    if (!(Test-Path -Path $global:AzureProjects.Tenant.$tenantKey.Location.Data)) {
        New-Item -Path $global:AzureProjects.Location.Data -Name $tenantKey -ItemType "directory" | Out-Null
    }    

    $_project = $Project.ToLower()
    $_group = $Group.ToLower()

    # add new group to AzureProjects
    if ($null -eq $global:AzureProjects.Tenant.$tenantKey.Group.$_group) {
        $global:AzureProjects.Tenant.$tenantKey.Group += @{
            $_group = @{
                Name = $_group
                DisplayName = $Group
                Location = @{
                    Data = "$($global:AzureProjects.Tenant.$tenantKey.Location.Data)\$_group"
                }
                $Tenant = $tenantKey
                Project = @{}
            }
        }
    }

    # create group directory
    if (!(Test-Path -Path $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Location.Data)) {
        New-Item -Path $global:AzureProjects.Tenant.$tenantKey.Location.Data -Name $_group -ItemType "directory" | Out-Null
    }

    # project is already initialized
    if ([bool]$global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.$_project.Initialized) {

        Write-Host+
        Write-Host+ -NoTrace "WARN: Project $Project has already been initialized." -ForegroundColor DarkYellow
        Write-Host+ -Iff $(!($Force.IsPresent)) -NoTrace "WARN: To reinitialize, add the -Force switch." -ForegroundColor DarkYellow
        Write-Host+ -Iff $($Force.IsPresent) -NoTrace "WARN: Reinitializing with FORCE." -ForegroundColor DarkYellow
        Write-Host+
        
        if (!$Force) {
            return $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.$_project
        }
        $Force = $false

        $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.Remove($_project)
        # Remove-Variable AzureProject

    }

    Write-Host+ -Iff $($Force.IsPresent) 
    Write-Host+ -Iff $($Force.IsPresent) -NoTrace "INFO: Ignoring -Force switch." -ForegroundColor DarkGray
    Write-Host+ -Iff $($Force.IsPresent) 
    $Force = $false    

    #add new project to AzureProjects
    $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project += @{
        $_project = @{
            Name = $_project
            DisplayName = $Project
            Location = @{
                Data = "$($global:AzureProjects.Tenant.$tenantKey.Group.$_group.Location.Data)\$_project"
                Credentials = "$($global:AzureProjects.Tenant.$tenantKey.Group.$_group.Location.Data)\$_project"
            }
            Tenant = $tenantKey
            Group = $_group
        }
    }
    
    #create project directory 
    if (!(Test-Path -Path $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.$_project.Location.Data)) {
        New-Item -Path $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Location.Data -Name $_project -ItemType "directory" | Out-Null
    }

    # get/read/update $Prefix
    $prefixIni = "$($global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.$_project.Location.Data)\$_project-prefix.ini"
    if (!$Prefix) {
        if (Test-Path $prefixIni) {
            $Prefix = (Get-Content $prefixIni | Where-Object {$_ -like "prefix*"}).split(" : ")[1].Trim()
        }
        $Prefix = $Prefix ?? $global:AzureAD.$tenantKey.Prefix
    }
    if (!(Test-Path $prefixIni)) {
        New-Item -Path $prefixIni -ItemType File | Out-Null
    }
    Clear-Content $prefixIni
    Add-Content $prefixIni "prefix : $Prefix"

    $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.$_project += @{
        Prefix = $Prefix
        AzureAD = @{
            Tenant = $tenantKey
            Invitation = @{
                Message = "You have been invited by $($global:AzureAD.$tenantKey.DisplayName) to collaborate on project $($Project.ToUpper())."
            }
            Location = $global:AzureAD.$tenantKey.Defaults.Location
        }
        ResourceType = @{
            ResourceGroup = @{
                Name = $global:AzureAD.$tenantKey.Defaults.ResourceGroup.Name.Template.replace("<0>",$_group).replace("<1>",$_project)
                Scope = "/subscriptions/$($global:AzureAD.$tenantKey.Subscription.Id)/resourceGroups/" + $global:AzureAD.$tenantKey.Defaults.ResourceGroup.Name.Template.replace("<0>",$_group).replace("<1>",$_project)
                Object = $null
            }
            BatchAccount = @{
                Name =  $global:AzureAD.$tenantKey.Defaults.BatchAccount.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project)
                Scope = $null
                Object = $null
                Context = $null
            }
            StorageAccount = @{
                Name =  ![string]::IsNullOrEmpty($StorageAccountName) ? $StorageAccountName : $global:AzureAD.$tenantKey.Defaults.StorageAccount.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project)
                Scope = $null
                Object = $null
                Context = $null
            }
            StorageContainer = @{
                Name = ![string]::IsNullOrEmpty($StorageContainerName) ? $StorageContainerName : $_project
                Scope = $null
                Object = $null
            }
            Bastion = @{
                Name = $global:AzureAD.$tenantKey.Defaults.Bastion.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project)
                Scope = $null
                Object = $null
            }
            VM = @{
                Name = $global:AzureAD.$tenantKey.Defaults.VM.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project).replace("<2>","01")
                Admin = $global:AzureAD.$tenantKey.Defaults.VM.Admin.Template.replace("<0>",$Prefix).replace("<1>",$_project)
                Scope = $null
                Object = $null
            }
            NetworkInterface = @()
            MLWorkspace = @{
                Name = $global:AzureAD.$tenantKey.Defaults.MLWorkspace.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            CosmosDBAccount = @{
                Name = $global:AzureAD.$tenantKey.Defaults.CosmosDBAccount.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            SqlVM = @{
                Name = $global:AzureAD.$tenantKey.Defaults.SqlVM.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            KeyVault = @{
                Name = $global:AzureAD.$tenantKey.Defaults.KeyVault.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project)
                Scope = $null
                Object = $null
            }
            DataFactory = @{
                Name = $global:AzureAD.$tenantKey.Defaults.DataFactory.Name.Template.replace("<0>",$Prefix).replace("<1>",$_project)
                Scope = $null
                Object = $null
            }
        }
    }
    $AzureProject = $global:AzureProjects.Tenant.$tenantKey.Group.$_group.Project.$_project

    Get-AiProjectResourceScopes -AzureProject $AzureProject
    Get-AiProjectDeployedResources -AzureProject $AzureProject

    $AzureProject.Initialized = $true

    return $AzureProject

}
Set-Alias -Name azProjInit -Value Initialize-AzProject -Scope Global

function Get-AiProjectResourceScopes {

    param(
        [Parameter(Mandatory=$false)][object]$AzureProject
    )
    
    $scopeBase = "/subscriptions/$($global:AzureAD.$($AzureProject.Tenant).Subscription.Id)/resourceGroups/$($AzureProject.ResourceType.ResourceGroup.Name)/providers"

    $AzureProject.ResourceType.BatchAccount.Scope = "$scopeBase/Microsoft.Batch/BatchAccounts/$($AzureProject.ResourceType.BatchAccount.Name)"
    $AzureProject.ResourceType.StorageAccount.Scope = "$scopeBase/Microsoft.Storage/storageAccounts/$($AzureProject.ResourceType.StorageAccount.Name)"
    $AzureProject.ResourceType.StorageContainer.Scope = "$scopeBase/Microsoft.Storage/storageAccounts/$($AzureProject.ResourceType.StorageAccount.Name)/blobServices/default/containers/$($AzureProject.ResourceType.StorageContainer.Name)"
    $AzureProject.ResourceType.Bastion.Scope = "$scopeBase/Microsoft.Network/bastionHosts/$($AzureProject.ResourceType.Bastion.Name)"
    $AzureProject.ResourceType.VM.Scope = "$scopeBase/Microsoft.Compute/virtualMachines/$($AzureProject.ResourceType.VM.Name)"
    $AzureProject.ResourceType.MLWorkspace.Scope = "$scopeBase/Microsoft.MachineLearningServices/workspaces/$($AzureProject.ResourceType.MLWorkspace.Name)"
    $AzureProject.ResourceType.CosmosDBAccount.Scope = "$scopeBase/Microsoft.DocumentDB/databaseAccounts/$($AzureProject.ResourceType.CosmosDBAccount.Name)" 
    $AzureProject.ResourceType.SqlVM.Scope = "$scopeBase/Microsoft.SqlVirtualMachine/SqlVirtualMachines/$($AzureProject.ResourceType.SqlVM.Name)"
    $AzureProject.ResourceType.KeyVault.Scope = "$scopeBase/Microsoft.KeyVault/vaults/$($AzureProject.ResourceType.KeyVault.Name)"
    $AzureProject.ResourceType.DataFactory.Scope = "$scopeBase/Microsoft.DataFactory/factories/$($AzureProject.ResourceType.DataFactory.Name)"

    return

}

function Get-AiProjectResourceFromScope {

    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$true,Position=0)][string]$Scope
    )

    $scopeBase = "/subscriptions/$($global:AzureAD.$($AzureProject.Tenant).Subscription.Id)/resourceGroups/$($AzureProject.ResourceType.ResourceGroup.Name)/providers"
    $resourceName = $Scope.Split("/")[-1]
    $provider = $Scope.Replace($scopeBase,"")
    $provider = $provider.Substring(1,$provider.LastIndexOf("/")-1)

    $resourceType = switch ($provider) {
        "Microsoft.Storage/storageAccounts" {"StorageAccount"}
        "Microsoft.Storage/storageAccounts/$($AzureProject.ResourceType.StorageAccount.Name)/blobServices/default/containers" {"StorageContainer"}
        "Microsoft.Network/bastionHosts" {"Bastion"}
        "Microsoft.Compute/virtualMachines" {"VM"}
        "Microsoft.MachineLearningServices/workspaces" {"MLWorkspace"}
        "Microsoft.DocumentDB/databaseAccounts" {"CosmosDBAccount "}
        "Microsoft.SqlVirtualMachine/SqlVirtualMachines" {"SqlVM"}
        "Microsoft.KeyVault/vaults" {"KeyVault"}
        "Microsoft.DataFactory/factories" {"DataFactory"}
    }

    return [PSCustomObject]@{
        resourceType = $resourceType
        resourceName = $resourceName
        resourceID = $resourceType + "-" + $resourceName
    }

}

function Get-AiProjectResourceScope {

    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$true,Position=0)][string]$ResourceType,
        [Parameter(Mandatory=$true,Position=1)][string]$ResourceName
    )

    $scope = $AzureProject.ResourceType.$ResourceType.Scope
    $scope = ![string]::IsNullOrEmpty($ResourceName) ? ($scope -replace "$($AzureProject.ResourceType.$ResourceType.Name)`$", $ResourceName) : $scope

    return $scope

}

function Get-AiProjectDeployedResources {

    param(
        [Parameter(Mandatory=$true)][object]$AzureProject
    )

    $resourceGroups = Get-AzResourceGroup
    if ($resourceGroups | Where-Object {$_.ResourceGroupName -eq $AzureProject.ResourceType.ResourceGroup.Name}) {
        $AzureProject.ResourceType.ResourceGroup.Object = Get-AzResourceGroup -Name $AzureProject.ResourceType.ResourceGroup.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.BatchAccount.Object = Get-AzBatchAccount -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.BatchAccount.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.StorageAccount.Object = Get-AzStorageAccount -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.StorageAccount.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.StorageAccount.Context = New-AzStorageContext -StorageAccountName $AzureProject.ResourceType.StorageAccount.Name -UseConnectedAccount -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.StorageContainer.Object = Get-AzStorageContainer -Context $AzureProject.ResourceType.StorageAccount.Context -Name $AzureProject.ResourceType.StorageContainer.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.Bastion.Object = Get-AzBastion -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.Bastion.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.VM.Object = Get-AzVm -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.VM.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.CosmosDBAccount.Object = Get-AzCosmosDBAccount -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.CosmosDBAccount.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.SqlVM.Object = Get-AzSqlVM -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.SqlVM.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.KeyVault.Object = Get-AzKeyVault -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.KeyVault.Name -ErrorAction SilentlyContinue
        $AzureProject.ResourceType.DataFactory.Object = Get-AzDataFactory -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.DataFactory.Name -ErrorAction SilentlyContinue

        $mlWorkspaces = get-azresource -resourcegroupname $AzureProject.ResourceType.ResourceGroup.Name | Where-Object {$_.ResourceType -eq "Microsoft.MachineLearningServices/workspaces"}
        if ($mlWorkspaces) {
            az login --output None # required until https://github.com/Azure/azure-cli/issues/20150 is resolved
            $AzureProject.ResourceType.MLWorkspace.Object = Get-AzMlWorkspace -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -WorkspaceName $AzureProject.ResourceType.MLWorkspace.Name -ErrorAction SilentlyContinue
        }
    }

    return

}

function global:New-AiResource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$true)][Alias("ResourceGroup")][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceName
    )

    $applicationInsights = Get-AzApplicationInsights -ResourceGroupName $ResourceGroupName
    $containerRegistry = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName
    $keyVault = $AzureProject.ResourceType.KeyVault
    $location = $AzureProject.AzureAD.Location
    $storageAccount = $AzureProject.ResourceType.StorageAccount

    $object = $null
    switch ($ResourceType) {
        "MLWorkspace" {
            $object = Get-AzResource -ResourceGroupName $ResourceGroupName -Name $ResourceName
            if ($object) {
                throw "$ResourceName already exists in $ResourceGroupName"
            }
        }
        "StorageContainer" {
            $object = Get-AzStorageContainer -Context $storageAccount.Context -Name $ResourceName
            if ($object) {
                throw "$ResourceName already exists in $ResourceGroupName"
            }
        }
    }

    $object = $null
    switch ($ResourceType) {
        "MLWorkspace" {
            $object = New-AzMlWorkspace -ResourceGroupName $ResourceGroupName -WorkspaceName $ResourceName -Location $Location -StorageAccount $storageAccount.Scope -KeyVault $keyVault.Scope -ApplicationInsights $applicationInsights.Id -ContainerRegistry $containerRegistry.Id
        }
        "StorageContainer" {
            $object = New-AzStorageContainer+ -Tenant $AzureProject.Tenant -Context $storageAccount.Context -ContainerName $ResourceName
        }
    }

    return $object

}

function global:New-AzProject {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$false)][Alias("StorageContainer")][string]$StorageContainerName
    )
    
    $message = "<  Resource creation <.>60> PENDING" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    $message = "<    ResourceGroup/:$($AzureProject.ResourceType.ResourceGroup.Name) <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
    $resourceGroup = Get-AzResourceGroup -Name $AzureProject.ResourceType.ResourceGroup.Name 
    if ($resourceGroup) {
        $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
    }
    else {
        $AzureProject.ResourceType.ResourceGroup.Object = New-AzResourceGroup+ -Tenant $AzureProject.Tenant -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name 
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

    $message = "<    StorageAccount/:$($AzureProject.ResourceType.StorageAccount.Name) <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name -Name $AzureProject.ResourceType.StorageAccount.Name -ErrorAction SilentlyContinue
    if ($storageAccount) {
        $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
    }
    else {
        $AzureProject.ResourceType.StorageAccount.Object = New-AzStorageAccount+ -Tenant $AzureProject.Tenant -ResourceGroupName $AzureProject.ResourceType.ResourceGroup.Name  -StorageAccountName $AzureProject.ResourceType.StorageAccount.Name
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

    $StorageContainerName = ![string]::IsNullOrEmpty($StorageContainerName) ? $StorageContainerName : $AzureProject.ResourceType.StorageContainer.Name
    if ($StorageContainerName -ne $AzureProject.ResourceType.StorageContainer.Name) {
        $AzureProject.ResourceType.StorageContainer.Name = $StorageContainerName
    }
    $message = "<    StorageContainer/:$StorageContainerName <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
    $storageAccountContext = New-AzStorageContext -StorageAccountName $AzureProject.ResourceType.StorageAccount.Name -UseConnectedAccount -ErrorAction SilentlyContinue
    $storageContainer = Get-AzStorageContainer -Context $storageAccountContext -Name $StorageContainerName -ErrorAction SilentlyContinue
    if ($storageContainer) {
        $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
    }
    else {
        $AzureProject.ResourceType.StorageAccount.Context = New-AzStorageContext -StorageAccountName $AzureProject.ResourceType.StorageAccount.Name -UseConnectedAccount
        $AzureProject.ResourceType.StorageContainer.Object = New-AzStorageContainer+ -Tenant $AzureProject.Tenant -Context $AzureProject.ResourceType.StorageAccount.Context -ContainerName $StorageContainerName
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }
    
    Write-Host+
    $message = "<  Resource creation <.>60> SUCCESS" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen

    return
    
}
Set-Alias -Name azProjNew -Value New-AzProject -Scope Global

function global:Convert-AiProjectImportFile {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$AzureProject
    )

    $message = "<  Import File Conversion <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $originalImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-roleAssignments.csv"
    if (!(Test-Path $originalImport)) {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator "$($emptyString.PadLeft(8,"`b")) FAILURE$($emptyString.PadLeft(8," "))" -ForegroundColor Red
        Write-Host+ -NoTrace -NoSeparator "    ERROR: File `"$originalImport`" not found." -ForegroundColor Red
        Write-Host+
        return
    }

    $UserImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-users-import.csv"
    # $GroupImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-groups-import.csv"
    $ResourceImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-resources-import.csv"
    $RoleAssignmentImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-roleAssignments-import.csv"

    $originalData = Import-Csv "$($AzureProject.Location.Data)\$($AzureProject.Name)-roleAssignments.csv"
    $originalData | Select-Object -Property signInName,fullName | Sort-Object -Property signInName -Unique | Export-Csv $UserImport -UseQuotes Always -NoTypeInformation
    $originalData | Select-Object -Property resourceType,resourceName,@{name="resourceID";expression={$_.resourceType + ($_.resourceName ? "-" + $_.resourceName : $null)}} | Sort-Object -Property resourceType, resourceName -Unique | Export-Csv $ResourceImport -UseQuotes Always  -NoTypeInformation
    $originalData | Select-Object -Property @{name="resourceID";expression={$_.resourceType + ($_.resourceName ? "-" + $_.resourceName : $null)}}, role, @{name="assigneeType";expression={"user"}}, @{name="assignee";expression={$_.signInName}} | Export-Csv $RoleAssignmentImport -UseQuotes Always  -NoTypeInformation

    $originalImportArchive = "$($AzureProject.Location.Data)\archive"
    if (!(Test-Path $originalImportArchive)) {
        New-Item -Path $AzureProject.Location.Data -Name "archive" -ItemType "Directory" | Out-Null
    }
    Move-Item -Path $originalImport -Destination $originalImportArchive

    Write-Host+ -NoTrace -NoTimestamp -NoSeparator "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))" -ForegroundColor DarkGreen
    Write-Host+

}

function global:Grant-AiProjectRole {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UserId","Email","Mail")][string]$User,
        [switch]$ReferencedResourcesOnly,
        [switch]$RemoveUnauthorizedRoleAssignments
    )

    [console]::CursorVisible = $false

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
    Write-Host+

    if ($User -and $RemoveUnauthorizedRoleAssignments) {
        Write-Host+ -NoTrace -NoSeparator -NoTimestamp "  ERROR:  The `$RemoveUnauthorizedRoleAssignments switch cannot be used with the `$User parameter." -ForegroundColor Red
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
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Role assignments not specified in `"$($AzureProject.Name)-roleAssignments-import.csv`" will be removed." -ForegroundColor Gray
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  EXCEPTIONS: OWNER role assignments and role assignments inherited from the subscription will NOT be removed." -ForegroundColor Gray
        Write-Host+
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine "  Continue (Y/N)? " -ForegroundColor Gray
        $response = Read-Host
        if ($response.ToUpper().Substring(0,1) -ne "Y") {
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

    $resourceGroupName = $AzureProject.ResourceType.ResourceGroup.Name

    if ($User) {

        $isUserId = $User -match $global:RegexPattern.Guid
        $isGuestUserPrincipalName = $User -match $global:RegexPattern.AzureAD.UserPrincipalName -and $User -like "*#EXT#*"
        $isEmail = $User -match $global:RegexPattern.Mail
        $isMemberUserPrincipalName = $User -match $global:RegexPattern.AzureAD.UserPrincipalName

        $isValidUser = $isUserId -or $isEmail -or $isMemberUserPrincipalName -or $isGuestUserPrincipalName
        if (!$isValidUser) {
            throw "'$User' is not a valid object id, userPrincipalName or email address."
        }
        
    }

    #region DATAFILES

        $message = "<  Data validation <.>60> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+

        $UserImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-users-import.csv"
        $GroupImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-groups-import.csv"
        $ResourceImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-resources-import.csv"
        $RoleAssignmentImport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-roleAssignments-import.csv"
        $RoleAssignmentExport = "$($AzureProject.Location.Data)\$($AzureProject.Name)-roleAssignments-export.csv"

        if (!(Test-Path $UserImport)) {
            Write-Host+ -NoTrace -Prefix "ERROR" "$UserImport not found." -ForegroundColor DarkRed
            return
        }

        if (!(Test-Path $GroupImport)) {
            $groupsInUse = Select-String -Path $RoleAssignmentImport -Pattern "group" -Quiet
            if ($groupsInUse) {
                Write-Host+ -NoTrace -Prefix ($groupsInUse ? "ERROR" : "WARNING") "$GroupImport not found." -ForegroundColor ($groupsInUse ? "DarkRed" : "DarkYellow")
                Write-Host+
                return
            }
        }

        if (!(Test-Path $ResourceImport)) {
            Write-Host+ -NoTrace -Prefix "ERROR" "$ResourceImport not found." -ForegroundColor DarkRed
            return
        }

        if (!(Test-Path $RoleAssignmentImport)) {
            Write-Host+ -NoTrace -Prefix "ERROR" "$RoleAssignmentImport not found." -ForegroundColor DarkRed
            return
        }

        Write-Host+ -NoTrace -NoSeparator "    $UserImport" -ForegroundColor DarkGray
        $users = @()
        $users += Import-Csv $UserImport
        if ($User) {
            # if $User has been specified, filter $users to the specified $User only
            $users = $users | Where-Object {$_.signInName -eq $User}
            if ($users.Count -eq 0) {
                Write-Host+ -NoTrace -NoSeparator  "      ERROR: User $User not referenced in project `"$($($AzureProject.Name))`"'s import files." -ForegroundColor Red
                Write-Host+
                return
            }
            $azureADUser = Get-AzureADUser -Tenant $AzureProject.Tenant -User $User
            if (!$azureADUser) {
                Write-Host+ -NoTrace -NoSeparator  "      ERROR: $User not found in Azure tenant `"$($AzureProject.Tenant)`"" -ForegroundColor Red
                Write-Host+
                return
            }
            $User = $azureADUser.mail
        }

        Write-Host+ -NoTrace -NoSeparator "    $GroupImport" -ForegroundColor DarkGray
        $groups = @()
        if (Test-Path $GroupImport) {
            $groups += Import-Csv $GroupImport
            if ($User) {
                # if $User has been specified, filter $groups to only those containing $User
                $groups = $groups | Where-Object {$_.user -eq $User}
            }
        }

        Write-Host+ -NoTrace -NoSeparator "    $ResourceImport" -ForegroundColor DarkGray
        $resources = @(); $resources += [PSCustomObject]@{resourceType = "ResourceGroup"; resourceName = $resourceGroupName; resourceID = "ResourceGroup-$resourceGroupName"; resourceScope = $AzureProject.ResourceType.ResourceGroup.Scope}
        $resources += Import-Csv -Path $ResourceImport | Select-Object -Property resourceType, resourceName, resourceID, @{Name="resourceScope"; Expression={$null}} | Sort-Object -Property resourceType, resourceName -Unique   

        Write-Host+ -NoTrace -NoSeparator "    $RoleAssignmentImport" -ForegroundColor DarkGray
        $roleAssignmentsFromFile = Import-Csv -Path $RoleAssignmentImport
        if ($User) {
            # if $User has been specified, filter $roleAssignmentsFromFile to those relevent to $User
            $roleAssignmentsFromFile = $roleAssignmentsFromFile | Where-Object {$_.assigneeType -eq "user" -and $_.assignee -eq $User -or ($_.assigneeType -eq "group" -and $_.assignee -in $groups.group)}
        }

        # if the $ReferencedResourcesOnly switch has been specified, then filter $resources to only those relevant to $users
        # NOTE: this is faster, but it prevents the function from finding/removing roleAssignments from other resources
        if ($ReferencedResourcesOnly) {
          $resources = $resources | Where-Object {$_.resourceID -in $roleAssignmentsFromFile.resourceID}
        }

        $missingUsers = @()
        # if (!$User) {
            $missingUsers += $groups | Where-Object {$_.user -notin $users.signInName} | Select-Object -Property @{Name="signInName"; Expression={$_.user}}, @{Name="source"; Expression={"Groups"}}
            $missingUsers += $roleAssignmentsFromFile | Where-Object {$_.assigneeType -eq "user" -and $_.assignee -notin $users.signInName} | Select-Object -Property @{Name="signInName"; Expression={$_.assignee}}, @{Name="source"; Expression={"Role Assignments"}}
        # }

        if ($missingUsers.Count -gt 0) {
            
            Write-Host+ 

            $message = "    SignInName : Status   : Source"
            Write-Host+ -NoTrace $message.Split(":")[0],(Format-Leader -Length 40 -Adjust (-($message.Split(":")[0]).Length) -Character " "),$message.Split(":")[1],$message.Split(":")[2] -ForegroundColor DarkGray
            $message = "    ---------- : ------   : ------"
            Write-Host+ -NoTrace $message.Split(":")[0],(Format-Leader -Length 40 -Adjust (-($message.Split(":")[0]).Length) -Character " "),$message.Split(":")[1],$message.Split(":")[2] -ForegroundColor DarkGray

            foreach ($missingUser in $missingUsers) {
                $message = "    $($missingUser.signInName) | MISSING  | $($missingUser.source)"
                Write-Host+ -NoTrace  $message.Split("|")[0],(Format-Leader -Length 40 -Adjust (-($message.Split("|")[0]).Length) -Character " "),$message.Split("|")[1],$message.Split("|")[2] -ForegroundColor DarkGray,DarkGray,DarkRed,DarkGray
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
            $resourceName = ![string]::IsNullOrEmpty($resource.resourceName) ? $resource.resourceName : $AzureProject.ResourceType.$resourceType.Name
            $resourcePath = $resourceGroupName -eq $resourceName ? $resourceGroupName : "$resourceGroupName/$resourceName"

            $scope = $null
            if ([string]::IsNullOrEmpty($resource.resourceScope)) {
                $scope = $AzureProject.ResourceType.$ResourceType.Scope
                $scope = $scope.Substring(0,$scope.LastIndexOf("/")+1) + $ResourceName
            }
            else {
                $scope = $resource.resourceScope
            }

            $object = $null
            $displayScope = $true
            switch ($resourceType) {
                default {
                    $getAzExpression = "Get-Az$resourceType -ResourceGroupName $resourceGroupName"
                    $getAzExpression += $resourceType -ne "ResourceGroup" ? " -Name $resourceName" : $null
                    $object = Invoke-Expression $getAzExpression
                    if (!$object) {
                        throw "The $resourceType $resourcePath' does not exist."
                    }
                    # $scope = $object.Id ?? $object.ResourceId
                }
                "MLWorkspace" {
                    $object = Get-AzResource -ResourceGroupName $ResourceGroupName -Name $ResourceName
                    if (!$object) {
                        $message = "    $($scope.split("/resourceGroups/")[1].replace("providers/Microsoft.",$null)) : CREATING"
                        Write-Host+ -NoTrace -NoNewLine -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor DarkGray,Gray
                        $object = New-AiResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator "$($emptyString.PadLeft(8,"`b"))NEW$($emptyString.PadLeft(8," "))"
                        $displayScope = $false
                    }
                }
                "StorageContainer" {
                    $object = Get-AzStorageContainer -Context $AzureProject.ResourceType.StorageAccount.Context -Name $resourceName
                    if (!$object) {
                        $message = "    $($scope.split("/resourceGroups/")[1].replace("providers/Microsoft.",$null)) : CREATING"
                        Write-Host+ -NoTrace -NoSeparator -NoNewLine  $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor DarkGray,Gray
                        $object = New-AiResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator "$($emptyString.PadLeft(8,"`b"))NEW$($emptyString.PadLeft(8," "))"
                        $displayScope = $false
                    }
                }
            }

            $resource.resourceName = [string]::IsNullOrEmpty($resource.resourceName) ? $scope.Substring($scope.LastIndexOf("/")+1, $scope.Length-($scope.LastIndexOf("/")+1)) : $resource.resourceName
            $resource.resourceScope = $scope

            switch ($resourceType) {
                "VM" {
                    $vm = $object
                    foreach ($nic in $vm.networkProfile.NetworkInterfaces) {

                        $nicType = "NetworkInterface"
                        $nicName = $nic.Id.split("/")[-1]
                        $nicScope = $nic.Id
                        $nicObject = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $nicName

                        Write-Host+ -NoTrace -NoSeparator "    $($nic.Id.split("/resourceGroups/")[1])" -ForegroundColor DarkGray

                        if ($AzureProject.ResourceType.NetworkInterface.Scope -notcontains $nicScope) {
                            $AzureProject.ResourceType.NetworkInterface += @{
                                Name = $nicName
                                Scope = $nicScope 
                                Object = $nicObject
                            }
                        }

                        $newResource = [PSCustomObject]@{
                            resourceID = $nicType + "-" + $nicName
                            resourceType = $nicType
                            resourceName = $nicName
                            resourceScope = $nicScope
                        }
                        $resources += $newResource

                        foreach ($resourceRoleAssignment in ($roleAssignmentsFromFile | Where-Object {$_.resourceID -eq $resource.resourceID} | Sort-Object -Property assigneeType,assignee -Unique)) {
                            $roleAssignmentsFromFile += [PSCustomObject]@{
                                resourceID = $newResource.resourceID
                                role = "Reader"
                                assigneeType = $resourceRoleAssignment.assigneeType
                                assignee = $resourceRoleAssignment.assignee
                            }
                        }
                    }
                }
            }

            if ($displayScope) {
                $message = "    $($scope.split("/resourceGroups/")[1].replace("providers/Microsoft.",$null))"
                Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            }

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

        # Initialize-AzureAD
        # Connect-AzureAD -Tenant $AzureProject.Tenant

        $authorizedProjectUsers = @()
        foreach ($signInName in $signInNames) {
            $azureADUser = Get-AzureADUser -Tenant $AzureProject.Tenant -User $signInName
            if ($azureADUser -and $azureADUser.accountEnabled) {
                $authorizedProjectUsers += $azureADUser
            }
        }
        $authorizedProjectUsers | Add-Member -NotePropertyName authorized -NotePropertyValue $true

        #region UNAUTHORIZED

            # identify unauthorized project users and role assignments
            # if $User has been specified, skip this step
            $unauthorizedProjectRoleAssignments = @()
            $unauthorizedProjectUsers = @()
            if (!$User) {
                $projectRoleAssignments = Get-AzRoleAssignment -ResourceGroupName $ResourceGroupName | 
                    Where-Object {$_.ObjectType -eq "User" -and $_.RoleDefinitionName -ne "Owner" -and $_.Scope -like "*$ResourceGroupName*" -and $_.SignInName -notlike "*admin_path.org*"}
                $unauthorizedProjectRoleAssignments = ($projectRoleAssignments | Where-Object {$authorizedProjectUsers.userPrincipalName -notcontains $_.SignInName})
                foreach ($invalidProjectRoleAssignment in $unauthorizedProjectRoleAssignments) {
                    $unauthorizedAzureADUser = Get-AzureADUser -Tenant $AzureProject.Tenant -User $invalidProjectRoleAssignment.SignInName
                    $unauthorizedAzureADUser | Add-Member -NotePropertyName authorized -NotePropertyValue $false
                    $unauthorizedAzureADUser | Add-Member -NotePropertyName reason -NotePropertyValue (!$_.accountEnabled ? "ACCOUNT DISABLED" : "UNAUTHORIZED")
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
                    $invitation = Send-AzureADInvitation -Tenant $AzureProject.Tenant -Email $signInName -DisplayName $fullName -Message $AzureProject.AzureAD.Invitation.Message
                    $invitation | Out-Null
                    Write-Host+ -NoTrace -NoTimeStamp "Invitation sent" -ForegroundColor DarkGreen
                }
                else {
                    $externalUserState = $guest.externalUserState -eq "PendingAcceptance" ? "Pending " : $guest.externalUserState
                    $externalUserStateChangeDateTime = $guest.externalUserStateChangeDateTime
                    $externalUserStateChangeDateString = $externalUserStateChangeDateTime.ToString("u").Substring(0,10)
                    $externalUserStateColor = $externalUserState -eq "Pending " ? "DarkYellow" : "DarkGray"
                    $message = "$externalUserState $externalUserStateChangeDateString"
                    Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor $externalUserStateColor

                    if (!$guest.authorized) {
                        Write-Host+ -NoTrace -NoTimeStamp -NoNewLine " *** $($guest.reason) ***" -ForegroundColor DarkRed
                    }

                    Write-Host+
                }

            }
        }

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
                    foreach ($resource in ($resources | Where-Object {$_.resourceID -eq $roleAssignment.resourceID})) {
                        $roleAssignments += [PsCustomObject]@{
                            resourceID = $roleAssignment.resourceID
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
                foreach ($resource in ($resources | Where-Object {$_.resourceID -eq $roleAssignment.resourceID})) {
                    $roleAssignments += [PsCustomObject]@{
                        resourceID = $roleAssignment.resourceID
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
            $resourceFromScope = Get-AiProjectResourceFromScope -Tenant $AzureProject.Tenant -Scope $unauthorizedProjectRoleAssignment.Scope
            $roleAssignments += [PsCustomObject]@{
                resourceID = $resourceFromScope.resourceType + "-" + $resourceFromScope.resourceName
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

            $assignee = Get-AzureADUser -Tenant $AzureProject.Tenant -User $signInName
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

            $identity = $assignee.identities | Where-Object {$_.issuer -eq $global:AzureAD.$($AzureProject.Tenant).Tenant.Name}
            $signInType = $identity.signInType
            $signIn = $signInType -eq "userPrincipalName" ? $assignee.userPrincipalName : $signInName
            
            $resourceTypes = @()
            $resourceTypes += ($roleAssignments | Where-Object {$_.signInName -eq $signInName} | Sort-Object -Property resourceTypeSortOrder,resourceType -Unique ).resourceType 
            if (!$ReferencedResourcesOnly) {
                $resourceTypes += $AzureProject.ResourceType.Keys | Where-Object {$_ -notin $resourceTypes -and $_ -ne "ResourceGroup" -and $AzureProject.ResourceType.$_.Object}
            }

            $roleAssignmentCount = 0
            foreach ($resourceType in $resourceTypes) {

                # if the $UserResourcesOnly switch has been specified, then filter $resources to only those relevant to the current assignee
                # NOTE: this is faster, but it prevents the function from finding/removing roleAssignments from other resources
                $resourcesToCheck = $resources
                if ($ReferencedResourcesOnly) {
                    $resourcesToCheck = $resources | Where-Object {$_.resourceID -in (($roleAssignments | Where-Object {$_.signInName -eq $signInName}).resourceID)}
                }

                foreach ($resource in $resourcesToCheck | Where-Object {$_.resourceType -eq $resourceType}) {

                    $unauthorizedRoleAssignment = $false

                    $resourceName = ![string]::IsNullOrEmpty($resource.resourceName) ? $resource.resourceName : ($AzureProject.ResourceType.($resourceType).Scope).split("/")[-1]
                    $resourceScope = Get-AiProjectResourceScope -AzureProject $AzureProject -ResourceType $resourceType -ResourceName $resourceName

                    $message = "<    $($resourceType)/$($resourceName)"
                    $message = ($message.Length -gt 55 ? $message.Substring(0,55) + "`u{22EF}" : $message) + " <.>60> "    

                    $currentRoleAssignments = Get-AzRoleAssignment -Scope $resourceScope -SignInName $signIn  | Sort-Object -Property Scope
                    if ($currentRoleAssignments) {
                        # Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Format-Leader -Length 60 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray 
                        foreach ($currentRoleAssignment in $currentRoleAssignments) {
                            if ($currentRoleAssignment.Scope -ne $resourceScope -and $resourceScope -like "$($currentRoleAssignment.Scope)*") {
                                $message += "^"
                            }
                            $message += $currentRoleAssignment.RoleDefinitionName
                            if ($currentRoleAssignments.Count -gt 1 -and $foreach.Current -ne $currentRoleAssignments[-1]) {
                                $message += ", "
                            }
                            # Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGray
                        }
                        Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray 
                    }
                    $rolesWrittenCount = $currentRoleAssignments.Count

                    $requiredRoleAssignments = $roleAssignments | Where-Object {$_.signInName -eq $signInName -and $_.resourceType -eq $resourceType}
                    if (![string]::IsNullOrEmpty($resourceName)) {
                        $requiredRoleAssignments =  $requiredRoleAssignments | Where-Object {$_.resourceName -eq $resourceName}
                    }
                    if ($requiredRoleAssignments) {
                        if (!$currentRoleAssignments) {
                            Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Format-Leader -Length 60 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray 
                        }
                        foreach ($roleAssignment in $requiredRoleAssignments) {
                            $currentRoleAssignment = Get-AzRoleAssignment -Scope $resourceScope -SignInName $signIn -RoleDefinitionName $roleAssignment.role
                            if (!$currentRoleAssignment -and ($currentRoleAssignment.RoleDefinitionName -ne $roleAssignment.role)) {
                                New-AzRoleAssignment+ -Scope $resourceScope -RoleDefinitionName $roleAssignment.role -SignInNames $signIn -ErrorAction SilentlyContinue | Out-Null
                                $message = "$($rolesWrittenCount -gt 0 ? ", " : $null)"
                                Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGray
                                $message = "+$($roleAssignment.role)"
                                Write-Host+ -NoTrace -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGreen 
                                $rolesWrittenCount++   
                            }
                            if ($unauthorizedProjectRoleAssignments | Where-Object {$_.SignInName -eq $currentRoleAssignment.SignInName -and $_.RoleDefinitionId -eq $currentRoleAssignment.RoleDefinitionId}) {
                                $unauthorizedRoleAssignment = $true
                            }
                        }
                    }

                    $currentRoleAssignmentsThisResourceScope = $currentRoleAssignments | Where-Object {$_.Scope -eq $AzureProject.ResourceType.($resourceType).Scope}
                    if ($currentRoleAssignmentsThisResourceScope) {
                        foreach ($currentRoleAssignment in $currentRoleAssignmentsThisResourceScope) {
                            if ($currentRoleAssignment.RoleDefinitionName -notin $requiredRoleAssignments.role -or ($RemoveUnauthorizedRoleAssignments -and $unauthorizedRoleAssignment)) {
                                Remove-AzRoleAssignment -Scope $resourceScope -RoleDefinitionName $currentRoleAssignment.RoleDefinitionName -SignInName $signIn | Out-Null
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

    [console]::CursorVisible = $true

    return

}
Set-Alias -Name azProjGrant -Value Grant-AiProjectRole -Scope Global

function global:Deploy-AzProject {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$true)][ValidateSet("DSnA","StorageAccount")][string]$DeploymentType,   
        [Parameter(Mandatory=$false)][Alias("StorageContainer")][string]$StorageContainerName,
        [Parameter(Mandatory=$false)][string]$VmSize,
        [Parameter(Mandatory=$false)][ValidateSet("canonical","microsoft-dsvm")][string]$VmImagePublisher,
        [Parameter(Mandatory=$false)][ValidateSet("dsvm-win-2019","linux-data-science-vm-ubuntu","ubuntuserver")][string]$VmImageOffer
    )

    switch ($DeploymentType) {
        "DSnA" {    
            Deploy-DSnA -Tenant $AzureProject.Tenant -Project $($AzureProject.Name) -VmSize $VmSize -VmImagePublisher $VmImagePublisher -VmImageOffer $VmImageOffer
        }
        "StorageAccount" {
            New-AzProject -Tenant $AzureProject.Tenant -Project $($AzureProject.Name) -StorageContainerName $StorageContainerName
        }
    }
    
    Get-AiProjectResourceScopes -AzureProject $AzureProject
    Get-AiProjectDeployedResources -AzureProject $AzureProject

    Grant-AiProjectRole -AzureProject $AzureProject

    return

}
Set-Alias -Name azProjDeploy -Value Deploy-AzProject -Scope Global

function global:Deploy-DSnA {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$AzureProject,
        [Parameter(Mandatory=$false)][string]$VmSize,
        [Parameter(Mandatory=$true)][ValidateSet("canonical","microsoft-dsvm")][string]$VmImagePublisher,
        [Parameter(Mandatory=$true)][ValidateSet("dsvm-win-2019","linux-data-science-vm-ubuntu","ubuntuserver")][string]$VmImageOffer
    )

    $VmSize = ![string]::IsNullOrEmpty($VmSize) ? $VmSize : $global:AzureAD.$($AzureProject.Tenant).Defaults.VM.Size 
    $VmOsType = ![string]::IsNullOrEmpty($VmOsType) ? $VmOsType : $global:AzureAD.$($AzureProject.Tenant).Defaults.VM.OsType

    if (Test-Credentials $AzureProject.ResourceType.VM.Admin -NoValidate) {
        $adminCreds = Get-Credentials $AzureProject.ResourceType.VM.Admin -Location $AzureProject.Location.Credentials
    }
    else {
        $adminCreds = Request-Credentials -UserName $AzureProject.VM.Admin -Password (New-RandomPassword -ExcludeSpecialCharacters)
        Set-Credentials $AzureProject.VM.Admin -Credentials $adminCreds
    }

    $params = @{
        Subscription = $global:AzureAD.$($AzureProject.Tenant).Subscription.Id
        Tenant = $global:AzureAD.$($AzureProject.Tenant).Tenant.Id
        Prefix = $global:AzureAD.$($AzureProject.Tenant).Prefix
        Random = $AzureProject.Name
        ResourceGroup = $AzureProject.ResourceType.ResourceGroup.Name
        BlobContainerName = $AzureProject.ResourceType.StorageContainer.Name
        VMSize = $VmSize
        location = $AzureProject.AzureAD.Location
    }

    Set-Location "$($Location.Data)\azure\deployment\vmImages\$VmImagePublisher\$VmImageOffer\config"

    if (Select-String -path "deploy.ps1" -Pattern "AdminPassword" -Quiet) {
        $params += @{AdminPassword = $adminCreds.Password}
    }
    if (Select-String -path "deploy.ps1" -Pattern "SshPrivateKeyPath" -Quiet) {
        $params += @{
            SshPrivateKeyPath = "~/.ssh/$($AzureProject.Name)_rsa.private"
            SshPublicKeyPath = "~/.ssh/$($AzureProject.Name)_rsa.public"
        }
    }

    .\deploy.ps1 @params
    
    Set-Location $global:Location.Root

    return

}