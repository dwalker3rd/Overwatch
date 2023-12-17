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

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant

    $subscriptionId = $global:Azure.$tenantKey.Subscription.Id
    $tenantId = $global:Azure.$tenantKey.Tenant.Id

    $creds = get-credentials $global:Azure.$tenantKey.Admin.Credentials

    $azureProfile = Connect-AzAccount -Credential $creds -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if (!$azureProfile) {
        $exception = [Microsoft.Azure.Commands.Common.Exceptions.AzPSAuthenticationFailedException]((Get-Error).Exception).InnerException
        if ($exception.DesensitizedErrorMessage -like "MFA*") {
            Write-Host+ -NoTrace "Non-interactive login failed because $($exception.DesensitizedErrorMessage)" -ForegroundColor DarkYellow
            Write-Host+ -NoTrace "Attempting interactive login ..." -ForegroundColor DarkGray
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
                Credentials = "$tenantKey-admin"
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

        Write-Host+ 
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
        [Parameter(Mandatory=$true)][string]$Location
    )

    # $tenantKey = Get-AzureTenantKeys -Tenant $Tenant

    return New-AzResourceGroup -Name $ResourceGroupName -Location $Location

}

function global:New-AzStorageAccount+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [Parameter(Mandatory=$true)][string]$StorageAccountName,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$SKU,
        [Parameter(Mandatory=$true)][string]$Location,
        [Parameter(Mandatory=$true)][bool]$EnableSoftDelete,
        [Parameter(Mandatory=$true)][int]$RetentionDays
    )

    # $tenantKey = Get-AzureTenantKeys -Tenant $Tenant

    $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName $SKU -Location $location

    if ($EnableSoftDelete) {
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
        [Parameter(Mandatory=$true)][ValidateSet("Container","Blob","Off")][string]$Permission
    )

    # $tenantKey = Get-AzureTenantKeys -Tenant $Tenant

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

    $tenantkey = Get-AzureTenantKeys -Tenant $Tenant

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

    return (az ml workspace show --resource-group $ResourceGroupName --name $WorkspaceName | ConvertFrom-Json)

}

function global:Get-AzVmContext {

    [CmdletBinding()]
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

    [CmdletBinding()]
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
        [Parameter(Mandatory=$false,Position=0)][string]$Tenant,
        [switch]$All,
        [switch]$AzureAD,
        [switch]$AzureADB2C
    )

    $tenantKey = $null
    if (![string]::IsNullOrEmpty($Tenant)) {
        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:Azure.$tenantKey) { 
            foreach ($azureTenantKey in (Get-AzureTenantKeys)) {
                if ($Tenant -eq $global:Azure.$azureTenantKey.Tenant.Id) { 
                    $tenantKey = $azureTenantKey
                }
            }
        }
        if ([string]::IsNullOrEmpty($tenantKey)) {
            throw "$tenantKey is not a name/id for a valid/configured Azure tenant."
        }
        return $tenantKey
    }

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


function global:Enable-AzVMExtensionAutomaticUpdate {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$VmName
    )

    $vmParams = @{}
    if (![string]::IsNullOrEmpty($ResourceGroupName)) { $vmParams += @{ ResourceGroupName = $ResourceGroupName } }
    if (![string]::IsNullOrEmpty($VmName)) { $vmParams += @{ VmName = $VmName } }
    $azVMs = Get-AzVM @vmParams

    foreach ($azVM in $azVMs) {

        $vmExtensionParams = @{}
        $vmExtensionParams += @{
            ResourceGroupName = $azVM.ResourceGroupName
            VMName = $azVM.Name
        }
        if (![string]::IsNullOrEmpty($Name)) { $vmExtensionParams += @{ Name = $Name } }
    
        $vmExtensions = Get-AzVmExtension @vmExtensionParams
        foreach ($vmExtension in $vmExtensions) {
            Set-AzVMExtension -ExtensionName $vmExtension.Name `
                -ResourceGroupName $azVM.ResourceGroupName `
                -VMName $azVM.Name `
                -Publisher $vmExtension.Publisher `
                -ExtensionType $vmExtension.ExtensionType `
                -TypeHandlerVersion $vmExtension.TypeHandlerVersion `
                -Location $vmExtension.Location `
                -EnableAutomaticUpgrade $true `
                -NoWait `
                -ErrorAction SilentlyContinue
        }
    
    }

}

function Invoke-ComputerCommand {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding(
        # SupportsShouldProcess,
        # ConfirmImpact = "High"
    )]
    param(
        [Parameter(Mandatory=$true,Position=0)][ValidateSet("Start","Stop")][string]$Command,
        [Parameter(Mandatory=$true,Position=1)][string]$ComputerName,
        [Parameter(Mandatory=$false)][string]$Tenant,
        [switch]$NoWait
    )

    function Get-PowerStateColor {
        param (
            [Parameter(Mandatory=$true,Position=0)]$PowerState
        )
        $powerStateColor = switch ($PowerState) {
            {$_ -like "VM run*"} { "DarkGreen" }
            {$_ -like "VM start*"} { "DarkGreen" }
            {$_ -like "VM deallocat*"} { "DarkRed" }
            default { "DarkGray" }
        }
        return $powerStateColor
    }

    # if ($Command -eq "Stop") {
    #     if (!$PSCmdlet.ShouldProcess($ComputerName)) { return }
    #     Write-Host+
    # }

    $Tenant = ![string]::IsNullOrEmpty($Tenant) ? $Tenant : ($global:Azure.$($global:Azure.Home).Tenant.Id)

    $azContext = Get-AzContext
    if (!$azContext.Subscription) {
        Connect-AzAccount+ -Tenant $Tenant
    }

    $powerStateTarget = switch ($Command) { "Start" { "VM running" }; "Stop" { "VM deallocated" }}

    $azVm = Get-AzVM -Name $ComputerName -Status
    $resourceGroupName = $azVm.ResourceGroupName
    $powerState = $azVm.PowerState
    $powerStateColor = Get-PowerStateColor -PowerState $powerState

    Write-Host+
    Write-Host+ -NoTrace "$Command-Computer"
    $message = "<$indent$ComputerName <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    $message = "<$indent  $($Command -eq "Start" ? "Starting" : "Stopping") $ComputerName <.>42> $powerState$($emptyString.PadLeft(20-$powerState.Length," "))"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$powerStateColor

    $result = @{ 
        IsSuccessStatusCode = $true
        StatusCode = $NoWait ? "Accepted" : "Succeeded" 
    }

    if ($powerState -ne $powerStateTarget) {

        $commandExpression = "$Command-AzVM -ResourceGroupName `"$resourceGroupName`" -Name `"$ComputerName`" -NoWait"
        # if ($NoWait) { $commandExpression += " -NoWait"}
        if ($Command -eq "Stop") { $commandExpression += " -Force"}
        $result = Invoke-Expression $commandExpression
    
        $timer = [Diagnostics.Stopwatch]::StartNew()

        $azVm = Get-AzVM -Name $ComputerName -Status
        $reverseLineFeedCount = $powerState -eq $azVm.PowerState ? 1 : 0
        $powerState = $azVm.PowerState
        $powerStateColor = Get-PowerStateColor -PowerState $powerState
        $message = "<$indent  $($Command -eq "Start" ? "Starting" : "Stopping") $ComputerName <.>42> $powerState$($emptyString.PadLeft(20-$powerState.Length," "))"
        Write-Host+ -NoTrace -ReverseLineFeed $reverseLineFeedCount -Parse $message -ForegroundColor Gray,DarkGray,$powerStateColor

        do {
            Start-Sleep -Seconds 5
            $azVm = Get-AzVM -Name $ComputerName -Status
            $reverseLineFeedCount = $powerState -eq $azVm.PowerState ? 1 : 0
            $powerState = $azVm.PowerState
            $powerStateColor = Get-PowerStateColor -PowerState $powerState
            $message = "<$indent  $($Command -eq "Start" ? "Starting" : "Stopping") $ComputerName <.>42> $powerState$($emptyString.PadLeft(20-$powerState.Length," "))"
            Write-Host+ -NoTrace -ReverseLineFeed $reverseLineFeedCount -Parse $message -ForegroundColor Gray,DarkGray,$powerStateColor
        } until ($powerState -eq $powerStateTarget -or ([math]::Round($timer.Elapsed.TotalSeconds,0) -gt (New-TimeSpan -Minutes 5).TotalSeconds))

        $timer.Stop()

        if ($Command -eq "Start") {

            $timer = [Diagnostics.Stopwatch]::StartNew()

            do {
                Start-Sleep -Seconds 5
                $pass = $false
                # ensure that node is reachable via network and psremoting
                if ((Test-NetConnection+ -ComputerName $ComputerName -NoHeader).Result -notcontains "Fail") {
                    if ((Test-PSRemoting -ComputerName $ComputerName -NoHeader).Result -notcontains "Fail") {
                        $pass = $true
                    }
                }
            } until ($pass -or ([math]::Round($timer.Elapsed.TotalSeconds,0) -gt (New-TimeSpan -Minutes 5).TotalSeconds))

            $timer.Stop()    

        }
    }

    $statusText = $powerState -eq $powerStateTarget ? "SUCCESS" : "FAIL"
    $statusColor = switch ($statusText) {
        "SUCCESS" { "DarkGreen" }
        "FAIL" { "DarkRed" }
        default { "DarkGray" }
    }
    $message = "<$indent$ComputerName <.>48> $statusText"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$statusColor
    Write-Host+

    return $result
}

function global:Start-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$NoWait
    )

    return Invoke-ComputerCommand -Command Start -ComputerName $ComputerName -NoWait:$NoWait.IsPresent

}
Set-Alias -Name Start-VM -Value Stop-Computer -Scope Global
Set-Alias -Name startVM -Value Stop-Computer -Scope Global

function global:Stop-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$NoWait
    )

    return Invoke-ComputerCommand -Command Stop -ComputerName $ComputerName -NoWait:$NoWait.IsPresent

}
Set-Alias -Name Stop-VM -Value Stop-Computer -Scope Global
Set-Alias -Name stopVM -Value Stop-Computer -Scope Global

function global:Get-AzDisk+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$VmName,
        [Parameter(Mandatory=$false)][AllowNull()][ValidateSet("Attached","Unattached","Reserved")][string[]]$DiskState
    )

    $params = @{}
    if (![string]::IsNullOrEmpty($Name)) { $params += @{ Name = $Name} }
    if (![string]::IsNullOrEmpty($ResourceGroupName)) { $params += @{ ResourceGroupName = $ResourceGroupName} }

    $managedDisks = Get-AzDisk @params
    if (![string]::IsNullOrEmpty($VmName)) {
        $managedDisks = $managedDisks | Where-Object { ($_.ManagedBy -split "/")[-1] -eq $VmName }
    }
    if (![string]::IsNullOrEmpty($DiskState)) {
        $managedDisks = $managedDisks | Where-Object { $_.DiskState -in $DiskState }
    }

    return $managedDisks

}

function global:Show-AzDisk+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$VmName,
        [Parameter(Mandatory=$false)][AllowNull()][ValidateSet("Attached","Unattached","Reserved")][string[]]$DiskState
    )

    $params = @{}
    if (![string]::IsNullOrEmpty($Name)) { $params += @{ Name = $Name} }
    if (![string]::IsNullOrEmpty($ResourceGroupName)) { $params += @{ ResourceGroupName = $ResourceGroupName} }
    if (![string]::IsNullOrEmpty($VmName)) { $params += @{ VmName = $VmName} }
    if (![string]::IsNullOrEmpty($DiskState)) { $params += @{ DiskState = $DiskState} }

    $managedDisks = Get-AzDisk+ @params

    $managedDisks | Select-Object -Property $AzureView.Disk.Default | Sort-object -property DiskState, ResourceGroupName, ManagedBy | Format-Table -GroupBy DiskState

    $_diskStateNotFound = $false
    foreach ($_diskState in $DiskState) {
        Write-Host+
        if ($managedDisks.DiskState -notcontains $_diskState) {
            $message = "No $($_diskstate.ToLower()) managed disks could be found."
            Write-Host+ -NoTrace $message -ForegroundColor DarkRed
            $_diskStateNotFound = $true
        }
    }

    if ($_diskStateNotFound) { Write-Host+ }

}

function global:Remove-AzDisk+ {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ResourceGroupName,
        [Parameter(Mandatory=$false)][string]$VmName,
        [Parameter(Mandatory=$false)][AllowNull()][ValidateSet("Attached","Unattached","Reserved")][string[]]$DiskState
    )

    $azContext = Get-AzContext
    $managedDiskScope = "Subscription `"$($azContext.Subscription.Name)`""
    if (![string]::IsNullOrEmpty($ResourceGroupName)) { $managedDiskScope = "Resource group `"$ResourceGroupName`"" }
    if (![string]::IsNullOrEmpty($Name)) { $managedDiskScope = $null }

    $params = @{}
    if (![string]::IsNullOrEmpty($Name)) { $params += @{ Name = $Name} }
    if (![string]::IsNullOrEmpty($ResourceGroupName)) { $params += @{ ResourceGroupName = $ResourceGroupName} }
    if (![string]::IsNullOrEmpty($VmName)) { $params += @{ VmName = $VmName} }
    if (![string]::IsNullOrEmpty($DiskState)) { $params += @{ DiskState = $DiskState} }

    $managedDisks = Get-AzDisk+ @params

    $attachedManagedDisks = $managedDisks | Where-Object { $_.DiskState -eq "Attached" -and $null -ne $_.ManagedBy }
    $unattachedManagedDisks = $managedDisks | Where-Object { $_.DiskState -eq "Unattached" -and $null -eq $_.ManagedBy }

    Write-Host+

    if (!$managedDisks) {
        Write-Host+ -NoTrace -NoTimestamp "Managed disk `"$Name`" could not be found." -ForegroundColor DarkRed
        Write-Host+
        return
    }

    if ($managedDisks.DiskState -contains "Attached") {
        Write-Host+ -NoTrace -NoTimestamp "Note: Only managed disks which are UNATTACHED can be deleted." -ForegroundColor DarkGray
    }

    if (!$unattachedManagedDisks) {
        if (!$managedDiskScope) {
            $attachedManagedDisks | Select-Object -Property $AzureView.Disk.Default | Format-Table
            Write-Host+ -NoTrace -NoTimestamp "Managed disk `"$Name`" is ATTACHED and cannot be deleted." -ForegroundColor DarkRed
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "No unattached managed disks in $($managedDiskScope.ToLower())" -ForegroundColor DarkRed
        }
        Write-Host+
        return
    }

    Write-Host+ -NoTrace -NoTimestamp "The following managed disks are UNATTACHED and will be DELETED."

    $unattachedManagedDisks | Select-Object -Property $AzureView.Disk.Default | Select-Object -ExcludeProperty ManagedBy | Format-Table
    
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine "Continue (Y/N)? "
    $response = Read-Host
    if ($response.ToUpper().Substring(0,1) -ne "Y") {
        Write-Host+ -NoTrace -NoTimestamp "Remove-AzDisk+ cancelled." -ForegroundColor DarkGray
        Write-Host+
        return
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 2
        Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft(20,"`b"))$($emptyString.PadLeft(20," "))"
        Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 3
    }
    
    Set-CursorInvisible

    Write-Host+
    if (![string]::IsNullOrEmpty($managedDiskScope)) {
        $message = "<$managedDiskScope <.>66> DELETING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
    }

    $indent = ![string]::IsNullOrEmpty($managedDiskScope) ? "  " : ""

    $deleteErrors = $false
    foreach ($unattachedManagedDisk in $unattachedManagedDisks) {
        if($unattachedManagedDisk.DiskState -eq "Unattached" -and $null -eq $unattachedManagedDisk.ManagedBy) {

            $message = "<$indent$($unattachedManagedDisk.Name.ToLower()) <.>56> DELETING"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
    
            $result = $unattachedManagedDisk | Remove-AzDisk -Force
    
            if ($result.Status -eq "Succeeded") {
                $message = "$($emptyString.PadLeft(9,"`b")) DELETED $($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 
            }
            else {
                $deleteErrors = $true
                $message = "$($emptyString.PadLeft(9,"`b")) ERROR   $($emptyString.PadLeft(8," "))"
                Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkRed
                if ($result.Error) {
                    Write-Host+ -NoTrace -NoTimestamp $result.Error -ForegroundColor DarkRed
                }
            }
        }
    }

    if (![string]::IsNullOrEmpty($managedDiskScope)) {
        $message = "<$managedDiskScope <.>66> $($deleteErrors ? "FAILED" : "SUCCESS")"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,($deleteErrors ? "DarkRed" : "DarkGreen")
    }
    Write-Host+

    Set-CursorVisible

}

function global:Show-CloudStatus {

    [CmdletBinding()]
    param()

    $azContext = Get-AzContext

    Write-Host+ -NoTrace $azContext.Environment.Name, "Status", (Format-Leader -Length 39 -Adjust $azContext.Environment.Name.Length), "PENDING" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGray

    # Write-Host+ -NoTrace "  Subscription:", $azContext.Subscription.Name -ForegroundColor DarkGray

    $unattachedManagedDiskGroups = Get-AzDisk+ -DiskState Unattached | Group-Object -Property ResourceGroupName
    if ($unattachedManagedDiskGroups) {
        foreach ($unattachedManagedDiskGroup in $unattachedManagedDiskGroups) {
            $message = "<  $($unattachedManagedDiskGroup.Count) unattached managed disk$($unattachedManagedDiskGroup.Count -ne 1 ? "s": $null) <.>42> REVIEW"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkYellow
        }
        Write-Host+ -NoTrace "    * Review with Show-AzDisk+" -ForegroundColor DarkGray
    }

    Write-Host+ -NoTrace $azContext.Environment.Name, "Status", (Format-Leader -Length 39 -Adjust $azContext.Environment.Name.Length), "READY" -ForegroundColor DarkBlue,Gray,DarkGray,DarkGreen

}