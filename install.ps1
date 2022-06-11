#Requires -RunAsAdministrator
#Requires -Version 7

$emptyString = ""

. $PSScriptRoot\source\core\definitions\classes.ps1
. $PSScriptRoot\source\core\definitions\catalog.ps1
. $PSScriptRoot\source\core\services\services-overwatch-loadearly.ps1

function Copy-File {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [switch]$Quiet,
        [switch]$ConfirmOverwrite
    )
    # if (!$Destination) {
    #     $Destination = $Path.replace("\source","")
    #     $Destination = $Destination.replace("\core","")
    #     $Destination = $Destination.replace("\product","")
    #     $Destination = $Destination.replace("-template","")
    # }
    if (Test-Path -Path $Path) {
        $overwrite = $true
        if ($ConfirmOverwrite -and (Test-Path -Path $Destination -PathType Leaf)) {
            Write-Host+ -NoTrace -NoTimeStamp -NoNewLine "Overwrite $($Destination)? [Y] Yes [N] No (default is `"No`"): " -ForegroundColor DarkYellow
            $overwrite = (Read-Host) -eq "Y" 
        }
        if ($overwrite) {
            Copy-Item -Path $Path $Destination
            if (!$Quiet) {
                Split-Path -Path $Path -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "Copied $_ to $Destination" -ForegroundColor DarkGray}
            }
        }
        else {
            if (!$Quiet) {
                Split-Path -Path $Path -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "[NOOVERWRITE] Not copying $_" -ForegroundColor DarkGray}
            }
        }
    }
}

function Remove-File {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [switch]$Quiet
    )
    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path
        if (!$Quiet) {Write-Host+ -NoTrace -NoTimestamp "Deleted $Path" -ForegroundColor Red}
    }
}

function Install-Product {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context
    )
    $productToInstall = Get-Product $Context -ResetCache
    if (Test-Path -Path $PSScriptRoot\install\install-product-$($productToInstall.Id).ps1) {. $PSScriptRoot\install\install-product-$($productToInstall.Id).ps1}
}

function Install-Provider {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$ProviderName
    )
    $providerToInstall = Get-Provider $ProviderName -ResetCache
    if (Test-Path -Path $PSScriptRoot\install\install-provider-$($providerToInstall.Id).ps1) {. $PSScriptRoot\install\install-provider-$($providerToInstall.Id).ps1}
}

Write-Host+ -Clear

$overwatchInstallLocation = $PSScriptRoot

#region INSTALLATIONS

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Discovery" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "---------" -ForegroundColor DarkGray
    $installedOperatingSystem = $((Get-CimInstance -ClassName Win32_OperatingSystem).Name -split "\|")[0]
    if ($installedOperatingSystem -like "*Windows Server*") {
        $installedOperatingSystem = "WindowsServer"
    }
    else {
        throw "$installedOperatingSystem is not an Overwatch-supported operating system."
    }
    Write-Host+ -NoTrace -NoTimestamp "Operating System: ","$installedOperatingSystem" -ForegroundColor Gray, Blue
    $operatingSystemId = $installedOperatingSystem

    $installedPlatforms = @()
    $services = Get-Service
    if ($services.Name -contains "tabsvc_0") {$installedPlatforms += "TableauServer"}
    if ($services.Name -contains "AlteryxService") {$installedPlatforms += "AlteryxServer"}
    Write-Host+ -NoTrace -NoTimestamp "Platform: ","$($installedPlatforms -join ", ")" -ForegroundColor Gray, Blue

#endregion INSTALLATIONS
#region LOAD SETTINGS

    Write-Host+ -MaxBlankLines 1
    $settingsFileMissing = $false

    $defaultSettings = "$PSScriptRoot\install\data\defaultSettings.ps1"
    if (Test-Path -Path $defaultSettings) {
        . $defaultSettings
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp "No default settings in $defaultSettings" -ForegroundColor DarkGray
        $settingsFileMissing = $true
    }

    $installSettings = "$PSScriptRoot\install\data\installSettings.ps1"
    if (Test-Path -Path $installSettings) {
        . $installSettings
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        $settingsFileMissing = $true
    }    

    if ($settingsFileMissing) {Write-Host+}

#endregion LOAD SETTINGS

Write-Host+ -MaxBlankLines 1
Write-Host+ -NoTrace -NoTimestamp "Installation Questions" -ForegroundColor DarkGray
Write-Host+ -NoTrace -NoTimestamp "----------------------" -ForegroundColor DarkGray

#region PLATFORM ID

    # if ($installedPlatforms.count -eq 1) {
        # $platformId = $installedPlatforms[0]
    # }
    # else {
        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Select Platform ", "$($installedPlatforms ? "[$($installedPlatforms -join ", ")] " : $null)", ": " -ForegroundColor Gray, Blue, Gray 
            $platformIdResponse = Read-Host
            $platformId = ![string]::IsNullOrEmpty($platformIdResponse) ? $platformIdResponse : $platformId
            Write-Host+ -NoTrace -NoTimestamp "Platform ID: $platformId" -IfDebug -ForegroundColor Yellow
            if ($installedPlatforms -notcontains $platformId) {
                Write-Host+ -NoTrace -NoTimestamp "Platform must be one of the following: $($installedPlatforms -join ", ")" -ForegroundColor Red
            }
        } until ($installedPlatforms -contains $platformId)
    # }

#endregion PLATFORM ID
#region PLATFORM INSTALL LOCATION

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Install Location ", "$($platformInstallLocation ? "[$platformInstallLocation] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
        $platformInstallLocationResponse = Read-Host
        $platformInstallLocation = ![string]::IsNullOrEmpty($platformInstallLocationResponse) ? $platformInstallLocationResponse : $platformInstallLocation
        Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow
        if (!(Test-Path -Path $platformInstallLocation)) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find path '$platformInstallLocation' because it does not exist." -ForegroundColor Red
            $platformInstallLocation = $null
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The path '$platformInstallLocation' is valid." -IfVerbose -ForegroundColor DarkGreen
        }
        $platformInstallLocationBin = switch ($platformId) {
            "TableauServer" {"$platformInstallLocation\packages\bin*"}
            "AlteryxServer" {"$platformInstallLocation\bin"}
        }
        if (!(Test-Path -Path $platformInstallLocationBin)) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find the $platformId bin directory, '$platformInstallLocationBin', because it does not exist." -ForegroundColor Red
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The bin directory for $platformId, '$platformInstallLocationBin', is valid." -IfVerbose -ForegroundColor DarkGreen
        }
    } until ($platformInstallLocation)
    Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTALL LOCATION
#region PIP

    $pipLocation = switch ($platformId) {
        "AlteryxServer" {"$platformInstallLocation\Miniconda3\envs\DesignerBaseTools_vEnv\Scripts"}
        default {$null}
    }

#region PIP
#region PLATFORM INSTANCE URL

do {
    try {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance URI ", "$($platformInstanceUri ? "[$platformInstanceUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        $platformInstanceUriResponse = Read-Host
        $platformInstanceUri = ![string]::IsNullOrEmpty($platformInstanceUriResponse) ? $platformInstanceUriResponse : $platformInstanceUri
        $platformInstanceUri = [System.Uri]::new($platformInstanceUri)
    }
    catch {
        Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid URI format" -ForegroundColor Red
        $platformInstanceUri = $null
    }
    if ($platformInstanceUri) {
        try {
            Invoke-WebRequest $platformInstanceUri -Method Head | Out-Null
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] Response from '$platformInstanceUri'" -IfVerbose -ForegroundColor DarkGreen
        }
        catch
        {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] No response from '$platformInstanceUri'" -ForegroundColor Red
            $platformInstanceUri = $null
        }
    }
} until ($platformInstanceUri)
Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceUri" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE URL
#region PLATFORM INSTANCE URL

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Domain ", "$($platformInstanceDomain ? "[$platformInstanceDomain]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        $platformInstanceDomainResponse = Read-Host
        $platformInstanceDomain = ![string]::IsNullOrEmpty($platformInstanceDomainResponse) ? $platformInstanceDomainResponse : $platformInstanceDomain
        if (![string]::IsNullOrEmpty($platformInstanceDomain) -and $platformInstanceUri.Host -notlike "*$platformInstanceDomain") {
            Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid domain. Domain must match the platform instance URI" -ForegroundColor Red
            $platformInstanceDomain = $null
        }
    } until ($platformInstanceDomain)
    Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceDomain" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE URL
#region PLATFORM INSTANCE ID

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance ID ", "$($platformInstanceId ? "[$platformInstanceId] " : "[$($platformInstanceUri.Host -replace "\.","-")]")", ": " -ForegroundColor Gray, Blue, Gray
        $platformInstanceIdResponse = Read-Host
        $platformInstanceId = ![string]::IsNullOrEmpty($platformInstanceIdResponse) ? $platformInstanceIdResponse : $platformInstanceId
        if ([string]::IsNullOrEmpty($platformInstanceId)) {
            Write-Host+ -NoTrace -NoTimestamp "NULL: Platform Instance ID is required" -ForegroundColor Red
            $platformInstanceId = $null
        }
        if ($platformInstanceId -notmatch "^[a-zA-Z0-9\-]*$") {
            Write-Host+ -NoTrace -NoTimestamp "INVALID CHARACTER: letters, digits and hypen only" -ForegroundColor Red
            $platformInstanceId = $null
        }
    } until ($platformInstanceId)
    Write-Host+ -NoTrace -NoTimestamp "Platform Instance ID: $platformInstanceId" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE ID
#region IMAGES

    do {
        try {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Images URL ", "$($imagesUri ? "[$imagesUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            $imagesUriResponse = Read-Host
            $imagesUri = ![string]::IsNullOrEmpty($imagesUriResponse) ? $imagesUriResponse : $imagesUri
            $imagesUri = [System.Uri]::new($imagesUri)
        }
        catch {
            Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid URI format" -ForegroundColor Red
            $imagesUri = $null
        }
        if ($imagesUri) {
            try {
                $imagesUriNoEndingSlash = $imagesUri.AbsoluteUri.Substring($imagesUri.AbsoluteUri.Length-1,1) -eq "/" ? $imagesUri.AbsoluteUri.Substring(0,$imagesUri.AbsoluteUri.Length-1) : $imagesUri
                $imgFile = "$imagesUriNoEndingSlash/windows_server.png"
                Invoke-WebRequest "$imgFile" -Method Head | Out-Null
                Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] Overwatch image files found at '$imgFile'" -IfVerbose -ForegroundColor DarkGreen
            }
            catch
            {
                Write-Host+ -NoTrace -NoTimestamp "[ERROR] Overwatch image files not found at '$imgFile'" -ForegroundColor Red
                $imagesUri = $null
            }
        }
    } until ($imagesUri)
    Write-Host+ -NoTrace -NoTimestamp "Public URI for images: $imagesUri" -IfDebug -ForegroundColor Yellow

#endregion IMAGES
#region LOCAL DIRECTORIES

    $requiredDirectories = @("data","definitions","docs","img","initialize","install","logs","preflight","postflight","providers","services","temp","data\$platformInstanceId")

    $missingDirectories = @()
    foreach ($requiredDirectory in $requiredDirectories) {
        if (!(Test-Path "$PSScriptRoot\$requiredDirectory")) { $missingDirectories += "$PSScriptRoot\$requiredDirectory" }
    }
    if ($missingDirectories) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Local Directories" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "-----------------" -ForegroundColor DarkGray

        foreach ($missingDirectory in $missingDirectories) {
            New-Item -ItemType Directory -Path $missingDirectory -Force
        }

    }

#endregion LOCAL DIRECTORIES
#region PRODUCTS

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Select Products" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "---------------" -ForegroundColor DarkGray
    
    $productsSelected = @("Command")
    $productSpecificServices = @()
    $productDependencies = @()
    foreach ($key in $global:Catalog.Product.Keys) {
        $product = $global:Catalog.Product.$key
        if ([string]::IsNullOrEmpty($product.Installation.Flag) -or ($product.Installation.Flag -notcontains "NoInstall" -and $product.Installation.Flag -notcontains "NoPrompt")) {
            if ([string]::IsNullOrEmpty($product.Installation.Prerequisite.Platform) -or $product.Installation.Prerequisite.Platform -contains $platformId) {
                $productResponseDefault = $product.id -in $productIds ? "Y" : "N"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $($product.id) ","[$productResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
                $productResponse = Read-Host
                if ([string]::IsNullOrEmpty($productResponse)) {$productResponse = $productResponseDefault}
                if ($productResponse -eq "Y") {
                    $productsSelected += $product.id
                    if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Product)) {
                        foreach ($prerequisiteProduct in $product.Installation.Prerequisite.Product) {
                            if ($productsSelected -notcontains $prerequisiteProduct) {
                                $productsSelected += $prerequisiteProduct
                                $productDependencies += @{
                                    Product = $product.id
                                    Dependency = $prerequisiteProduct
                                }
                            }
                        }
                    }
                    if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Service)) {
                        foreach ($prerequisiteService in $product.Installation.Prerequisite.Service) {
                            if ($prerequisiteService -notin $productSpecificServices) {
                                $productSpecificServices += $prerequisiteService
                            }
                        }
                    }
                }
            }
        }
    }
    $productIds = $productsSelected
    Write-Host+ -NoTrace -NoTimestamp "Products: $($productIds -join ", ")" -IfDebug -ForegroundColor Yellow

    if ($productDependencies) {
        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Other Products" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "--------------" -ForegroundColor DarkGray
        foreach ($productDependency in $productDependencies) {
            Write-Host+ -NoTrace -NoTimestamp $($productDependency.Dependency),"(required by $($productDependency.Product))" -ForegroundColor Gray,DarkGray
        }
        Write-Host+
    }

#endregion PRODUCTS
#region PROVIDERS

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace -NoTimestamp "Select Providers" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "----------------" -ForegroundColor DarkGray
    $_providerIds = @("Views")
    $providerList = $global:Catalog.Provider.Keys | Where-Object {$_ -ne "Views"}
    foreach ($provider in $providerList) {
        $providerResponseDefault = $provider -in $providerIds ? "Y" : "N"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $provider ","[$providerResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
        $providerResponse = Read-Host
        if ([string]::IsNullOrEmpty($providerResponse)) {$providerResponse = $providerResponseDefault}
        if ($providerResponse -eq "Y") {
            $_providerIds += $provider
        }

    }
    $providerIds = $_providerIds
    Write-Host+ -NoTrace -NoTimestamp "Providers: $($providerIds -join ", ")" -IfDebug -ForegroundColor Yellow

#endregion PROVIDERS
#region SAVE SETTINGS

    if (Test-Path $installSettings) {Clear-Content -Path $installSettings}
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $installSettings
    "Param()" | Add-Content -Path $installSettings
    "`$operatingSystemId = ""$operatingSystemId""" | Add-Content -Path $installSettings
    "`$platformId = ""$platformId""" | Add-Content -Path $installSettings
    "`$platformInstallLocation = ""$platformInstallLocation""" | Add-Content -Path $installSettings
    "`$platformInstanceId = ""$platformInstanceId""" | Add-Content -Path $installSettings
    "`$productIds = @('$($productIds -join "', '")')" | Add-Content -Path $installSettings
    "`$providerIds = @('$($providerIds -join "', '")')" | Add-Content -Path $installSettings
    "`$imagesUri = [System.Uri]::new(""$imagesUri"")" | Add-Content -Path $installSettings
    "`$platformInstanceUri = [System.Uri]::new(""$platformInstanceUri"")" | Add-Content -Path $installSettings
    "`$platformInstanceDomain = ""$platformInstanceDomain""" | Add-Content -Path $installSettings

#endregion SAVE SETTINGS
#region FILES

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Configuration Files" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "-------------------" -ForegroundColor DarkGray

    #region CORE

        $files = (Get-ChildItem $PSScriptRoot\source\core -File -Recurse).VersionInfo.FileName
        foreach ($file in $files) { Copy-File $file $file.replace("\source\core","")}

    #endregion CORE
    #region ENVIRON

        $sourceFile = "$PSScriptRoot\source\environ\environ-template.ps1"
        $targetFile = "$PSScriptRoot\environ.ps1"
        $targetFileExists = Test-Path $targetFile
        $environFile = Get-Content -Path $sourceFile
        $environFile = $environFile -replace "<operatingSystemId>", ($operatingSystemId -replace " ","")
        $environFile = $environFile -replace "<platformId>", ($platformId -replace " ","")
        $environFile = $environFile -replace "<overwatchInstallLocation>", $overwatchInstallLocation
        $environFile = $environFile -replace "<platformInstanceId>", $platformInstanceId
        $environFile = ($environFile -replace "<productIds>", "'$($productIds -join "', '")'") -replace "'",'"'
        $environFile = ($environFile -replace "<providerIds>", "'$($providerIds -join "', '")'") -replace "'",'"'
        $environFile = $environFile -replace "<imagesUri>", $imagesUri
        $environFile = $environFile -replace "<pipLocation>", $pipLocation
        $environFile | Set-Content -Path $targetFile
        Write-Host+ -NoTrace -NoTimestamp "$($targetFileExists ? "Updated" : "Created") $targetFile" -ForegroundColor DarkGreen

        . $PSScriptRoot\environ.ps1

    #endregion ENVIRON
    #region PLATFORM INSTANCE DEFINITIONS

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1

        $isSourceFileTemplate = $false
        $sourceFile = "$PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1"
        if (!(Test-Path $sourceFile) -or (Get-Content -Path $sourceFile | Select-String "<platformId>" -SimpleMatch -Quiet)) {
            $sourceFile = "$PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$platformId-template.ps1"
            $isSourceFileTemplate = $true
        }
        $platformInstanceDefinitionsFile = Get-Content -Path $sourceFile
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformId>", ($platformId -replace " ","")
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstallLocation>", $platformInstallLocation
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceId>", $platformInstanceId
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceUrl>", $platformInstanceUri
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceDomain>", $platformInstanceDomain
        $platformInstanceDefinitionsFile | Set-Content -Path $PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1
        Write-Host+ -NoTrace -NoTimestamp "$($isSourceFileTemplate ? "Created" : "Updated") $PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1" -ForegroundColor DarkGreen

    #endregion PLATFORM INSTANCE DEFINITIONS
    #region COPY

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $PSScriptRoot\services
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $PSScriptRoot\services

        foreach ($productSpecificService in $productSpecificServices) {
            Copy-File $PSScriptRoot\source\services\$($productSpecificService.ToLower())\definitions-service-$($productSpecificService.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-service-$($productSpecificService.ToLower()).ps1 -ConfirmOverwrite
            Copy-File $PSScriptRoot\source\services\$($productSpecificService.ToLower())\services-$($productSpecificService.ToLower()).ps1 $PSScriptRoot\services\services-$($productSpecificService.ToLower()).ps1
            $definitionsServices = "$PSScriptRoot\definitions\definitions-services.ps1"
            $contentLine1 = ". `$definitionsPath\definitions-service-$($productSpecificService.ToLower()).ps1"
            $contentLine2 = ". `$servicesPath\services-$($productSpecificService.ToLower()).ps1"
            if (!(Select-String -Path $definitionsServices -Pattern $contentLine1 -SimpleMatch -Quiet)) {
                Add-Content -Path $definitionsServices -Value $contentLine1
                Add-Content -Path $definitionsServices -Value $contentLine2
            }
        }

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformInstanceId).ps1

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platforminstance-$($platformInstanceId).ps1
        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platforminstance-$($platformInstanceId).ps1

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platforminstance-$($platformInstanceId).ps1
        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platforminstance-$($platformInstanceId).ps1

        foreach ($product in $productIds) {
            Copy-File $PSScriptRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $PSScriptRoot\install\install-product-$($product.ToLower()).ps1
            Copy-File $PSScriptRoot\source\product\$($product.ToLower())\uninstall-product-$($product.ToLower()).ps1 $PSScriptRoot\install\uninstall-product-$($product.ToLower()).ps1
            Copy-File $PSScriptRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.ToLower()).ps1 -ConfirmOverwrite
            Copy-File $PSScriptRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $PSScriptRoot\$($product.ToLower()).ps1
        }      
        foreach ($provider in $providerIds) {
            Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\install-provider-$($provider.ToLower()).ps1
            Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\uninstall-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\uninstall-provider-$($provider.ToLower()).ps1
            Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-provider-$($provider.ToLower()).ps1 -ConfirmOverwrite
            Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $PSScriptRoot\providers\provider-$($provider.ToLower()).ps1
        }

    #endregion COPY
#endregion FILES
#region MODULES-PACKAGES

    Write-Host+ -MaxBlankLines 1
    $message = "Powershell modules/packages : INSTALLING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    if (!(Get-PackageSource -ProviderName PowerShellGet)) {
        Register-PackageSource -Name PSGallery -Location "https://www.powershellgallery.com/api/v2" -ProviderName PowerShellGet -ErrorAction SilentlyContinue | Out-Null
    }
    $requiredModules = @("PsIni")
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ErrorAction SilentlyContinue | Out-Null)) {
            Install-Module -Name $module -ErrorAction SilentlyContinue | Out-Null
            Import-Module -Name $module -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (!(Get-PackageSource -ProviderName NuGet -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name Nuget -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -ErrorAction SilentlyContinue | Out-Null
    }
    $requiredPackages = @("Portable.BouncyCastle","MimeKit","MailKit")
    foreach ($package in $requiredPackages) {
        if (!(Get-Package -Name $package -ErrorAction SilentlyContinue)) {
            Install-Package -Name $package -SkipDependencies -Force | Out-Null
        }
    }

    $message = "$($emptyString.PadLeft(10,"`b"))INSTALLED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion MODULES-PACKAGES
#region REMOVE CACHE

    Remove-File "$PSScriptRoot\data\$($platformInstanceId.ToLower())\*.cache" -Quiet

#endregion REMOVE CACHE
#region CREDENTIALS

    . $PSScriptRoot\services\vault.ps1
    . $PSScriptRoot\services\credentials.ps1

    $message = "Admin Credentials : VALIDATING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    if (!$(Test-Credentials -NoValidate "localadmin-$platformInstanceId")) { 
        Write-Host+
        Write-Host+

        Request-Credentials -Message "    Enter the local admin credentials" -Prompt1 "    User" -Prompt2 "    Password" | Set-Credentials "localadmin-$($global:Platform.Instance)"
        
        Write-Host+
        $message = "Credentials : VALID"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGreen
        Write-Host+
    }
    else {
        $message = "$($emptyString.PadLeft(10,"`b"))VALID     "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion CREDENTIALS
#region INITIALIZE OVERWATCH

    $message = "Overwatch : INITIALIZING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    psPref -xpref -xpostf -xwhp -Quiet

    $global:Product = @{Id="Install"}
    . $PSScriptRoot\definitions.ps1

    psPref -Quiet

    $message = "$($emptyString.PadLeft(12,"`b"))INITIALIZED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion INITIALIZE OVERWATCH
#region REMOTE DIRECTORIES

    $requiredDirectories = @("data\$platformInstanceId")

    $missingDirectories = @()
    foreach ($node in (pt nodes -k)) {
        $remotePSScriptRoot = "\\$node\$($PSScriptRoot.Replace(":","$"))"
        foreach ($requiredDirectory in $requiredDirectories) {
            if (!(Test-Path "$remotePSScriptRoot\$requiredDirectory")) { $missingDirectories += "$remotePSScriptRoot\$requiredDirectory" }
        }
    }
    if ($missingDirectories) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Remote Directories" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "------------------" -ForegroundColor DarkGray

        foreach ($missingDirectory in $missingDirectories) {
            New-Item -ItemType Directory -Path $missingDirectory -Force
        }

    }

#endregion REMOTE DIRECTORIES
#region CONTACTS

    $message = "Contacts : UPDATING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    if (!(Test-Path $ContactsDB)) {New-ContactsDB}

    if (!(Get-Contact)) {
        while (!(Get-Contact)) {
            Write-Host+
            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp "  Contacts" -ForegroundColor DarkGray
            Write-Host+ -NoTrace -NoTimestamp "  --------" -ForegroundColor DarkGray
            do {
                $contactName = Read-Host "  Name"
                if (Get-Contact -Name $contactName) {Write-Host+ -NoTrace -NoTimestamp "  Contact $($contactName) already exists." -ForegroundColor DarkYellow}
            } until (!(Get-Contact -Name $contactName))
            do {
                $contactEmail = Read-Host "  Email (SMTP)"
                if (!$contactEmail) {
                    Write-Host+ -NoTrace -NoTimestamp "    Email is required for SMTP." -ForegroundColor DarkYellow
                }
                elseif (Get-Contact -Email $contactEmail) {
                    Write-Host+ -NoTrace -NoTimestamp "    Email $($contactEmail) already exists." -ForegroundColor DarkYellow
                }
            } until ($contactEmail -and !(Get-Contact -Email $contactEmail) -and $(IsValidEmail $contactEmail))
            do {
                $contactPhone = Read-Host "  Phone (SMS)"
                if (!$contactPhone) {
                    Write-Host+ -NoTrace -NoTimestamp "    Phone is required for SMS." -ForegroundColor DarkYellow
                }
                elseif (Get-Contact -Phone $contactPhone) {
                    Write-Host+ -NoTrace -NoTimestamp "    Phone $($contactPhone) already exists." -ForegroundColor DarkYellow
                }
            } until ($contactPhone -and !(Get-Contact -Phone $contactPhone) -and $(IsValidPhone $contactPhone))
            Add-Contact $contactName -Email $contactEmail -Phone $contactPhone
        }

        Write-Host+
        $message = "Contacts : UPDATED"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGreen
        Write-Host+

    }
    else {
        $message = "$($emptyString.PadLeft(8,"`b"))UPDATED "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion CONTACTS
#region LOG

    $message = "Log files : CREATING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    if (!(Test-Log -Name $Platform.Instance)) {
        New-Log -Name $Platform.Instance | Out-Null
    }

    $message = "$($emptyString.PadLeft(8,"`b"))CREATED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion LOG 
#region MAIN

    [console]::CursorVisible = $false

        #region PRODUCTS

            Write-Host+ -MaxBlankLines 1
            $message = "Installing products : PENDING"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray
            Write-Host+

            $message = "  Product             Publisher           Status              Task"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
            $message = "  -------             ---------           ------              ----"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

            $global:Environ.Product | ForEach-Object {Install-Product $_}
            
            Write-Host+
            $message = "Installing products : SUCCESS"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen

        #endregion PRODUCTS
        #region PROVIDERS
            
            Write-Host+ -MaxBlankLines 1
            $message = "Installing providers : PENDING"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray
            Write-Host+

            $message = "  Provider            Publisher           Status"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
            $message = "  --------            ---------           ------"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray            

            $global:Environ.Provider | ForEach-Object {Install-Provider $_}
            
            Write-Host+ -MaxBlankLines 1
            $message = "Installing providers : SUCCESS"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen

        #endregion PROVIDERS
        #region POST-INSTALLATION CONFIG

            $manualConfigFiles = @()
            $definitionsFiles = Get-Item -Path "definitions\definitions-*.ps1"
            foreach ($definitionFile in $definitionsFiles) {
                if (Select-String $definitionFile -Pattern "Manual Configuration > " -SimpleMatch -Quiet) {
                    $manualConfigFiles += $definitionFile
                }
            }

            if ($manualConfigFiles) {

                Write-Host+
                Write-Host+ -NoTrace -NoTimestamp "Post-Installation Configuration" -ForegroundColor DarkGray
                Write-Host+ -NoTrace -NoTimestamp "-------------------------------" -ForegroundColor DarkGray
                Write-Host+ -NoTrace -NoTimeStamp "Product > All > Task > Start disabled tasks"
                
                foreach ($manualConfigFile in $manualConfigFiles) {

                    $manualConfigMeta = (Select-String $manualConfigFile -Pattern "Manual Configuration > " -SimpleMatch -NoEmphasis -Raw) -split " > "
                    if ($manualConfigMeta) {
                        $manualConfigObjectType = $manualConfigMeta[1]
                        $manualConfigObjectId = $manualConfigMeta[2]
                        $manualConfigAction = $manualConfigMeta[3]
                        
                        switch ($manualConfigObjectType) {
                            "Service" {
                                $manualConfigObject = @{
                                    Name = $manualConfigObjectId
                                    IsInstalled = $true
                                }
                            }   
                            default {
                                $manualConfigObject = Invoke-Expression "Get-$manualConfigObjectType $manualConfigObjectId"
                            } 
                        }
                        if ($manualConfigObject.IsInstalled) {
                            $message = "$manualConfigObjectType > $($manualConfigObject.Name) > $manualConfigAction > Edit $(Split-Path $manualConfigFile -Leaf)"
                            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor Gray,DarkGray,Gray
                        }
                    }
                }

            }

        #endregion POST-INSTALLATION CONFIG

        Write-Host+
        $message = "Overwatch installation is complete."
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen
        Write-Host+

    [console]::CursorVisible = $true

#endregion MAIN