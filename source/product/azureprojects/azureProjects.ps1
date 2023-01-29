
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

function global:Initialize-AzProject {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$true)][Alias("Group")][string]$GroupName,
        [Parameter(Mandatory=$false)][Alias("StorageAccount")][string]$StorageAccountName,
        [Parameter(Mandatory=$false)][Alias("StorageContainer")][string]$StorageContainerName,
        [Parameter(Mandatory=$false)][string]$Prefix,
        [switch]$Reinitialize
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    if ([string]::IsNullOrEmpty($global:Azure.$tenantKey.MsGraph.AccessToken)) {
        Connect-AzureAD -Tenant $tenantKey
    }

    $projectNameLowerCase = $ProjectName.ToLower()
    $projectNameUpperCase = $ProjectName.ToUpper()
    $groupNameLowerCase = $GroupName.ToLower()

    # add new group to Azure
    if (!$global:Azure.Group.$groupNameLowerCase) {
        $global:Azure.Group += @{
            $groupNameLowerCase = @{
                Name = $groupNameLowerCase
                DisplayName = $GroupName
                Location = @{
                    Data = "$($global:Azure.Location.Data)\$groupNameLowerCase"
                }
                Project = @{}
            }
        }
    }

    # create group directory
    if (!(Test-Path -Path $global:Azure.Group.$groupNameLowerCase.Location.Data)) {
        New-Item -Path $global:Azure.Location.Data -Name $groupNameLowerCase -ItemType "directory" | Out-Null
    }

    if ($global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase.Initialized) {
        Write-Host+ -NoTrace "WARN: Project `"$projectNameLowerCase`" has already been initialized." -ForegroundColor DarkYellow
        Write-Host+ -Iff $(!($Reinitialize.IsPresent)) -NoTrace "INFO: To reinitialize project `"$projectNameLowerCase`", add the -Reinitialize switch."
        Write-Host+ -Iff $($Reinitialize.IsPresent) -NoTrace "WARN: Reinitializing project `"$projectNameLowerCase`"." -ForegroundColor DarkYellow
    }

    # Connect-AzAccount+
    # if the project's ConnectedAccount contains an AzureProfile, save it for reuse
    # otherwise, connect with Connect-AzAccount+ which returns an AzureProfile
    if ($global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase.ConnectedAccount) {
        Write-Host+ -Iff $($Reinitialize.IsPresent) -NoTrace "INFO: Reusing ConnectedAccount from project `"$projectNameLowerCase`"`."
        $_connectedAccount = $global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase.ConnectedAccount
    }
    else {
        $_connectedAccount = Connect-AzAccount+ -Tenant $tenantKey
    }

    # reinitializing the project, so remove the project from $global:Azure
    if ($global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase) {
        $global:Azure.Group.$groupNameLowerCase.Project.Remove($projectNameLowerCase)
    }

    # clear the global scope variable AzureProject as it points to the last initialized project
    Remove-Variable AzureProject -Scope Global -ErrorAction SilentlyContinue 

    #add new project to Azure
    $global:Azure.Group.$groupNameLowerCase.Project += @{
        $projectNameLowerCase = @{
            Name = $projectNameLowerCase
            DisplayName = $ProjectName
            GroupName = $groupNameLowerCase
            Location = @{
                Data = "$($global:Azure.Group.$groupNameLowerCase.Location.Data)\$projectNameLowerCase"
                Credentials = "$($global:Azure.Group.$groupNameLowerCase.Location.Data)\$projectNameLowerCase"
            }
            Initialized = $false
        }
    }
    
    #create project directory 
    if (!(Test-Path -Path $global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase.Location.Data)) {
        New-Item -Path $global:Azure.Group.$groupNameLowerCase.Location.Data -Name $projectNameLowerCase -ItemType "directory" | Out-Null
    }

    # get/read/update $Prefix
    $prefixIni = "$($global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase.Location.Data)\$projectNameLowerCase-prefix.ini"
    if (!$Prefix) {
        if (Test-Path $prefixIni) {
            $Prefix = (Get-Content $prefixIni | Where-Object {$_ -like "prefix*"}).split(" : ")[1].Trim()
        }
        $Prefix = $Prefix ?? $global:Azure.$tenantKey.Prefix
    }
    if (!(Test-Path $prefixIni)) {
        New-Item -Path $prefixIni -ItemType File | Out-Null
    }
    Clear-Content $prefixIni
    Add-Content $prefixIni "prefix : $Prefix"

    $global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase += @{
        Prefix = $Prefix
        Invitation = @{
            Message = "You have been invited by $($global:Azure.$tenantKey.DisplayName) to collaborate on project $projectNameUpperCase."
        }
        ConnectedAccount = $_connectedAccount
        ResourceType = @{
            ResourceGroup = @{
                Name = $global:Azure.Templates.Resources.ResourceGroup.Name.Pattern.replace("<0>",$groupNameLowerCase).replace("<1>",$projectNameLowerCase)
                Scope = "/subscriptions/$($global:Azure.$tenantKey.Subscription.Id)/resourceGroups/" + $global:Azure.Templates.Resources.ResourceGroup.Name.Pattern.replace("<0>",$groupNameLowerCase).replace("<1>",$projectNameLowerCase)
                Object = $null
            }
            BatchAccount = @{
                Name =  $global:Azure.Templates.Resources.BatchAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase)
                Scope = $null
                Object = $null
                Context = $null
            }
            StorageAccount = @{
                Name =  ![string]::IsNullOrEmpty($StorageAccountName) ? $StorageAccountName : $global:Azure.Templates.Resources.StorageAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase)
                Scope = $null
                Object = $null
                Context = $null
            }
            StorageContainer = @{
                Name = ![string]::IsNullOrEmpty($StorageContainerName) ? $StorageContainerName : $projectNameLowerCase
                Scope = $null
                Object = $null
            }
            Bastion = @{
                Name = $global:Azure.Templates.Resources.Bastion.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase)
                Scope = $null
                Object = $null
            }
            VM = @{
                Name = $global:Azure.Templates.Resources.VM.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase).replace("<2>","01")
                Admin = $global:Azure.Templates.Resources.VM.Admin.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase)
                Scope = $null
                Object = $null
            }
            NetworkInterface = @()
            MLWorkspace = @{
                Name = $global:Azure.Templates.Resources.MLWorkspace.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            CosmosDBAccount = @{
                Name = $global:Azure.Templates.Resources.CosmosDBAccount.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            SqlVM = @{
                Name = $global:Azure.Templates.Resources.SqlVM.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase).replace("<2>","01")
                Scope = $null
                Object = $null
            }
            KeyVault = @{
                Name = $global:Azure.Templates.Resources.KeyVault.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase)
                Scope = $null
                Object = $null
            }
            DataFactory = @{
                Name = $global:Azure.Templates.Resources.DataFactory.Name.Pattern.replace("<0>",$Prefix).replace("<1>",$projectNameLowerCase)
                Scope = $null
                Object = $null
            }
        }
    }

    $global:AzureProject = $global:Azure.Group.$groupNameLowerCase.Project.$projectNameLowerCase

    Get-AzProjectResourceScopes -Tenant $tenantKey
    Get-AzProjectDeployedResources

    $global:AzureProject.Initialized = $true

    return

}
Set-Alias -Name azProjInit -Value Initialize-AzProject -Scope Global

function global:Get-AzProjectResourceScopes {

    param(
        [Parameter(Mandatory=$true)][string]$Tenant
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    $scopeBase = "/subscriptions/$($global:Azure.$tenantKey.Subscription.Id)/resourceGroups/$($global:AzureProject.ResourceType.ResourceGroup.Name)/providers"

    $global:AzureProject.ResourceType.BatchAccount.Scope = "$scopeBase/Microsoft.Batch/BatchAccounts/$($global:AzureProject.ResourceType.BatchAccount.Name)"
    $global:AzureProject.ResourceType.StorageAccount.Scope = "$scopeBase/Microsoft.Storage/storageAccounts/$($global:AzureProject.ResourceType.StorageAccount.Name)"
    $global:AzureProject.ResourceType.StorageContainer.Scope = "$scopeBase/Microsoft.Storage/storageAccounts/$($global:AzureProject.ResourceType.StorageAccount.Name)/blobServices/default/containers/$($global:AzureProject.ResourceType.StorageContainer.Name)"
    $global:AzureProject.ResourceType.Bastion.Scope = "$scopeBase/Microsoft.Network/bastionHosts/$($global:AzureProject.ResourceType.Bastion.Name)"
    $global:AzureProject.ResourceType.VM.Scope = "$scopeBase/Microsoft.Compute/virtualMachines/$($global:AzureProject.ResourceType.VM.Name)"
    $global:AzureProject.ResourceType.MLWorkspace.Scope = "$scopeBase/Microsoft.MachineLearningServices/workspaces/$($global:AzureProject.ResourceType.MLWorkspace.Name)"
    $global:AzureProject.ResourceType.CosmosDBAccount.Scope = "$scopeBase/Microsoft.DocumentDB/databaseAccounts/$($global:AzureProject.ResourceType.CosmosDBAccount.Name)" 
    $global:AzureProject.ResourceType.SqlVM.Scope = "$scopeBase/Microsoft.SqlVirtualMachine/SqlVirtualMachines/$($global:AzureProject.ResourceType.SqlVM.Name)"
    $global:AzureProject.ResourceType.KeyVault.Scope = "$scopeBase/Microsoft.KeyVault/vaults/$($global:AzureProject.ResourceType.KeyVault.Name)"
    $global:AzureProject.ResourceType.DataFactory.Scope = "$scopeBase/Microsoft.DataFactory/factories/$($global:AzureProject.ResourceType.DataFactory.Name)"

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
            $global:AzureProject.ResourceType.MLWorkspace.Object = Get-AzMlWorkspace -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -WorkspaceName $global:AzureProject.ResourceType.MLWorkspace.Name -ErrorAction SilentlyContinue
        }
    }

}

function global:New-AzResource {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("ResourceGroup")][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$ResourceType,
        [Parameter(Mandatory=$true)][string]$ResourceName
    )

    $applicationInsights = Get-AzApplicationInsights -ResourceGroupName $ResourceGroupName
    $containerRegistry = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName
    $keyVault = $global:AzureProject.ResourceType.KeyVault
    $location = $global:Azure.Templates.Resources.Location
    $storageAccount = $global:AzureProject.ResourceType.StorageAccount

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
            $object = New-AzStorageContainer+ -Tenant $tenantKey -Context $storageAccount.Context -ContainerName $ResourceName
        }
    }

    return $object

}

function global:New-AzProject {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$false)][Alias("StorageContainer")][string]$StorageContainerName
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    $emptyString = ""

    # $projectNameTitleCase = (Get-Culture).TextInfo.ToTitleCase($ProjectName)
    $projectNameLowerCase = $ProjectName.ToLower()
    # $projectNameUpperCase = $ProjectName.ToUpper()

    if ($projectNameLowerCase -ne $global:AzureProject.Name) {
        Write-Host+ -NoTrace "`$global:AzureProject has not been initialized for project $($ProjectName)" -ForegroundColor DarkRed
    }
    
    $message = "<  Resource creation <.>60> PENDING" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    Write-Host+

    $message = "<    ResourceGroup/:$($global:AzureProject.ResourceType.ResourceGroup.Name) <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
    $resourceGroup = Get-AzResourceGroup -Name $global:AzureProject.ResourceType.ResourceGroup.Name 
    if ($resourceGroup) {
        $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
    }
    else {
        $global:AzureProject.ResourceType.ResourceGroup.Object = New-AzResourceGroup+ -Tenant $tenantKey -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name 
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

    $message = "<    StorageAccount/:$($global:AzureProject.ResourceType.StorageAccount.Name) <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name -Name $global:AzureProject.ResourceType.StorageAccount.Name -ErrorAction SilentlyContinue
    if ($storageAccount) {
        $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
    }
    else {
        $global:AzureProject.ResourceType.StorageAccount.Object = New-AzStorageAccount+ -Tenant $tenantKey -ResourceGroupName $global:AzureProject.ResourceType.ResourceGroup.Name  -StorageAccountName $global:AzureProject.ResourceType.StorageAccount.Name
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

    $StorageContainerName = ![string]::IsNullOrEmpty($StorageContainerName) ? $StorageContainerName : $global:AzureProject.ResourceType.StorageContainer.Name
    if ($StorageContainerName -ne $global:AzureProject.ResourceType.StorageContainer.Name) {
        $global:AzureProject.ResourceType.StorageContainer.Name = $StorageContainerName
    }
    $message = "<    StorageContainer/:$StorageContainerName <.>60> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkGray,Gray,DarkGray,DarkGray
    $storageAccountContext = New-AzStorageContext -StorageAccountName $global:AzureProject.ResourceType.StorageAccount.Name -UseConnectedAccount -ErrorAction SilentlyContinue
    $storageContainer = Get-AzStorageContainer -Context $storageAccountContext -Name $StorageContainerName -ErrorAction SilentlyContinue
    if ($storageContainer) {
        $message = "$($emptyString.PadLeft(8,"`b")) Exists$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkYellow
    }
    else {
        $global:AzureProject.ResourceType.StorageAccount.Context = New-AzStorageContext -StorageAccountName $global:AzureProject.ResourceType.StorageAccount.Name -UseConnectedAccount
        $global:AzureProject.ResourceType.StorageContainer.Object = New-AzStorageContainer+ -Tenant $tenantKey -Context $global:AzureProject.ResourceType.StorageAccount.Context -ContainerName $StorageContainerName
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }
    
    Write-Host+
    $message = "<  Resource creation <.>60> SUCCESS" 
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGreen
    
}
Set-Alias -Name azProjNew -Value New-AzProject -Scope Global

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
        Write-Host+ -NoTrace -Prefix "ERROR" "$Path not found." -ForegroundColor DarkRed
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

function global:ConvertTo-AzProjectFile {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName
    )

    # Original AzProject Import File
    # ------------------------------
    # <prefix>-roleAssignments.csv: "project","resourceType","resourceName","role","signInName","fullName"

    $roleAssignmentsFile = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments.csv"

    # Current AzProject Import Files
    # ------------------------------
    # <prefix>-users-import.csv: "signInName","fullName"
    # [optional] <prefix>-groups-import.csv: "group","user"
    # <prefix>-resources-import.csv: "resourceType","resourceName","resourceID"
    # <prefix>-roleAssignments-import.csv: "resourceID","role","assigneeType","assignee"    

    $userImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-users-import.csv"
    $groupImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-groups-import.csv"
    $resourceImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
    $roleAssignmentImportFile = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments-import.csv"
    
    # ABORT if any of the new AzProject import files already exist
    if ((Test-Path $userImportFile) -or (Test-Path $groupImportFile) -or (Test-Path $ResourceImportFile) -or (Test-Path $RoleAssignmentImportFile)) {
        Write-Host+ -Iff $(Test-Path $userImportFile) -NoTrace -NoTimestamp "INFO: $userImportFile already exists." 
        Write-Host+ -Iff $(Test-Path $groupImportFile) -NoTrace -NoTimestamp "INFO: $groupImportFile already exists." 
        Write-Host+ -Iff $(Test-Path $resourceImportFile) -NoTrace -NoTimestamp "INFO: $resourceImportFile already exists." 
        Write-Host+ -Iff $(Test-Path $roleAssignmentImportFile) -NoTrace -NoTimestamp "INFO: $roleAssignmentImportFile already exists." 
        Write-Host+ -NoTrace -NoTimestamp "WARN: One or more AzProject import files already exists." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoTimestamp "WARN: AzProject import file conversion aborted." -ForegroundColor DarkYellow
        return
    }   

    # Current AzProject Export File
    # -----------------------------
    # <prefix>-roleAssignments-export.csv: "resourceType","resourceName","role","name"

    $roleAssignmentExportFile = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments-export.csv"

    # ERROR if the old AzProject import file does not exist
    if (!(Test-Path $roleAssignmentsFile)) {
        Write-Host+ -NoTrace -NoTimestamp "ERROR: $roleAssignmentsFile not found." -ForegroundColor DarkRed
        return
    } 

    # read old AzProject import data
    $roleAssignments = Import-AzProjectFile $roleAssignmentsFile

    # write old AzProject import data to new AzProject import files 
    $roleAssignments | Select-Object -Property signInName,fullName | Sort-Object -Property signInName -Unique | Export-Csv $userImportFile -UseQuotes Always -NoTypeInformation
    $roleAssignments | Select-Object -Property resourceType,resourceName,@{name="resourceID";expression={$_.resourceType + ($_.resourceName ? "-" + $_.resourceName : $null)}} | Sort-Object -Property resourceType, resourceName -Unique | Export-Csv $resourceImportFile -UseQuotes Always  -NoTypeInformation
    $roleAssignments | Select-Object -Property @{name="resourceID";expression={$_.resourceType + ($_.resourceName ? "-" + $_.resourceName : $null)}}, role, @{name="assigneeType";expression={"user"}}, @{name="assignee";expression={$_.signInName}} | Export-Csv $roleAssignmentImportFile -UseQuotes Always  -NoTypeInformation

    # write headers only to the new AzProject group import file and the export file
    Set-Content -Path $groupImportFile -Value '"group","user"'
    Set-Content -Path $roleAssignmentExportFile -Value '"resourceType","resourceName","role","name"'

    # archive the old AzProject import file
    $archiveDirectory = "$($global:AzureProject.Location.Data)\archive"
    if (!(Test-Path $archiveDirectory)) {
        New-Item -Path $global:AzureProject.Location.Data -Name "archive" -ItemType Directory | Out-Null
    }
    Move-Item -Path $roleAssignmentsFile -Destination $archiveDirectory
    Write-Host+ -NoTrace -NoTimestamp "INFO: $roleAssignmentsFile archived."

}

function global:Grant-AzProjectRole {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$false)][Alias("UserPrincipalName","UPN","Id","UserId","Email","Mail")][string]$User,
        [switch]$ReferencedResourcesOnly,
        [switch]$RemoveUnauthorizedRoleAssignments
    )

    function Get-AzProjectResourceFromScope {

        param(
            [Parameter(Mandatory=$true)][string]$Tenant,
            [Parameter(Mandatory=$true,Position=0)][string]$Scope
        )
    
        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}
    
        $scopeBase = "/subscriptions/$($global:Azure.$tenantKey.Subscription.Id)/resourceGroups/$($global:AzureProject.ResourceType.ResourceGroup.Name)/providers"
        $resourceName = $Scope.Split("/")[-1]
        $provider = $Scope.Replace($scopeBase,"")
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
        }
    
        return [PSCustomObject]@{
            resourceType = $resourceType
            resourceName = $resourceName
            resourceID = $resourceType + "-" + $resourceName
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
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp "  Role assignments not specified in `"$ProjectName-roleAssignments-import.csv`" will be removed." -ForegroundColor Gray
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

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    $resourceGroupName = $global:AzureProject.ResourceType.ResourceGroup.Name

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

        $UserImport = "$($global:AzureProject.Location.Data)\$ProjectName-users-import.csv"
        $GroupImport = "$($global:AzureProject.Location.Data)\$ProjectName-groups-import.csv"
        $ResourceImport = "$($global:AzureProject.Location.Data)\$ProjectName-resources-import.csv"
        $RoleAssignmentImport = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments-import.csv"
        $RoleAssignmentExport = "$($global:AzureProject.Location.Data)\$ProjectName-roleAssignments-export.csv"

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

        Write-Host+ -NoTrace -NoSeparator "    $GroupImport" -ForegroundColor DarkGray
        $groups = @()
        if (Test-Path $GroupImport) {
            $groups += Import-AzProjectFile $GroupImport
            if ($User) {
                # if $User has been specified, filter $groups to only those containing $User
                $groups = $groups | Where-Object {$_.user -eq $User}
            }
        }

        Write-Host+ -NoTrace -NoSeparator "    $ResourceImport" -ForegroundColor DarkGray
        $resources = @(); $resources += [PSCustomObject]@{resourceType = "ResourceGroup"; resourceName = $resourceGroupName; resourceID = "ResourceGroup-$resourceGroupName"; resourceScope = $global:AzureProject.ResourceType.ResourceGroup.Scope}
        $resources += Import-AzProjectFile -Path $ResourceImport | Select-Object -Property resourceType, resourceName, resourceID, @{Name="resourceScope"; Expression={$null}} | Sort-Object -Property resourceType, resourceName -Unique   

        Write-Host+ -NoTrace -NoSeparator "    $RoleAssignmentImport" -ForegroundColor DarkGray
        $roleAssignmentsFromFile = Import-AzProjectFile -Path $RoleAssignmentImport
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
            $resourcePath = $resourceGroupName -eq $resourceName ? $resourceGroupName : "$resourceGroupName/$resourceName"

            $scope = $null
            if ([string]::IsNullOrEmpty($resource.resourceScope)) {
                $scope = $global:AzureProject.ResourceType.$ResourceType.Scope
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
                        $object = New-AzResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator "$($emptyString.PadLeft(8,"`b"))NEW$($emptyString.PadLeft(8," "))"
                        $displayScope = $false
                    }
                }
                "StorageContainer" {
                    $object = Get-AzStorageContainer -Context $global:AzureProject.ResourceType.StorageAccount.Context -Name $resourceName
                    if (!$object) {
                        $message = "    $($scope.split("/resourceGroups/")[1].replace("providers/Microsoft.",$null)) : CREATING"
                        Write-Host+ -NoTrace -NoSeparator -NoNewLine  $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor DarkGray,Gray
                        $object = New-AzResource -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName
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

                        if ($global:AzureProject.ResourceType.NetworkInterface.Scope -notcontains $nicScope) {
                            $global:AzureProject.ResourceType.NetworkInterface += @{
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

        # Initialize-AzureConfig
        # Connect-AzureAD -Tenant $tenantKey

        $authorizedProjectUsers = @()
        foreach ($signInName in $signInNames) {
            $azureADUser = Get-AzureADUser -Tenant $tenantKey -User $signInName
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
                    $unauthorizedAzureADUser = Get-AzureADUser -Tenant $tenantKey -User $invalidProjectRoleAssignment.SignInName
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
                    $invitation = Send-AzureADInvitation -Tenant $tenantKey -Email $signInName -DisplayName $fullName -Message $global:AzureProject.Invitation.Message
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
            $resourceFromScope = Get-AzProjectResourceFromScope -Tenant $tenantKey -Scope $unauthorizedProjectRoleAssignment.Scope
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

            $identity = $assignee.identities | Where-Object {$_.issuer -eq $global:Azure.$tenantKey.Tenant.Name}
            $signInType = $identity.signInType
            $signIn = $signInType -eq "userPrincipalName" ? $assignee.userPrincipalName : $signInName
            
            $resourceTypes = @()
            $resourceTypes += ($roleAssignments | Where-Object {$_.signInName -eq $signInName} | Sort-Object -Property resourceTypeSortOrder,resourceType -Unique ).resourceType 
            if (!$ReferencedResourcesOnly) {
                $resourceTypes += $global:AzureProject.ResourceType.Keys | Where-Object {$_ -notin $resourceTypes -and $_ -ne "ResourceGroup" -and $global:AzureProject.ResourceType.$_.Object}
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

                    $resourceName = ![string]::IsNullOrEmpty($resource.resourceName) ? $resource.resourceName : ($global:AzureProject.ResourceType.($resourceType).Scope).split("/")[-1]
                    $resourceScope = Get-AzProjectResourceScope -ResourceType $resourceType -ResourceName $resourceName

                    $message = "    $($resourceType)/$($resourceName)"
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
Set-Alias -Name azProjGrant -Value Grant-AzProjectRole -Scope Global

function global:Deploy-AzProject {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$true)][ValidateSet("DSnA","StorageAccount")][string]$DeploymentType,   
        [Parameter(Mandatory=$false)][Alias("StorageContainer")][string]$StorageContainerName,
        [Parameter(Mandatory=$false)][string]$VmSize,
        [Parameter(Mandatory=$false)][ValidateSet("canonical","microsoft-dsvm")][string]$VmImagePublisher,
        [Parameter(Mandatory=$false)][ValidateSet("dsvm-win-2019","linux-data-science-vm-ubuntu","ubuntuserver")][string]$VmImageOffer
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    switch ($DeploymentType) {
        "DSnA" {    
            Deploy-DSnA -Tenant $tenantKey -Project $ProjectName -VmSize $VmSize -VmImagePublisher $VmImagePublisher -VmImageOffer $VmImageOffer
        }
        "StorageAccount" {
            New-AzProject -Tenant $tenantKey -Project $ProjectName -StorageContainerName $StorageContainerName
        }
    }
    
    Get-AzProjectResourceScopes
    Get-AzProjectDeployedResources

    Grant-AzProjectRole -Tenant $tenantKey -Project $ProjectName

    return

}
Set-Alias -Name azProjDeploy -Value Deploy-AzProject -Scope Global

function global:Deploy-DSnA {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][Alias("Project")][string]$ProjectName,
        [Parameter(Mandatory=$false)][string]$VmSize,
        [Parameter(Mandatory=$true)][ValidateSet("canonical","microsoft-dsvm")][string]$VmImagePublisher,
        [Parameter(Mandatory=$true)][ValidateSet("dsvm-win-2019","linux-data-science-vm-ubuntu","ubuntuserver")][string]$VmImageOffer
    )

    # Initialize-AzureConfig

    # $tenantKey = $Tenant.split(".")[0].ToLower()
    # if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    # Connect-AzureAD -Tenant $tenantKey

    # Initialize-AzProject -ProjectName $ProjectName -Tenant $tenantKey

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}
    if ($ProjectName -ne $global:AzureProject.Name) {throw "`$global:AzureProject not initialized for project $ProjectName"}

    $VmSize = ![string]::IsNullOrEmpty($VmSize) ? $VmSize : $global:Azure.Templates.Resources.VM.Size 
    $VmOsType = ![string]::IsNullOrEmpty($VmOsType) ? $VmOsType : $global:Azure.Templates.Resources.VM.OsType

    if (Test-Credentials $global:AzureProject.ResourceType.VM.Admin -NoValidate) {
        $adminCreds = Get-Credentials $global:AzureProject.ResourceType.VM.Admin -Location $global:AzureProject.Location.Credentials
    }
    else {
        $adminCreds = Request-Credentials -UserName $global:AzureProject.VM.Admin -Password (New-RandomPassword -ExcludeSpecialCharacters)
        Set-Credentials $global:AzureProject.VM.Admin -Credentials $adminCreds
    }

    $params = @{
        Subscription = $global:Azure.$tenantKey.Subscription.Id
        Tenant = $global:Azure.$tenantKey.Tenant.Id
        Prefix = $global:Azure.$tenantKey.Prefix
        Random = $ProjectName
        ResourceGroup = $global:AzureProject.ResourceType.ResourceGroup.Name
        BlobContainerName = $global:AzureProject.ResourceType.StorageContainer.Name
        VMSize = $VmSize
        location = $global:Azure.Templates.Resources.Location
    }

    Set-Location "$($Location.Data)\azure\deployment\vmImages\$VmImagePublisher\$VmImageOffer\config"

    if (Select-String -path "deploy.ps1" -Pattern "AdminPassword" -Quiet) {
        $params += @{AdminPassword = $adminCreds.Password}
    }
    if (Select-String -path "deploy.ps1" -Pattern "SshPrivateKeyPath" -Quiet) {
        $params += @{
            SshPrivateKeyPath = "~/.ssh/$($ProjectName)_rsa.private"
            SshPublicKeyPath = "~/.ssh/$($ProjectName)_rsa.public"
        }
    }

    .\deploy.ps1 @params
    
    Set-Location $global:Location.Root

    return

}

Remove-PSSession+
