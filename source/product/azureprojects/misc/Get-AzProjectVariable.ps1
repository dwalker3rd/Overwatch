function global:Get-AzProjectConfig {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]


    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Tenant
    )

    function Get-AzProjectVariable {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$false)][string]$Default,
            [Parameter(Mandatory=$false)][string[]]$Suggestions,
            [Parameter(Mandatory=$false)][string[]]$Selections,
            [switch]$AllowNone
        )

        $_selections = @()
        $_selections += $Selections
        if ($AllowNone) {
            $_selections += "None"
        }

        if ($Suggestions.Count -gt 1) {
            Write-Host+ -NoTrace -NoTimestamp "Suggestions: $($Suggestions -join ", ")" -ForegroundColor DarkGray
        }
        if ($AllowNone) {
            Write-Host+ -NoTrace -NoTimestamp "Enter 'None' to deselect $Name" -ForegroundColor DarkGray
        }
        if ([string]::IsNullOrEmpty($Default) -and $Suggestions.Count -eq 1) {
            $Default = $Suggestions[0]
        }

        $showSelections = $true
        do {
            $response = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $Name, $(![string]::IsNullOrEmpty($Default) ? " [$Default]" : ""), ": " -ForegroundColor Gray, Blue, Gray
            $response = Read-Host
            $response = ![string]::IsNullOrEmpty($response) ? $response : $Default
            if ($response -eq "?") { $showSelections = $true }
            if ($showSelections -and $_selections -and $response -notin $_selections) {
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine "  $Name must be one of the following: " -ForegroundColor DarkGray
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
                            Write-Host+ -NoTrace -NoTimestamp $selectionsRow -ForegroundColor DarkGray
                        }
                    }
                }
                $showSelections = $false
            }
        } until ($_selections ? $response -in $_selections : $response -ne $global:emptyString)

        return $response

    }

    function global:Read-AzProjectIni {
        
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Name
        )
        
        $iniContent = Get-Content $iniFile
    
        $value = $iniContent | Where-Object {$_ -like "$Name*"}
        if (![string]::IsNullOrEmpty($value)) {
            return $value.split("=")[1].Trim()
        } else {
            return
        }

    }

    function global:Write-AzProjectIni {
        
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][string]$Value
        )
        
        $iniContent = Get-Content $iniFile -Raw
    
        $valueUpdated = $false
        if (![string]::IsNullOrEmpty($iniContent)) {
            $targetDefinition = [regex]::Match($iniContent,"($Name)\s?=\s?(.*)").Groups[0].Value
            if (![string]::IsNullOrEmpty($targetDefinition)) {
                $iniContent = $iniContent.Replace($targetDefinition,"$Name = $Value")
                Set-Content -Path $iniFile -Value $iniContent.Trim()
                $valueUpdated = $true
            }
        }
        if (!$valueUpdated) {
            Add-Content -Path $iniFile -Value "$Name = $Value"
        }

        return

    }

    Write-Host+

    $tenantKey = Get-AzureTenantKeys -Tenant $Tenant
    Write-Host+ -NoTrace -NoTimestamp "Tenant", " [$tenantKey]", ": " -ForegroundColor Gray, Blue, Gray
    Write-Host+

    $subscriptionId = $global:Azure.$tenantKey.Subscription.Id
    Write-Host+ -NoTrace -NoTimestamp "SubscriptionId", " [$subscriptionId]", ": " -ForegroundColor Gray, Blue, Gray
    Write-Host+

    $tenantId = $global:Azure.$tenantKey.Tenant.Id
    Write-Host+ -NoTrace -NoTimestamp "TenantId", " [$tenantId]", ": " -ForegroundColor Gray, Blue, Gray
    Write-Host+

    $groupNames = $global:Azure.Group.Keys
    $groupName = Get-AzProjectVariable -Name "GroupName" -Suggestions $groupNames
    Write-Host+ -NoTrace -NoTimestamp "GroupName = $groupName" -ForegroundColor DarkGray
    Write-Host+

    $projectNames = 
        foreach ($_groupName in $global:Azure.Group.Keys) {
            $global:Azure.Group.$_groupName.Project.Keys
        }
    $projectName = Get-AzProjectVariable -Name "ProjectName" -Suggestions $projectNames
    Write-Host+ -NoTrace -NoTimestamp "ProjectName = $projectName" -ForegroundColor DarkGray
    Write-Host+

    $resourceGroupName = "$($GroupName)-$($ProjectName)-rg"

    $iniFile = "$($global:Azure.Group.$groupName.Project.$ProjectName.Location.Data)\$ProjectName.ini"
    if (!(Test-Path $iniFile)) {
        New-Item -Path $iniFile -ItemType File | Out-Null
    }

    Write-AzProjectIni -Name Tenant -Value $Tenant
    Write-AzProjectIni -Name SubscriptionId -Value $subscriptionId
    Write-AzProjectIni -Name TenantId -Value $tenantId
    Write-AzProjectIni -Name GroupName -Value $groupName
    Write-AzProjectIni -Name ProjectName -Value $projectName
    Write-AzProjectIni -Name ResourceGroupName -Value $resourceGroupName

    # get/read/update Prefix
    $prefixDefault = Read-AzProjectIni -Name Prefix
    $prefixes = 
        $global:Azure.Group.Keys | 
            Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.Prefix} |
                    Sort-Object -Unique
    $prefixes = $prefixes | Sort-Object -Unique
    $prefix = Get-AzProjectVariable -Name "Prefix" -Suggestions $prefixes -Default $prefixDefault
    Write-Host+ -NoTrace -NoTimestamp "Prefix = $prefix" -ForegroundColor DarkGray
    Write-AzProjectIni -Name Prefix -Value $prefix
    Write-Host+

    # get/read/update ResourceLocation
    $azLocations = Get-AzLocation | Where-Object {$_.providers -contains "Microsoft.Compute"} | 
        Select-Object -Property displayName, location | Sort-Object -Property location
    $resourceLocationDefault = Read-AzProjectIni -Name resourceLocation
    $resourceLocationSuggestions = 
        $global:Azure.Group.Keys | 
            Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.resourceLocation} |
                    Sort-Object -Unique
    $resourceLocationSelections = $azLocations.Location
    $resourceLocation = Get-AzProjectVariable -Name "ResourceLocation" -Suggestions $resourceLocationSuggestions -Selections $resourceLocationSelections -Default $resourceLocationDefault
    Write-Host+ -NoTrace -NoTimestamp "ResourceLocation = $resourceLocation" -ForegroundColor DarkGray
    Write-AzProjectIni -Name ResourceLocation -Value $resourceLocation
    Write-Host+
    
    # get/read/update StorageAccountPerformanceTier
    $storageAccountPerformanceTiers = @("Standard","Premium")
    $storageAccountPerformanceTierDefault = "Standard"
    $storageAccountPerformanceTier = Get-AzProjectVariable -Name "StorageAccountPerformanceTier" -Selections $storageAccountPerformanceTiers -Default $storageAccountPerformanceTierDefault
    Write-Host+ -NoTrace -NoTimestamp "StorageAccountPerformanceTier = $storageAccountPerformanceTier" -ForegroundColor DarkGray
    Write-AzProjectIni -Name StorageAccountPerformanceTier -Value $storageAccountPerformanceTier
    Write-Host+

    # get/read/update StorageAccountSku
    $storageAccountSkus = @("Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS", "Standard_GZRS", "Standard_RAGZRS", "Premium_LRS", "Premium_ZRS")
    $storageAccountSkuDefault = "Standard_LRS"
    $storageAccountSku = Get-AzProjectVariable -Name "StorageAccountSku" -Selections $storageAccountSkus -Default $storageAccountSkuDefault
    Write-Host+ -NoTrace -NoTimestamp "StorageAccountSku = $storageAccountSku" -ForegroundColor DarkGray
    Write-AzProjectIni -Name StorageAccountSku -Value $storageAccountSku
    Write-Host+

    # get/read/update StorageAccountRedundancyConfiguration
    $storageAccountRedundancyConfigurations = @("LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS")
    $storageAccountRedundancyConfigurationDefault = "LRS"
    $storageAccountRedundancyConfiguration = Get-AzProjectVariable -Name "StorageAccountRedundancyConfiguration" -Selections $storageAccountRedundancyConfigurations -Default $storageAccountRedundancyConfigurationDefault
    Write-Host+ -NoTrace -NoTimestamp "StorageAccountRedundancyConfiguration = $storageAccountRedundancyConfiguration" -ForegroundColor DarkGray
    Write-AzProjectIni -Name StorageAccountRedundancyConfiguration -Value $storageAccountRedundancyConfiguration
    Write-Host+

    # get/read/update StorageAccountKind
    $storageAccountKinds = @("StorageV2","BlockBlobStorage","FileStorage","Storage","BlobStorage")
    $storageAccountKindDefault = "BlobStorage"
    $storageAccountKind = Get-AzProjectVariable -Name "StorageAccountKind" -Selections $storageAccountKinds -Default $storageAccountKindDefault
    Write-Host+ -NoTrace -NoTimestamp "StorageAccountKind = $storageAccountKind" -ForegroundColor DarkGray
    Write-AzProjectIni -Name StorageAccountKind -Value $storageAccountKind
    Write-Host+

    # get/read/update VmSize
    $availableVmSizes = Get-AzAvailableVmSizes -ResourceLocation $resourceLocation -HasSufficientQuota
    $vmSizeDefault = (Read-AzProjectIni -Name vmSize) ?? "Standard_D4s_v3"
    $vmSizeSuggestions = @()
    $vmSizeSuggestions +=  
        $global:Azure.Group.Keys | 
            Foreach-Object { $_groupName = $_; $global:Azure.Group.$_groupName.Project.Keys } | 
                Foreach-Object { $_projectName = $_; $global:Azure.Group.$_groupName.Project.$_projectName.vmSize} |
                    Sort-Object -Unique
    $vmSizeSelections = @()
    $vmSizeSelections += $availableVmSizes.Name | Sort-Object
    $vmSize = Get-AzProjectVariable -Name "VmSize" -Suggestions $vmSizeSuggestions -Selections $vmSizeSelections -Default $vmSizeDefault -AllowNone
    Write-Host+ -NoTrace -NoTimestamp "VmSize = $vmSize" -ForegroundColor DarkGray
    Write-AzProjectIni -Name VmSize -Value $vmSize
    Write-Host+

    # need to look at project providers and see if compute is included
    if ($vmSize -ne "None") {

        # get/read/update VmImagePublisher
        $vmImagePublishers = @("microsoft-dsvm")
        $vmImagePublisher = Get-AzProjectVariable -Name "VmImagePublisher" -Suggestions $vmImagePublishers -Selections $vmImagePublishers
        Write-Host+ -NoTrace -NoTimestamp "VmImagePublisher = $vmImagePublisher" -ForegroundColor DarkGray
        Write-AzProjectIni -Name VmImagePublisher -Value $vmImagePublisher
        Write-Host+

        # get/read/update VmImageOffer
        $vmImageOffers = @("linux","windows")
        $vmImageOffer = Get-AzProjectVariable -Name "VmImageOffer" -Suggestions $vmImageOffers -Selections $vmImageOffers
        Write-Host+ -NoTrace -NoTimestamp "VmImageOffer = $vmImageOffer" -ForegroundColor DarkGray
        Write-AzProjectIni -Name VmImageOffer -Value $vmImageOffer
        Write-Host+

        $resourceAdminUsername = "$($Prefix)$($ProjectName)adm"
        Write-AzProjectIni -Name ResourceAdminUsername -Value $resourceAdminUsername

        $authorizedIp = $(curl -s https://api.ipify.org)
        Write-AzProjectIni -Name AuthorizedIp -Value $authorizedIp

        $currentAzureUser = Get-AzureAdUser -Tenant $tenantKey -User (Get-AzContext).Account.Id
        $currentAzureUserId = $currentAzureUser.id
        $currentAzureUserEmail = $currentAzureUser.mail
        Write-AzProjectIni -Name CurrentAzureUserId -Value $currentAzureUserId
        Write-AzProjectIni -Name CurrentAzureUserEmail -Value $currentAzureUserEmail

    }

}

Write-Host+ -Clear
Get-AzProjectConfig -Tenant pathaiforhealth