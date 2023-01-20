#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param (
    [switch]$SkipProductStart,
    [switch]$SkipPowerShell,
    [switch]$UseDefaultResponses,
    [switch][Alias("PostInstall")]$PostInstallation
)

#region REMOVE PSSESSIONS

    # Remove-PSSession+

#endregion REMOVE PSSESSIONS

$global:WriteHostPlusPreference = "Continue"

$global:Environ = @{}
$global:Location = @{}

# if this is first install, then environ.ps1 does not exist
# copy it to the users' temp directory and update the global Location variable
if (!(Test-Path "environ.ps1")) {
    $sourceEnvironFile = "$PSScriptRoot\source\environ\environ-template.ps1"
    $environFile = "$($env:TEMP)\environ.ps1"
    Copy-File $sourceEnvironFile $environFile -Quiet
    Update-Environ -Source $sourceEnvironFile -Destination $environFile -Type Location -Name Root -Expression (Get-Location) 
    Remove-Variable -Scope Global Environ
}
else {
    $environFile = "$PSScriptRoot\environ.ps1"
}

. $environFile
. $PSScriptRoot\source\core\definitions\definitions-sysinternals.ps1
. $PSScriptRoot\source\core\definitions\definitions-powershell.ps1
. $PSScriptRoot\source\core\definitions\classes.ps1
. $PSScriptRoot\source\core\definitions\catalog.ps1
. $PSScriptRoot\source\core\definitions\definitions-regex.ps1
. $PSScriptRoot\source\core\definitions\definitions-overwatch.ps1
. $PSScriptRoot\source\core\services\services-overwatch-loadearly.ps1
. $PSScriptRoot\source\core\services\services-overwatch-install.ps1
. $PSScriptRoot\source\core\services\cache.ps1

Write-Host+ -ResetAll
Write-Host+

#region POST INSTALL SHORTCUT

    if ($PostInstallation -and $PSBoundParameters.Keys.Count -gt 1) {
        Write-Host+ -NoTrace -NoTimestamp  "The PostInstallation switch cannot be used with other switches." -ForegroundColor Red
        return
    }

    if ($PostInstallation) {
        try{
            Show-PostInstallation
        }
        catch {
            Write-Host+ -NoTrace -NoTimestamp  "The PostInstallation switch cannot be used until Overwatch is initialized." -ForegroundColor Red
            Write-Host+
        }
        return
    }

#endregion POST INSTALL SHORTCUT

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

# Clear-Host

#region CHECK INSTALLUPDATERESTART

    $installUpdateRestart = (read-cache installUpdateRestart).installUpdateRestart
    if ($installUpdateRestart) { $UseDefaultResponses = $true }

#endregion CHECK INSTALLUPDATERESTART
#region DISCOVERY

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Discovery" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "---------" -ForegroundColor DarkGray

    $overwatchInstallLocation = Get-Location

    $installedProducts = @()
    $installedProviders = @()
    $installOverwatch = $true
    try {

        $message = "<Control <.>24> SEARCHING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        # try{
            $global:WriteHostPlusPreference = "SilentlyContinue"
            $global:Product = @{Id="Command"}
            . $PSScriptRoot\definitions.ps1
        # }
        # catch {}
        # finally {
            # $global:WriteHostPlusPreference = "Continue"
        # }

        $installedProducts = Get-Product #-ResetCache
        $installedProviders = Get-Provider #-ResetCache
        $installOverwatch = $false

        $global:WriteHostPlusPreference = "Continue"
        $message = "$($emptyString.PadLeft(9,"`b"))$($Overwatch.DisplayName) "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Blue

    }
    catch {
        $global:WriteHostPlusPreference = "Continue"
        $message = "$($emptyString.PadLeft(9,"`b"))None      "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
    }

    if ($installOverwatch) {
        Write-Host+ -NoTrace -NoTimestamp -Parse "<Mode <.>24> Install" -ForegroundColor Gray,DarkGray,Blue
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp -Parse  "<Mode <.>24> Update" -ForegroundColor Gray,DarkGray,Blue
    }

    $installedOperatingSystem = $((Get-CimInstance -ClassName Win32_OperatingSystem).Name -split "\|")[0]
    if ($installedOperatingSystem -like "*Windows Server*") {
        $installedOperatingSystem = "WindowsServer"
    }
    else {
        throw "$installedOperatingSystem is not an Overwatch-supported operating system."
    }
    Write-Host+ -NoTrace -NoTimestamp -Parse "<Operating System <.>24> $installedOperatingSystem" -ForegroundColor Gray,DarkGray,Blue
    $operatingSystemId = $installedOperatingSystem

    $installedPlatforms = @()
    $localServices = Get-Service
    foreach ($key in $global:Catalog.Platform.Keys) { 
        if ($localServices.Name -contains $global:Catalog.Platform.$key.Installation.Discovery.Service) {
            $installedPlatforms += $key
        }
    }
    Write-Host+ -NoTrace -NoTimestamp -Parse "<Platform <.>24> $($installedPlatforms -join ", ")" -ForegroundColor Gray,DarkGray,Blue

    Write-Host+ -NoTrace -NoTimestamp -Parse "<Location <.>24> $((Get-Location).Path)" -ForegroundColor Gray,DarkGray,Blue

#endregion DISCOVERY
#region LOAD SETTINGS

    Write-Host+ -MaxBlankLines 1

    if (Test-Path -Path $($global:InstallSettings)) {
        . $($global:InstallSettings)
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        Write-Host+
    } 

#endregion LOAD SETTINGS

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace -NoTimestamp "Installation Questions" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "----------------------" -ForegroundColor DarkGray

#region OVERWATCH INSTALL LOCATION

    do {
        $overwatchInstallLocationResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Overwatch Install Location ", "$($overwatchInstallLocation ? "[$overwatchInstallLocation]" : $PSScriptRoot)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $overwatchInstallLocationResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $overwatchInstallLocation = ![string]::IsNullOrEmpty($overwatchInstallLocationResponse) ? $overwatchInstallLocationResponse : $overwatchInstallLocation
        Write-Host+ -NoTrace -NoTimestamp "Overwatch Install Location: $overwatchInstallLocation" -IfDebug -ForegroundColor Yellow
        if (!(Test-Path -Path $overwatchInstallLocation)) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find path '$overwatchInstallLocation' because it does not exist." -ForegroundColor Red
            $overwatchInstallLocation = $null
        }
        elseif ((Get-Location).Path -ne $overwatchInstallLocation) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Current location and install location must be the same." -ForegroundColor Red
            $overwatchInstallLocation = $null
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The path '$overwatchInstallLocation' is valid." -IfVerbose -ForegroundColor DarkGreen
        }
    } until ($overwatchInstallLocation)
    Write-Host+ -NoTrace -NoTimestamp "Overwatch Install Location: $overwatchInstallLocation" -IfDebug -ForegroundColor Yellow

#endregion OVERWATCH INSTALL LOCATION
#region PLATFORM ID

    $platformId = $installedPlatforms[0]
    do {
        $platformIdResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Select Platform ", "$($installedPlatforms ? "[$($installedPlatforms -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $platformIdResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformId = ![string]::IsNullOrEmpty($platformIdResponse) ? $platformIdResponse : $platformId
        Write-Host+ -NoTrace -NoTimestamp "Platform ID: $platformId" -IfDebug -ForegroundColor Yellow
        if ($installedPlatforms -notcontains $platformId) {
            Write-Host+ -NoTrace -NoTimestamp "Platform must be one of the following: $($installedPlatforms -join ", ")" -ForegroundColor Red
        }
    } until ($installedPlatforms -contains $platformId)

#endregion PLATFORM ID
#region PLATFORM INSTALL LOCATION

    do {
        $platformInstallLocationResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Install Location ", "$($platformInstallLocation ? "[$platformInstallLocation]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstallLocationResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformInstallLocation = ![string]::IsNullOrEmpty($platformInstallLocationResponse) ? $platformInstallLocationResponse : $platformInstallLocation
        Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow
        if (!(Test-Path -Path $platformInstallLocation)) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find path '$platformInstallLocation' because it does not exist." -ForegroundColor Red
            $platformInstallLocation = $null
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The path '$platformInstallLocation' is valid." -IfVerbose -ForegroundColor DarkGreen
        }
    } until ($platformInstallLocation)
    Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTALL LOCATION
#region PLATFORM INSTANCE URL

    do {
        try {
            $platformInstanceUriResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance URI ", "$($platformInstanceUri ? "[$platformInstanceUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $platformInstanceUriResponse = Read-Host
            }
            else {
                Write-Host+
            }
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
#region PLATFORM INSTANCE DOMAIN

    $platformInstanceDomain ??= $platformInstanceUri.Host.Split(".",2)[1]
    do {
        $platformInstanceDomainResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Domain ", "$($platformInstanceDomain ? "[$platformInstanceDomain]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstanceDomainResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformInstanceDomain = ![string]::IsNullOrEmpty($platformInstanceWriteDomainResponse) ? $platformInstanceDomainResponse : $platformInstanceDomain
        if (![string]::IsNullOrEmpty($platformInstanceDomain) -and $platformInstanceUri.Host -notlike "*$platformInstanceDomain") {
            Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid domain. Domain must match the platform instance URI" -ForegroundColor Red
            $platformInstanceDomain = $null
        }
    } until ($platformInstanceDomain)
    Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceDomain" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE DOMAIN
#region PLATFORM INSTANCE ID

    $platformInstanceId ??= $platformInstanceUri.Host -replace "\.","-"
    do {
        $platformInstanceIdResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance ID ", "$($platformInstanceId ? "[$platformInstanceId]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstanceIdResponse = Read-Host
        }
        else {
            Write-Host+
        }
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
#region PLATFORM INSTANCE NODES

    if ($platformId -eq "AlteryxServer") {
        do {
            $platformInstanceNodesResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Nodes ", "$($platformInstanceNodes ? "[$($platformInstanceNodes -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $platformInstanceNodesResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $platformInstanceNodes = ![string]::IsNullOrEmpty($platformInstanceNodesResponse) ? $platformInstanceNodesResponse : $platformInstanceNodes
            if ([string]::IsNullOrEmpty($platformInstanceNodes)) {
                Write-Host+ -NoTrace -NoTimestamp "NULL: Platform Instance Nodes is required" -ForegroundColor Red
                $platformInstanceNodes = $null
            }
        } until ($platformInstanceNodes)
        $platformInstanceNodes = $platformInstanceNodes -split "," | ForEach-Object { $_.Trim(" ") }
        Write-Host+ -NoTrace -NoTimestamp "Platform Instance Nodes: $platformInstanceNodes" -IfDebug -ForegroundColor Yellow
    }

#endregion PLATFORM INSTANCE NODES 
#region PYTHON

    $pythonEnvLocation = $null
    $pythonPipLocation = $null
    $pythonSitePackagesLocation = $null
    switch ($platformId) {
        "AlteryxServer" {
            $pythonEnvLocation = "$platformInstallLocation\bin\Miniconda3\envs\DesignerBaseTools_vEnv"
            $pythonPipLocation = "$pythonEnvLocation\Scripts"
            $pythonSitePackagesLocation = "$pythonEnvLocation\Lib\site-packages"

            $requiredPythonPackagesResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Required Python Packages ", "$($requiredPythonPackages ? "[$($requiredPythonPackages -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $requiredPythonPackagesResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $requiredPythonPackages = ![string]::IsNullOrEmpty($requiredPythonPackagesResponse) ? $requiredPythonPackagesResponse : $requiredPythonPackages
            $requiredPythonPackages = $requiredPythonPackages -split "," | ForEach-Object { $_.Trim(" ") }
            Write-Host+ -NoTrace -NoTimestamp "Required Python Packages: $requiredPythonPackages" -IfDebug -ForegroundColor Yellow
        }
        default {$null}
    }

#region PYTHON
#region IMAGES

    do {
        try {
            $imagesUriResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Images URL ", "$($imagesUri ? "[$imagesUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $imagesUriResponse = Read-Host
            }
            else {
                Write-Host+
            }
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

    $requiredDirectories = @("config","data","definitions","docs","docs\img","img","initialize","install","logs","preflight","postflight","providers","services","temp","install\data","views")

    $missingDirectories = @()
    foreach ($requiredDirectory in $requiredDirectories) {
        if (!(Test-Path "$PSScriptRoot\$requiredDirectory")) { $missingDirectories += "$PSScriptRoot\$requiredDirectory" }
    }
    if ($missingDirectories) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Local Directories" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "-----------------" -ForegroundColor DarkGray

        foreach ($missingDirectory in $missingDirectories) {
            $_dir = New-Item -ItemType Directory -Path $missingDirectory -Force
            Write-Host+ -NoTrace -NoTimeStamp "Directory: $($_dir.FullName)"
        }

        Write-Host+

    }

#endregion LOCAL DIRECTORIES
#region PRODUCTS
    
    $productsSelected = @()
    $productSpecificServices = @()
    $productDependencies = @()
    $productHeaderWritten = $false

    foreach ($key in $global:Catalog.Product.Keys) {

        $product = $global:Catalog.Product.$key
        
        if ([string]::IsNullOrEmpty($product.Installation.Prerequisite.Platform) -or $product.Installation.Prerequisite.Platform -contains $platformId) {

            if ($product.Id -notin $installedProducts.Id) {

                $productResponse = $null

                if ($product.Installation.Flag -contains "AlwaysInstall") {
                    $productsSelected += $product.id
                    $productResponse = "Y"
                }
                elseif ($product.Installation.Flag -notcontains "NoPrompt") {
                    if (!$productHeaderWritten) {
                        Write-Host+
                        Write-Host+ -NoTrace -NoTimestamp "Select Products" -ForegroundColor DarkGray
                        Write-Host+ -NoTrace -NoTimestamp "---------------" -ForegroundColor DarkGray
                        $productHeaderWritten = $true
                    }
                    $productResponseDefault = $product.id -in $productIds ? "Y" : "N"
                    $productResponse = $null
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $($product.id) ","[$productResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
                    if (!$UseDefaultResponses) {
                        $productResponse = Read-Host
                    }
                    else {
                        Write-Host+
                    }
                    if ([string]::IsNullOrEmpty($productResponse)) {$productResponse = $productResponseDefault}
                    if ($productResponse -eq "Y") {
                        $productsSelected += $product.id
                    }
                }

                if ($productResponse -eq "Y") {
                    if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Product)) {
                        foreach ($prerequisiteProduct in $product.Installation.Prerequisite.Product) {
                            if ($prerequisiteProduct -notin $installedProducts.Id) {
                                if ($prerequisiteProduct -notin $productsSelected) {
                                    $productsSelected += $prerequisiteProduct
                                    $productDependencies += @{
                                        Product = $product.id
                                        Dependency = $prerequisiteProduct
                                    }
                                }
                            }
                        }
                    }
                    if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Service)) {
                        foreach ($prerequisiteService in $product.Installation.Prerequisite.Service) {
                            $productSpecificServices += @{
                                Product = $product.id
                                Service = $prerequisiteService
                            }
                        }
                    }
                }
            }
            else {
                # code repeat necessary to catch product service prerequisites when using -Update switch
                if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Service)) {
                    foreach ($prerequisiteService in $product.Installation.Prerequisite.Service) {
                        $productSpecificServices += @{
                            Product = $product.id
                            Service = $prerequisiteService
                        }
                    }
                }
            }

        }

    }
    $productIds = $productsSelected

    Write-Host+ -Iff $productHeaderWritten

    if ($productDependencies) {
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "Other Products" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "--------------" -ForegroundColor DarkGray
        foreach ($productDependency in $productDependencies) {
            Write-Host+ -NoTrace -NoTimestamp $($productDependency.Dependency),"(required by $($productDependency.Product))" -ForegroundColor Gray,DarkGray
        }
        Write-Host+
    }

#endregion PRODUCTS
#region PROVIDERS

    $providerHeaderWritten = $false
    $_providerIds = @()
    foreach ($key in $global:Catalog.Provider.Keys) {
        $provider = $global:Catalog.Provider.$key
        if ([string]::IsNullOrEmpty($provider.Installation.Prerequisite.Platform) -or $provider.Installation.Prerequisite.Platform -contains $platformId) {
            if ($provider.Id -notin $installedProviders.Id) {
                if ($provider.Installation.Flag -contains "AlwaysInstall") {
                    $_providerIds += $provider.Id
                }
                elseif ($provider.Installation.Flag -notcontains "NoPrompt") {
                    if (!$providerHeaderWritten) {
                        Write-Host+ -MaxBlankLines 1
                        Write-Host+ -NoTrace -NoTimestamp "Select Providers" -ForegroundColor DarkGray
                        Write-Host+ -NoTrace -NoTimestamp "----------------" -ForegroundColor DarkGray
                        $providerHeaderWritten = $true
                    }
                    $providerResponseDefault = $provider.ID -in $providerIds ? "Y" : "N"
                    $providerResponse = $null
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $($provider.Id) ","[$providerResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
                    if (!$UseDefaultResponses) {
                        $providerResponse = Read-Host
                    }
                    else {
                        Write-Host+
                    }
                    if ([string]::IsNullOrEmpty($providerResponse)) {$providerResponse = $providerResponseDefault}
                    if ($providerResponse -eq "Y") {
                        $_providerIds += $provider.Id
                    }
                }

                
            }
        }
    }
    $providerIds = $_providerIds

    Write-Host+ -Iff $providerHeaderWritten

#endregion PROVIDERS
#region UPDATES

    if (!$installOverwatch) {

        Write-Host+ -MaxBlankLines 1
        $message = "<Updated Files <.>48> CHECKING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        Write-Host+

        $updatedFiles = @()

        #region CORE

            $coreFiles = @()

            $files = (Get-ChildItem $PSScriptRoot\source\core -File).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            $files = (Get-ChildItem $PSScriptRoot\source\core\config -File).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            $files = (Get-ChildItem $PSScriptRoot\source\core\definitions -File).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            # if classes file is updated, then all cache will need to be deleted before Overwatch is initialized
            $classesFile = Copy-File $PSScriptRoot\source\core\definitions\classes.ps1 $PSScriptRoot\definitions\classes.ps1 -WhatIf
            $classesFileUpdated = $null -ne $classesFile
            # $coreFiles += $classesFile

            $files = (Get-ChildItem $PSScriptRoot\source\core\services -File -Recurse).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }
            $files = (Get-ChildItem $PSScriptRoot\source\core\views -File -Recurse).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            $sourceEnvironFile = "$PSScriptRoot\source\environ\environ-template.ps1"
            $tempEnvironFile = "$PSScriptRoot\temp\environ.ps1"
            $destinationEnvironFile = "$PSScriptRoot\environ.ps1"

            Update-Environ -Source $sourceEnvironFile -Destination $tempEnvironFile

            $environFile = Copy-File $tempEnvironFile $destinationEnvironFile -WhatIf -Quiet

            $environFileUpdated = $false
            if ($environFile) {
                $environFile.Component = "Core"
                $environFile.$($environFile.Component) = "Environ"
                $environFile += @{ Flag = "NOCOPY" }
                $environFileUpdated = $true
                $coreFiles += $environFile
                Write-Host+ -NoTrace -NoTimestamp "  [$($environFile.Component)`:$($environFile.$($environFile.Component))] $($environFile.Destination)" -ForegroundColor DarkGray
            }
            Remove-Files -Path $tempEnvironFile

            $updatedfiles += $coreFiles

            $installUpdate = $false
            if ($coreFiles.Count -gt 0 -and (Split-Path $coreFiles.Destination -Leaf) -like "*install.ps1") {
                $installUpdate = $true
            }

        #endregion CORE
        #region PowerShell

            # $psFiles = @()
            # $psFiles += Copy-File $PSScriptRoot\source\powershell\definitions-ps-*.ps1 $PSScriptRoot\definitions -WhatIf
            # $psFiles += Copy-File $PSScriptRoot\source\powershell\config-ps-*.ps* $PSScriptRoot\config -WhatIf
            # $updatedFiles += $psFiles

        #endregion PowerShell
        #region OS

            $osFiles = @()
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\config-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
            $updatedFiles += $osFiles

        #endregion OS
        #region PLATFORM            

            $platformFiles = @()
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\config\config-platform-$($platformInstanceId).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformInstanceId).ps1 -WhatIf
            foreach ($platformPrerequisiteService in $global:Catalog.Platform.$platformId.Installation.Prerequisite.Service) {
                $platformFiles += Copy-File $PSScriptRoot\source\services\$($platformPrerequisiteService.ToLower())\services-$($platformPrerequisiteService.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            }
            $updatedFiles += $platformFiles

        #endregion PLATFORM
        #region PRODUCT

            $productFiles = @()

            $productSpecificServiceFiles = @()
            foreach ($productSpecificService in $productSpecificServices.Service | Sort-Object -Unique) {
                if (Test-Path "$PSScriptRoot\source\services\$($productSpecificService.ToLower())\definitions-service-$($productSpecificService.ToLower())-template.ps1") {
                    $productSpecificServiceFiles += Copy-File $PSScriptRoot\source\services\$($productSpecificService.ToLower())\definitions-service-$($productSpecificService.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-service-$($productSpecificService.ToLower()).ps1 -WhatIf
                }
                $productSpecificServiceFiles += Copy-File $PSScriptRoot\source\services\$($productSpecificService.ToLower())\services-$($productSpecificService.ToLower()).ps1 $PSScriptRoot\services\services-$($productSpecificService.ToLower()).ps1 -WhatIf
            }
            foreach ($productSpecificServiceFile in $productSpecificServiceFiles) {
                if ($productSpecificServiceFile.Source.FullName -notin $productFiles.Source.FullName) {
                    $productfiles += $productSpecificServiceFile
                }
            }

            foreach ($product in $global:Environ.Product + $productIds) {
                $productFiles += Copy-File $PSScriptRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $PSScriptRoot\install\install-product-$($product.ToLower()).ps1 -WhatIf
                $productFiles += Copy-File $PSScriptRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.ToLower()).ps1 -WhatIf
                $productFiles += Copy-File $PSScriptRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $PSScriptRoot\$($product.ToLower()).ps1 -WhatIf
            }

            $updatedFiles += $productFiles

        #endregion PRODUCT
        #region PROVIDER                    

            $providerFiles = @()

            foreach ($provider in $global:Environ.Provider + $providerIds) {
                $providerFiles += Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\install-provider-$($provider.ToLower()).ps1 -WhatIf
                $providerFiles += Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-provider-$($provider.ToLower()).ps1 -WhatIf
                $providerFiles += Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $PSScriptRoot\providers\provider-$($provider.ToLower()).ps1 -WhatIf
            }

            $updatedFiles += $providerFiles

        #endregion PROVIDER
        #region DEFINITIONS-SERVICES

            $definitionsServicesFile = "$PSScriptRoot\definitions\definitions-services.ps1"

            $definitionsServicesUpdated = $false
            foreach ($productSpecificService in $productSpecificServices.Service) {
                if (Test-Path "$PSScriptRoot\definitions\definitions-service-$($productSpecificService.ToLower()).ps1") {
                    $contentLine = ". `"`$(`$global:Location.Definitions)\definitions-service-$($productSpecificService.ToLower()).ps1`""
                    if (!(Select-String -Path $definitionsServicesFile -Pattern $contentLine -SimpleMatch -Quiet)) {
                        $definitionsServicesUpdated = $true
                    }
                }
                $contentLine = ". `"`$(`$global:Location.Services)\services-$($productSpecificService.ToLower()).ps1`""
                if (!(Select-String -Path $definitionsServicesFile -Pattern $contentLine -SimpleMatch -Quiet)) {
                    $definitionsServicesUpdated = $true
                }
            }

            if ($definitionsServicesUpdated) {
                Write-Host+ -NoTrace -NoTimestamp "  [Core:Definitions] $definitionsServicesFile" -ForegroundColor DarkGray
                $updatedFiles += $definitionsServicesFile
            }

        #endregion DEFINITIONS-SERVICES


        if (!$updatedFiles) {
            $message = "<Updated Files <.>48> NONE    "
            Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 2 -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        }

    }

#endregion UPDATES
#region IMPACT

    $impactedIds = @()
    if ($coreFiles) {
        $impactedIds += "Overwatch.Overwatch"
    }
    if ($platformFiles) {
        $impactedIds += "Platform.$platformId"
    }
    if ($productFiles) {
        $productIds += ($productFiles.Product -split ",") | Where-Object {$_ -notin $productIds} | Sort-Object -Unique
        $impactedIds += foreach ($productId in $productIds) { "Product.$productId" }
    }
    if ($providerFiles) {
        $providerIds += ($providerFiles.Provider -split ",") | Where-Object {$_ -notin $providerIds} | Sort-Object -Unique
        $impactedIds += foreach ($providerId in $providerIds) { "Provider.$providerId" }
    }
    if ($coreFiles -or $osFiles -or $platformFiles) {
        $productIds += $global:Environ.Product | Where-Object {$_ -notin $productIds}
        $providerIds += $global:Environ.Provider | Where-Object {$_ -notin $providerIds}
    }

    if ($installUpdateRestart) {
        $impactedProductIds = @()
        $productIds = (Get-Product).Id 
    }
    else {
        $disabledProductIDS = @()
        $impactedProductIds = $productIds | Where-Object {$_ -in $global:Environ.Product}
    }

    if ($impactedProductIds) {

        $disabledProductIds += (Get-PlatformTask -Disabled).ProductID

        Write-Host+ -MaxBlankLines 1
        $message = "<Impacted Products <.>48> DISABLING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        Write-Host+

        $message = "  Product             Publisher           Status              Task"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
        $message = "  -------             ---------           ------              ----"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

        foreach ($impactedProductId in $impactedProductIds) {
            if ((Get-Product -Id $impactedProductId).HasTask) {
                Disable-Product $impactedProductId
            }
        }

        Write-Host+

    }

#endregion IMPACT
#region FILES

    if ($installOverwatch -or $updatedFiles) {

        Write-Host+ -MaxBlankLines 1
        $message = $installOverwatch ? "<Source Files <.>48> COPYING" : "<Updated Files <.>48> COPYING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        Write-Host+

        #region CORE

            $files = (Get-ChildItem $PSScriptRoot\source\core -File -Recurse).VersionInfo.FileName
            foreach ($file in $files) { 
                Copy-File $file $file.replace("\source\core","")
            }

            $destinationEnvironFileExists = Test-Path $destinationEnvironFile
            if ($environFileUpdated) {
                Update-Environ -Source $sourceEnvironFile -Destination $destinationEnvironFile
                Write-Host+ -NoTrace -NoTimestamp "  $($destinationEnvironFileExists ? "Updated" : "Created") $destinationEnvironFile" -ForegroundColor DarkGreen
            }
            . $PSScriptRoot\environ.ps1

        #endregion ENVIRON
        #region PowerShell

            # Copy-File $PSScriptRoot\source\powershell\definitions-ps-*.ps1 $PSScriptRoot\definitions
            # Copy-File $PSScriptRoot\source\powershell\config-ps-*.ps* $PSScriptRoot\config

        #endregion PowerShell
        #region OS

            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $PSScriptRoot\services
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\config-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-os-$($operatingSystemId.ToLower()).ps1

        #endregion OS
        #region PLATFORM

            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1

            $sourceFile = "$PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$($platformId.ToLower())-template.ps1"
            $destinationFile = "$PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1"
            if (Copy-File $sourcefile $destinationFile -ConfirmCopy) {
                $platformInstanceDefinitionsFile = Get-Content -Path $destinationFile
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformId>", ($platformId -replace " ","")
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstallLocation>", $platformInstallLocation
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceId>", $platformInstanceId
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceUrl>", $platformInstanceUri
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceDomain>", $platformInstanceDomain
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace '"<platformInstanceNodes>"', "@('$($platformInstanceNodes -join "', '")')"
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<pythonPipLocation>", $pythonPipLocation
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<pythonSitePackagesLocation>", $pythonSitePackagesLocation
                $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace '"<requiredPythonPackages>"', "@('$($requiredPythonPackages -join "', '")')"
                $platformInstanceDefinitionsFile | Set-Content  -Path $destinationFile
                Write-Host+ -NoTrace -NoTimestamp "  Updated $destinationFile" -ForegroundColor DarkGreen
            }

            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $PSScriptRoot\services
            
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platform-$($platformId.ToLower()).ps1

            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\config\config-platform-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platforminstance-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platforminstance-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platforminstance-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platforminstance-$($platformInstanceId).ps1

            $definitionsServicesUpdated = $false
            foreach ($platformPrerequisiteService in $global:Catalog.Platform.$platformId.Installation.Prerequisite.Service) {
                $platformPrerequisiteServiceFiles = Copy-File $PSScriptRoot\source\services\$($platformPrerequisiteService.ToLower())\services-$($platformPrerequisiteService.ToLower())*.ps1 $PSScriptRoot\services -WhatIf -Quiet
                foreach ($platformPrerequisiteServiceFile in $platformPrerequisiteServiceFiles) {
                    Copy-File $platformPrerequisiteServiceFile.Source $platformPrerequisiteServiceFile.Destination
                    Get-Item $platformPrerequisiteServiceFile.Destination | 
                        Foreach-Object {
                            $contentLine = ". `"`$(`$global:Location.Services)\$($_.Name)`""
                            if (!(Select-String -Path $definitionsServicesFile -Pattern $contentLine -SimpleMatch -Quiet)) {
                                Add-Content -Path $definitionsServicesFile -Value $contentLine
                                $definitionsServicesUpdated = $true
                            }
                        }
                    }
            }
            if ($definitionsServicesUpdated) {
                Write-Host+ -Iff $($definitionsServicesUpdated) -NoTrace -NoTimestamp "  Updated $definitionsServicesFile with platform services." -ForegroundColor DarkGreen
            }

        #endregion PLATFORM
        #region PRODUCT

            foreach ($product in $global:Environ.Product) {
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $PSScriptRoot\install\install-product-$($product.ToLower()).ps1
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\uninstall-product-$($product.ToLower()).ps1 $PSScriptRoot\install\uninstall-product-$($product.ToLower()).ps1
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.ToLower()).ps1
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $PSScriptRoot\$($product.ToLower()).ps1
            }    

            foreach ($productSpecificService in $productSpecificServices.Service) {
                Copy-File $PSScriptRoot\source\services\$($productSpecificService.ToLower())\definitions-service-$($productSpecificService.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-service-$($productSpecificService.ToLower()).ps1
                Copy-File $PSScriptRoot\source\services\$($productSpecificService.ToLower())\services-$($productSpecificService.ToLower()).ps1 $PSScriptRoot\services\services-$($productSpecificService.ToLower()).ps1
            }

        #endregion PRODUCT             
        #region PROVIDER

            foreach ($provider in $global:Environ.Provider) {
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\install-provider-$($provider.ToLower()).ps1
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\uninstall-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\uninstall-provider-$($provider.ToLower()).ps1
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-provider-$($provider.ToLower()).ps1
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $PSScriptRoot\providers\provider-$($provider.ToLower()).ps1
            }

        #endregion PROVIDER

    }

    # always ensure definitions/definitions-services.ps1 has product-specific service entries
    $definitionsServicesUpdated = $false
    foreach ($productSpecificService in $productSpecificServices.Service) {
        if (Test-Path "$PSScriptRoot\definitions\definitions-service-$($productSpecificService.ToLower()).ps1") {
            $contentLine = ". `"`$(`$global:Location.Definitions)\definitions-service-$($productSpecificService.ToLower()).ps1`""
            if (!(Select-String -Path $definitionsServicesFile -Pattern $contentLine -SimpleMatch -Quiet)) {
                Add-Content -Path $definitionsServicesFile -Value $contentLine
                $definitionsServicesUpdated = $true
            }
        }
        $contentLine = ". `"`$(`$global:Location.Services)\services-$($productSpecificService.ToLower()).ps1`""
        if (!(Select-String -Path $definitionsServicesFile -Pattern $contentLine -SimpleMatch -Quiet)) {
            Add-Content -Path $definitionsServicesFile -Value $contentLine
            $definitionsServicesUpdated = $true
        }
    }

    if ($definitionsServicesUpdated) {
        Write-Host+ -Iff $($definitionsServicesUpdated) -NoTrace -NoTimestamp "  Updated $definitionsServicesFile with product-specific services." -ForegroundColor DarkGreen
    }

    Write-Host+ -MaxBlankLines 1

#endregion FILES
#region INSTALL UPDATE

    if ($installUpdate) {

        $installUpdateRestartData = [PSCustomObject]@{
            installUpdateRestart = $true
            disabledProductIds = $disabledProductIds
        }  
        
        $installUpdateRestartData | Write-Cache installUpdateRestart

        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "The installer has been updated and must be restarted." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoTimestamp "This update will not be complete until the installer is rerun." -ForegroundColor DarkYellow
        Write-Host+

        Remove-PSSession+
        
        return
    }

#endregion INSTALL UPDATE

    . $PSScriptRoot\definitions\definitions-sysinternals.ps1
    . $PSScriptRoot\definitions\definitions-powershell.ps1
    . $PSScriptRoot\definitions\classes.ps1
    . $PSScriptRoot\definitions\catalog.ps1
    . $PSScriptRoot\definitions\definitions-regex.ps1
    . $PSScriptRoot\definitions\definitions-overwatch.ps1
    . $PSScriptRoot\services\services-overwatch-loadearly.ps1
    . $PSScriptRoot\services\services-overwatch-install.ps1
    . $PSScriptRoot\services\cache.ps1

#region POWERSHELL MODULES-PACKAGES

    if (!$SkipPowerShell) {

        Write-Host+ -MaxBlankLines 1
        $message = "<Powershell modules/packages <.>48> INSTALLING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        $requiredModules = @()
        $requiredPackages = @()

        foreach ($impactedId in $impactedIds) {
            $dependencies = Get-CatalogDependencies -Type ($impactedId -split "\.")[0] -Id ($impactedId -split "\.")[1]  -Recurse
            foreach ($dependency in ($dependencies | Where-Object {$_.Type -eq "PowerShell"})) {
                if ($dependency.Id -eq "Module") { 
                    $requiredModules +=  @{ Name = $dependency.Object.Name }
                }
                if ($dependency.Id -eq "Package") { 
                    $requiredPackages +=  @{ Name = $dependency.Object.Name }
                }
            }
        }

        if (!(Get-PackageSource -ProviderName PowerShellGet)) {
            Register-PackageSource -Name PSGallery -ProviderName PowerShellGet -Trusted -ErrorAction SilentlyContinue | Out-Null
        }
        if (!(Get-PackageSource -ProviderName NuGet -ErrorAction SilentlyContinue)) {
            Register-PackageSource -Name Nuget -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -Trusted -ErrorAction SilentlyContinue | Out-Null
        }

        $requiredModules += @()
        foreach ($module in $requiredModules) {

            $message = "<  $($module.name) <.>36> PENDING"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            $installedColor = "DarkGray"
            if (!(Get-InstalledModule -Name $module.name -ErrorAction SilentlyContinue)) {
                Install-Module -Name $module.name -Force -ErrorAction SilentlyContinue | Out-Null
                Import-Module -Name $module.name -ErrorAction SilentlyContinue | Out-Null
                $installedColor = "DarkGreen"
            }
            
            $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED "
            Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor $installedColor

        }

        # $requiredPackages += @()
        foreach ($package in $requiredPackages) {
            
            $message = "<  $($package.name) <.>36> PENDING"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            $installedColor = "DarkGray"
            if (!(Get-InstalledModule -Name $package.name -ErrorAction SilentlyContinue)) {
                Install-Package -Name $package.name -SkipDependencies -Force | Out-Null
                $installedColor = "DarkGreen"
            }

            $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED "
            Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor $installedColor

        }

        $message = "<Powershell modules/packages <.>48> INSTALLED"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen

    }

#endregion POWERSHELL MODULES-PACKAGES
#region PYTHON-PACKAGES

    switch ($platformId) {
        "AlteryxServer" {
            if ($requiredPythonPackages) {

                $message = "<Python Packages <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

                Install-PythonPackage -Package $requiredPythonPackages -Pip $pythonPipLocation -ComputerName $platformInstanceNodes -Quiet

                $message = "$($emptyString.PadLeft(10,"`b"))INSTALLED "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

            }
        }
        default {}
    }

#region PYTHON-PACKAGES
#region REMOVE CACHE

    if ($installOverwatch -or $classesFileUpdated) {
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\clusterstatus.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\heartbeat.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platforminfo.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platformstatus.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platformservices.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platformtopology.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\providers.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\products.cache"
    }

#endregion REMOVE CACHE
#region INITIALIZE OVERWATCH

    $message = "<Overwatch <.>48> INITIALIZING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    try{
        $global:WriteHostPlusPreference = "SilentlyContinue"
        $global:Product = @{Id="Command"}
        . $PSScriptRoot\definitions.ps1
    }
    catch {}
    finally {
        $global:WriteHostPlusPreference = "Continue"
    }

    $message = "$($emptyString.PadLeft(12,"`b"))INITIALIZED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    . $PSScriptRoot\services\services-overwatch-install.ps1

#endregion INITIALIZE OVERWATCH
#region CREDENTIALS

    if ($installOverwatch) {
        . $PSScriptRoot\services\vault.ps1
        . $PSScriptRoot\services\encryption.ps1
        . $PSScriptRoot\services\credentials.ps1

        $message = "<Admin Credentials <.>48> VALIDATING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        if (!$(Test-Credentials -NoValidate "localadmin-$platformInstanceId")) { 
            Write-Host+
            Write-Host+

            Request-Credentials -Message "  Enter the local admin credentials" -Prompt1 "  User" -Prompt2 "  Password" | Set-Credentials "localadmin-$($global:Platform.Instance)"
            
            Write-Host+
            $message = "<Admin Credentials <.>48> VALID"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
            Write-Host+
        }
        else {
            $message = "$($emptyString.PadLeft(10,"`b"))VALID     "
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
    }

#endregion CREDENTIALS
#region REMOTE DIRECTORIES

    $requiredDirectories = @("data","config")

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
            $_dir = New-Item -ItemType Directory -Path $missingDirectory -Force
            Write-Host+ -NoTrace -NoTimeStamp "Directory: $($_dir.FullName)"
        }

        Write-Host+

    }

#endregion REMOTE DIRECTORIES
#region CONTACTS

    if ($installOverwatch) {
        $message = "<Contacts <.>48> UPDATING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        if (!(Test-Path $ContactsDB)) {New-ContactsDB}

        if (!(Get-Contact)) {
            while (!(Get-Contact)) {
                Write-Host+
                Write-Host+
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
            $message = "<Contacts <.>48> UPDATED"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
            Write-Host+

        }
        else {
            $message = "$($emptyString.PadLeft(8,"`b"))UPDATED "
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
    }

#endregion CONTACTS
#region LOG

    if ($installOverwatch) {
        $message = "<Log files <.>48> CREATING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        $osLogFile = ((Get-Catalog $OS.Id -Type "OS").Log).ToLower()
        if (!(Test-Log -Name $osLogFile)) {
            New-Log -Name $osLogFile | Out-Null
        }

        $platformLogFile = ((Get-Catalog $Platform.Id -Type "Platform").Log).ToLower()
        if (!(Test-Log -Name $platformLogFile)) {
            New-Log -Name $platformLogFile | Out-Null
        }

        $message = "$($emptyString.PadLeft(8,"`b"))CREATED "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion LOG 
#region MAIN

    [console]::CursorVisible = $false

        #region CONFIG

            if (!$SkipPowerShell) {    
                if (Test-Path "$PSScriptRoot\config\config-ps-remoting.ps1") {. "$PSScriptRoot\config\config-ps-remoting.ps1" }
            }

            if (Test-Path "$PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1") {. "$PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1" }
            if (Test-Path "$PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1") {. "$PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1" }
            if (Test-Path "$PSScriptRoot\config\config-platforminstance-$($platformInstanceId.ToLower()).ps1") {. "$PSScriptRoot\config\config-platforminstance-$($platformInstanceId.ToLower()).ps1" }

        #endregion CONFIG
        #region PROVIDERS

            if ($providerIds) {
                    
                Write-Host+ -MaxBlankLines 1
                $message = "<Providers <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Provider            Publisher           Status"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  --------            ---------           ------"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray            

                $providerIds | ForEach-Object { Install-Provider $_ -UseDefaultResponses:$UseDefaultResponses }
                
                Write-Host+

            }

        #endregion PROVIDERS        
        #region PRODUCTS

            if ($installUpdateRestart) {
                $disabledProductIds = (read-cache installUpdateRestart).disabledProductIds
                if ($disabledProductIds) {
                    $productIds += $disabledProductIds | Where-Object {$_ -notin $productIds}
                }
            }

            if ($productIds) {

                Write-Host+ -MaxBlankLines 1
                $message = "<Products <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Product             Publisher           Status              Task"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  -------             ---------           ------              ----"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

                foreach ($productId in $productIds) {

                    if ((Get-Product -Id $productId).HasTask) {
                        Install-Product $productId -NoNewLine
                        if (!$SkipProductStart -and !$installOverwatch) {
                            if ($productId -notin $disabledProductIDs) {
                                Enable-Product $productId -NoNewLine
                            }
                            else {
                                Disable-Product $productId -NoNewLine
                            }
                        }
                        else {
                            Write-Host+
                        }
                    }
                    else {
                        Install-Product $productId -UseDefaultResponses:$UseDefaultResponses
                    }

                }

                Write-Host+

            }

        #endregion PRODUCTS
        #region SAVE SETTINGS

            Update-InstallSettings

        #endregion SAVE SETTINGS
        #region INITIALIZE OVERWATCH

            if ($productIds -or $providerIds) {

                $message = "<Overwatch <.>48> VERIFYING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
            
                try{
                    $global:WriteHostPlusPreference = "SilentlyContinue"
                    $global:Product = @{Id="Command"}
                    . $PSScriptRoot\definitions.ps1
                }
                catch {}
                finally {
                    $global:WriteHostPlusPreference = "Continue"
                }
            
                $message = "$($emptyString.PadLeft(9,"`b"))VERIFIED "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

                . $PSScriptRoot\services\services-overwatch-install.ps1

            }
        
        #endregion INITIALIZE OVERWATCH 
        #region POST-INSTALLATION CONFIG

            Show-PostInstallation

        #endregion POST-INSTALLATION CONFIG
        #region CLEAR INSTALLUPDATERESTART

            clear-cache installUpdateRestart

        #endregion CLEAR INSTALLUPDATERESTART
        #region REMOVE PSSESSIONS

            Remove-PSSession+

        #endregion REMOVE PSSESSIONS

        Write-Host+ -MaxBlankLines 1
        $message = "Overwatch installation is complete."
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen
        Write-Host+

    [console]::CursorVisible = $true

#endregion MAIN

#tag you're it