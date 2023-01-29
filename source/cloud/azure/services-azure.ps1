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

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    $subscriptionId = $global:Azure.$tenantKey.Subscription.Id
    $tenantId = $global:Azure.$tenantKey.Tenant.Id

    $creds = get-credentials $global:Azure.$tenantKey.Admin.Credentials

    $azureProfile = Connect-AzAccount -Credential $creds -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if (!$azureProfile) {
        $exception = [Microsoft.Azure.Commands.Common.Exceptions.AzPSAuthenticationFailedException](Get-Error).Exception
        if ($exception.DesensitizedErrorMessage -like "MFA*") {
            $azureProfile = Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId
        }
    }

    return $azureProfile

}


function global:Update-AzureConfig {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$TenantId,
        [Parameter(Mandatory=$false)][string]$SubscriptionId,
        [Parameter(Mandatory=$false)][string]$Credentials,
        [switch]$Sync
    )

    foreach ($tenantKey in (Get-AzureTenantKeys)) {
        if ($global:Azure.$tenantKey.Tenant.Id -eq $TenantId) {
            # if ($PSBoundParameters.ErrorAction -and $PSBoundParameters.ErrorAction -ne "SilentlyContinue") {
            #     Write-Host+ -NoTimestamp "    Tenant id `"$($global:Azure.$tenantKey.Tenant.Id)`" has already been added."
            # }
            return @{
                SubscriptionId = $global:Azure.$tenantKey.Subscription.Id
                TenantId = $global:Azure.$tenantKey.Tenant.Id
                TenantKey = $tenantKey
            }
        }
    }

    Write-Host+; Write-Host+

    do {

        do {

            if (![string]::IsNullOrEmpty($Credentials) -and $(Test-Credentials $Credentials -NoValidate)) {
                $creds = Get-Credentials $Credentials
            }
            else {
                $creds = Request-Credentials -Message "    Enter Azure Admin Credentials" -Prompt1 "      Username" -Prompt2 "      Password"
            }

            Write-Host+

            do {
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Azure Subscription ID ", "$($SubscriptionId ? "[$SubscriptionId] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
                if (!$UseDefaultResponses) {
                    $subscriptionIdResponse = Read-Host
                }
                else {
                    Write-Host+
                }
                $SubscriptionId = ![string]::IsNullOrEmpty($subscriptionIdResponse) ? $subscriptionIdResponse : $SubscriptionId
                if ([string]::IsNullOrEmpty($SubscriptionId)) {
                    Write-Host+ -NoTrace -NoTimestamp "    NULL: Azure Subscription ID is required." -ForegroundColor Red
                    $SubscriptionId = $null
                }
            } until ($SubscriptionId)

            do {
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Azure Tenant ID ", "$($TenantId ? "[$TenantId] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
                if (!$UseDefaultResponses) {
                    $tenantIdResponse = Read-Host
                }
                else { 
                    Write-Host+
                }
                $TenantId = ![string]::IsNullOrEmpty($tenantIdResponse) ? $tenantIdResponse : $TenantId
                if ([string]::IsNullOrEmpty($TenantId)) {
                    Write-Host+ -NoTrace -NoTimestamp "    NULL: Azure AD tenant ID is required." -ForegroundColor Red
                    $TenantId = $null
                }
            } until ($TenantId)

            Write-Host+

            $azureProfile = Connect-AzAccount -Credential $creds -TenantId $TenantId -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            if (!$azureProfile) {
                $exception = [Microsoft.Azure.Commands.Common.Exceptions.AzPSAuthenticationFailedException](Get-Error).Exception
                if ($exception.DesensitizedErrorMessage -like "MFA*") {
                    $azureProfile = Connect-AzAccount -TenantId $TenantId -SubscriptionId $SubscriptionId
                }
            }

            if (!$azureProfile) {
                Write-Host+ -NoTrace -NoTimestamp "    Invalid Tenant ID, Subscription ID or Azure Admin Credentials." -ForegroundColor Red
                $TenantId = $SubscriptionId = $creds = $null
            }

            Write-Host+

        } until ($azureProfile)

        $azTenant = Get-AzTenant -TenantId $TenantId

        $tenantDomain = $azTenant.DefaultDomain
        $tenantKey = ($azTenant.DefaultDomain -split "\.")[0]
        $tenantName = $azTenant.Name
        # $tenantId = $azTenant.TenantId
        $tenantType = $azTenant.TenantType -replace "AAD","Azure AD"
        $tenantDirectory = $azTenant.ExtendedProperties.Directory
        $subscriptionName = $azureProfile.Context.Subscription.Name
        # $subscriptionId = $azureProfile.Context.Subscription.Id

        # got the azure profile, therefore azure admin credentials are valid 
        $creds | Set-Credentials "$tenantKey-admin"

        # Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "    Subscription: $subscriptionName ($SubscriptionId)"
        Write-Host+ -NoTrace -NoTimestamp "    Tenant: $tenantName ($TenantId)"
        Write-Host+ -NoTrace -NoTimestamp "    DefaultDomain: $tenantDomain"
        Write-Host+ -NoTrace -NoTimestamp "    TenantType: $tenantType"
        Write-Host+ -NoTrace -NoTimestamp "    Directory: $tenantDirectory"
        Write-Host+

        $azureConfigurationResponse = Read-Host -Prompt "    Configure this Azure Subscription/Tenant? (Y/N)"
    
    } until ($azureConfigurationResponse.ToUpper().StartsWith("Y"))

    foreach ($tenantKey in (Get-AzureTenantKeys)) {
        if ($global:Azure.$tenantKey.Tenant.Id -eq $TenantId) {
            # Write-Host+ -NoTrace -NoTimestamp "    Tenant id `"$($global:Azure.$tenantKey.Tenant.Id)`" has already been added." -ForegroundColor Red
            return @{
                SubscriptionId = $SubscriptionId
                TenantId = $TenantId
                TenantKey = $tenantKey
                Credentials = "$tenantKey-admin"
            }
        }
    }

    $_tenantTemplate = @{
        $tenantKey = @{
            Name = $tenantName
            DisplayName = $tenantName
            Organization = $null
            Subscription = @{
                Id = $subscriptionId
                Name = $subscriptionName
            }
            Tenant = @{
                Id = $TenantId
                Name = $tenantName
                Type = $tenantType
                Domain = $tenantDomain
            }
            Admin = @{
                Credentials = "$tenantKey-admin"
            }
            MsGraph = @{
                Credentials = "$tenantKey-msgraph"
                Scope = "https://graph.microsoft.com/.default"
                AccessToken = $null
            }
            Prefix = $tenantKey
        }
    }

    if ($Sync) {
        switch ($tenantType) {
            "Azure AD" {

                $_tenantTemplate.$tenantKey += @{
                    Sync = @{
                        Enabled = $false
                        Source = $tenantDirectory
                        IdentityIssuer = ""
                    }
                }

            }
            "Azure AD B2C" {

                $_identityIssuers = @()
                $azureADUsers,$cacheError = Get-AzureADUsers -Tenant $tenantKey -AsArray
                $azureADUsers | Foreach-Object { 
                    $issuerAssignedId = ($_.identities | Where-Object {$_.signInType -eq "emailAddress"}).issuerAssignedId
                    $issuer = ($_.identities | Where-Object {$_.signInType -eq "federated"}).issuer
                    if ($null -ne $issuerAssignedId -and $issuerAssignedId.EndsWith($tenantDirectory) -and $null -ne $issuer -and $issuer -notin $_identityIssuers) { 
                        $_identityIssuers += $issuer 
                    }
                }

                $_tenantTemplate.$tenantKey += @{
                    Sync = @{
                        Enabled = $true
                        Source = Get-AzureTenantKeys -AzureAD
                        IdentityIssuer = $_identityIssuers -join ", "
                    }
                }

            }
        }
    }

    $azureDefinitionsFile = "$($global:Location.Definitions)\definitions-cloud-azure.ps1"
    $azureDefinitions = Get-Content -Path $azureDefinitionsFile

    $i = 0
    $foundMatch = $false
    do {
        if ($azureDefinitions[$i] -match "Templates = @\{") {
            $foundMatch = $true
        }
        else {
            $i++
        }
    } until ($foundMatch -or $i -gt $azureDefinitions.Count)

    if (![string]::IsNullOrEmpty($azureDefinitions[$i-1])) {
        $azureDefinitions = $azureDefinitions.Replace($azureDefinitions[$i], "$($azureDefinitions[$i])`r`n")
    }
    $i--

    $azureDefinitions = ($azureDefinitions[0..$i] | Out-String) + ($_tenantTemplate | ConvertTo-PowerShell -Indent 12) + ($azureDefinitions[($i+1)..($azureDefinitions.count)] | Out-String)
    $azureDefinitions | Set-Content -Path $azureDefinitionsFile

    . $azureDefinitionsFile
    Initialize-AzureConfig -Reinitialize

    return @{
        SubscriptionId = $SubscriptionId
        TenantId = $TenantId
        TenantKey = $tenantKey
        Credentials = "$tenantKey-admin"
    }

}

function global:New-AzResourceGroup+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$Location = $global:Azure.Templates.Resources.Location
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    return New-AzResourceGroup -Name $ResourceGroupName -Location $Location

}

function global:New-AzStorageAccount+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$StorageAccountName,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$SKU = $global:Azure.Templates.Resources.StorageAccount.SKU,
        [Parameter(Mandatory=$false)][string]$Location = $global:Azure.Templates.Resources.Location,
        [Parameter(Mandatory=$false)][int]$RetentionDays = $global:Azure.Templates.Resources.StorageAccount.SoftDelete.RetentionDays
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName $SKU -Location $location

    if ($global:Azure.Templates.Resources.StorageAccount.SoftDelete.Enabled) {
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
        [Parameter(Mandatory=$false)][ValidateSet("Container","Blob","Off")][string]$Permission = $global:Azure.Templates.Resources.StorageAccount.Permission
    )

    $tenantKey = $Tenant.split(".")[0].ToLower()
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

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
    if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured Azure tenant."}

    $subscriptionId = $global:Azure.$tenantKey.Subscription.Id
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

function global:Get-AzMlWorkspace {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Alias("ResourceGroup")][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][Alias("Workspace")][string]$WorkspaceName
    )

    return (az ml workspace show --resource-group $ResourceGroupName --workspace $WorkspaceName | ConvertFrom-Json)

}

function global:Get-AzVmContext {

    param(
        [Parameter(Mandatory=$false,Position=0)][string]$VmName=$env:COMPUTERNAME
    )

    $azVmContext = @{}
    $vm = Get-AzVM -Name $VmName
    if (!$vm) { return $azVmContext }
    $vm | Get-Member -MemberType Property | Foreach-Object {
        switch ($_.Name) {
            "Extensions" {}
            default {
                $azVmContext += @{ $_ = $vm.($_) }
            }
        }
    }
    $azVmContext += @{ Extensions = @{} }
    foreach ($extension in Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name) {
        $azVmContext.Extensions += @{
            $extension.Name = $extension
        }
    }

    $azVmContext += @{ ResourceGroup = @{} }
    $resourceGroup = Get-AzResourceGroup -Name $vm.ResourceGroupName
    if (!$resourceGroup) { return $azVmContext }
    $azVmContext.ResourceGroup = @{
        ResourceID = $resourcegroup.ResourceId
        ResourceGroupName = $resourceGroup.ResourceGroupName
        Location = $resourceGroup.Location
    }

    $azVmContext += @{ Subscription = @{} }
    $subscription = Get-AzSubscription -SubscriptionId ($vm.Id -split "/")[2]
    if (!$subscription) { return $azVmContext }
    $azVmContext.Subscription = @{
        Id = $subscription.SubscriptionId
        TenantId = $subscription.TenantId
        Name = $subscription.Name
        Environment = $subscription.ExtendedProperties.Environment
    }

    $azVmContext += @{ Tenant = @{} }
    $tenant = Get-AzTenant -TenantId $subscription.TenantId
    if (!$subscription) { return $azVmContext }
    $azVmContext.Tenant = @{
        Id = $tenant.Id
        Name = $tenant.Name
        Type = $tenant.TenantType
        Domain = $tenant.DefaultDomain
    }

    return $azVmContext

}

function global:Install-AzVmExtension {

    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string[]]$VmName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$true)][string]$Publisher,
        [Parameter(Mandatory=$true)][string]$ExtensionType,
        [Parameter(Mandatory=$true)][string]$TypeHandlerVersion
    )

    foreach ($node in $VmName) {

        $azVmExtension = Get-AzVmExtension -ResourceGroupName $resourceGroupName -VMName $node -Name $Name -ErrorAction SilentlyContinue
        if (!$azVmExtension) {
            Set-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $node -Name $Name -TypeHandlerVersion $bgInfoTypeHandlerVersion -Location $Location
        }

    }
}

function global:Get-AzureTenantKeys {

    [CmdletBinding()]
    param(
        [switch]$All,
        [switch]$AzureAD,
        [switch]$AzureADB2C
    )

    if ($All -and $AzureAD) {
        throw "The `"All`" switch cannot be used with the `"AzureAD`" switch"
    }
    if ($All -and $AzureADB2C) {
        throw "The `"All`" switch cannot be used with the `"AzureADB2C`" switch"
    }
    if ($AzureAD -and $AzureADB2C) {
        throw "The `"AzureAD`" and `"AzureADB2C`" switches cannot be used together"
    }
    if (!$AzureAD -and !$AzureADB2C) { $All = $true }

    $tenantKeys = @()
    $tenantKeys = foreach ($key in ($global:Azure.Keys)) {
        if (![string]::IsNullOrEmpty($global:Azure.$key.Tenant.Type)) {
            if ($AzureAD -and $global:Azure.$key.Tenant.Type -eq "Azure AD") { $key }
            if ($AzureADB2C -and $global:Azure.$key.Tenant.Type -eq "Azure AD B2C") { $key }
            if ($All) { $key }
        }
    }
    return $tenantKeys

}