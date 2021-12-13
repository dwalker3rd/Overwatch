#
# ISSUE (MSAL.PS): https://github.com/AzureAD/MSAL.PS/issues/32
# MSAL.PS and Az.Accounts use different versions of the Microsoft.Identity.Client
# Az.Accounts requires Microsoft.Identity.Client, Version=4.30.1.0
# MSAL.PS requires Microsoft.Identity.Client, Version=4.21.0 
# if Connect-AzAccount+ is called first, then Reset-AzureADUserPassword will fail
# if Reset-AzureADUserPassword is called first, then Connect-AzAccount+ will fail
# 

function global:Connect-AzAccount+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $subscriptionId = $global:AzureAD.$tenantKey.Subscription.Id
    $tenantId = $global:AzureAD.$tenantKey.Tenant.Id

    $creds = get-credentials $global:AzureAD.$tenantKey.Admin.Credentials

    $azureProfile = Connect-AzAccount -Credential $creds -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if (!$azureProfile) {
        $exception = [Microsoft.Azure.Commands.Common.Exceptions.AzPSAuthenticationFailedException](Get-Error).Exception
        if ($exception.DesensitizedErrorMessage -like "MFA*") {
            $azureProfile = Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId
        }
    }

    return $azureProfile

}

function global:New-AzResourceGroup+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$Location = $global:AzureAD.$tenantKey.Defaults.Location
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    return New-AzResourceGroup -Name $ResourceGroupName -Location $Location

}

function global:New-AzStorageAccount+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$StorageAccountName,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$SKU = $global:AzureAD.$tenantKey.Defaults.StorageAccount.SKU,
        [Parameter(Mandatory=$false)][string]$Location = $global:AzureAD.$tenantKey.Defaults.Location,
        [Parameter(Mandatory=$false)][int]$RetentionDays = $global:AzureAD.$tenantKey.Defaults.StorageAccount.SoftDelete.RetentionDays
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName $SKU -Location $location

    if ($global:AzureAD.$tenantKey.Defaults.StorageAccount.SoftDelete.Enabled) {
        Enable-AzStorageBlobDeleteRetentionPolicy -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -RetentionDays $RetentionDays
    }

    return $storageAccount
}

function global:New-AzStorageContainer+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][object]$Context,
        [Parameter(Mandatory=$true)][string]$ContainerName,
        [Parameter(Mandatory=$false)][ValidateSet("Container","Blob","Off")][string]$Permission = $global:AzureAD.$tenantKey.Defaults.StorageAccount.Permission
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    return New-AzStorageContainer -Name $ContainerName.ToLower() -Context $Context -Permission $Permission

}

function global:New-AzRoleAssignment+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Scope,
        [Parameter(Mandatory=$true)][string]$RoleDefinitionName,
        [Parameter(Mandatory=$true)][Alias("Owners","Contributors","Readers")][string[]]$SignInNames
    )

    $roleAssignments = @()

    foreach ($signInName in $SignInNames) {
        $roleAssignments += New-AzRoleAssignment -SignInName $signInName -RoleDefinitionName $RoleDefinitionName -Scope $Scope
    }

    return $roleAssignments

}

function global:Get-AzRoleAssignments {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$Scope,
        [switch]$IncludeInheritance
    )

    $tenantkey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $subscriptionId = $global:AzureAD.$tenantKey.Subscription.Id
    $subscriptionScope = "/subscriptions/$($subscriptionId)"
    $ignore = @("/",$subscriptionScope)

    $roleAssignments = Get-AzRoleAssignment -Scope $Scope
    if (!$IncludeInheritance) { 
        $roleAssignments = $roleAssignments | Where-Object {$_.scope -notin $ignore}
    }

    return $roleAssignments

}
        
function global:Format-AzRoleAssignments {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][Object]$InputObject,
        [Parameter(Mandatory=$false)][string]$GroupBy
    )

    begin {

        $props = @("Scope","RoleAssignmentId","RoleDefinitionName","ObjectType","ObjectId","SignInName","DisplayName")
        $params = @{Property = $props}
        if ($GroupBy) {
            $params = @{
                GroupBy = $GroupBy
                Property = $props | Where-Object {$_ -ne $GroupBy}
            }
        }

        $outputObject = @()

    }
    process {

        if ($InputObject) {$outputObject += $InputObject}

    }
    end {

        return $outputObject | 
            Select-Object -Property @{name="RoleAssignmentId";expression={$_.RoleAssignmentId.split("/")[-1]}},
                RoleDefinitionName,ObjectType,ObjectId,SignInName,DisplayName,Scope | 
                    Sort-Object -Property $props | 
                        Format-Table @params

    }

}
Set-Alias -Name ftAzRoles -Value Format-AzRoleAssignments -Scope Global

$global:AzVizResourceGroups = @(
    "hub-rg",
    "apps-gen-rg",
    "apps-tableau-rg",
    "apps-alteryx-rg"
)
$global:AzVizExcludeTypes = @(
    "microsoft.compute/disks",
    "microsoft.insights/datacollectionrules",
    "microsoft.operationsmanagement/solutions",
    "microsoft.compute/virtualmachines/extensions",
    "microsoft.automation/automationaccounts/jobs",
    "microsoft.automation/automationaccounts/modules",
    "microsoft.automation/automationaccounts/jobschedules",
    "microsoft.operationalinsights/workspaces",
    "microsoft.storage/storageaccounts/*/*diag*",
    "microsoft.datashare/accounts",
    "microsoft.managedidentity/userAssignedIdentities",
    "microsoft.recoveryservices/vaults",
    "microsoft.automation/automationaccounts",
    "microsoft.network/firewallpolicies")

function global:Publish-AzDiagram {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string[]]$ResourceGroup,
        [Parameter(Mandatory=$false)][string]$OutputFilePath = "F:\Overwatch\docs\diagrams",
        [Parameter(Mandatory=$false)][ValidateSet("svg","png")][string]$OutputFormat = "svg",
        [Parameter(Mandatory=$false)][ValidateRange(1,3)][int]$LabelVerbosity = 2,
        [Parameter(Mandatory=$false)][ValidateRange(1,3)][int]$CategoryDepth = 1,
        [Parameter(Mandatory=$false)][string[]]$ExcludeTypes = $global:AzVizExcludeTypes,
        [Parameter(Mandatory=$false)][bool]$Show = $false
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

    $ResourceGroup | ForEach-Object {
        Export-AzViz -ResourceGroup $_ -Theme light -Show:$Show -OutputFormat $OutputFormat -OutputFilePath "$($OutputFilePath)\$($_).$($OutputFormat)" -LabelVerbosity $LabelVerbosity -CategoryDepth $CategoryDepth -ExcludeTypes $ExcludeTypes
    }
}

function global:Get-AzMlWorkspace {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("ResourceGroup")][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][Alias("Workspace")][string]$WorkspaceName
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    return (az ml workspace show --resource-group $ResourceGroupName --workspace $WorkspaceName | ConvertFrom-Json)

}