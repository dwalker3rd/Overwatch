#Requires -RunAsAdministrator
#Requires -Version 7

$emptyString = ""

. $PSScriptRoot\services\services-overwatch-loadearly.ps1

function Copy-File {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [switch]$Quiet,
        [switch]$ConfirmOverwrite
    )
    if (!$Destination) {
        $Destination = $Path -Replace "\\templates",""
        $Destination = $Destination -Replace "\\source\\products",""
        $Destination = $Destination -Replace "\\source",""
        $Destination = $Destination -Replace "\-template",""
    }
    if (Test-Path -Path $Path) {
        $overwrite = $true
        if ($ConfirmOverwrite -and (Test-Path -Path $Destination)) {
            Write-Host+ -NoTrace -NoTimeStamp "  Overwrite $($Destination)?"
            $overwrite = (Read-Host "  [Y] Yes [N] No (default is ""No"")") -eq "Y" 
        }
        if ($overwrite) {
            Copy-Item -Path $Path -Destination $Destination
            if (!$Quiet) {
                Split-Path -Path $Path -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "  Copied $_ to $Destination"  -ForegroundColor DarkGray}
            }
        }
        else {
            if (!$Quiet) {
                Split-Path -Path $Path -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "  [NOOVERWRITE] Not copying $_"  -ForegroundColor DarkGray}
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
        if (!$Quiet) {Write-Host+ -NoTrace -NoTimestamp "  Deleted $Path" -ForegroundColor Red}
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
    Write-Host+ -NoTrace -NoTimestamp "Installations" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "-------------" -ForegroundColor DarkGray
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

    Write-Host+
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
#region PLATFORM ID

    # if ($installedPlatforms.count -eq 1) {
        # $platformId = $installedPlatforms[0]
    # }
    # else {
        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Select Platform ", "$($installedPlatforms ? "[$($installedPlatforms -join ", ")] " : $null)", ": " -ForegroundColor Gray, Blue, Gray 
            $platformIdResponse = Read-Host
            $platformId = $platformIdResponse ? $platformIdResponse : $platformId
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
        $platformInstallLocation = $platformInstallLocationResponse ? $platformInstallLocationResponse : $platformInstallLocation
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
#region PLATFORM INSTANCE ID

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance ID ", "$($platformInstanceId ? "[$platformInstanceId] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
        $platformInstanceIdResponse = Read-Host
        $platformInstanceId = $platformInstanceIdResponse ? $platformInstanceIdResponse : $platformInstanceId
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
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Images URL ", "$($imagesUri ? " [$imagesUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            $imagesUriResponse = Read-Host
            $imagesUri = $imagesUriResponse ? $imagesUriResponse : $imagesUri
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
#region DIRECTORIES

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Directories" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "-----------" -ForegroundColor DarkGray

    if (!(Test-Path $PSScriptRoot\data\$platformInstanceId)) {New-Item -ItemType Directory -Path $PSScriptRoot\data\$platformInstanceId -Force}
    if (!(Test-Path $PSScriptRoot\logs)) {New-Item -ItemType Directory -Path $PSScriptRoot\logs -Force}
    if (!(Test-Path $PSScriptRoot\initialize)) {New-Item -ItemType Directory -Path $PSScriptRoot\initialize -Force}
    if (!(Test-Path $PSScriptRoot\preflight)) {New-Item -ItemType Directory -Path $PSScriptRoot\preflight -Force}
    if (!(Test-Path $PSScriptRoot\postflight)) {New-Item -ItemType Directory -Path $PSScriptRoot\postflight -Force}
    if (!(Test-Path $PSScriptRoot\temp)) {New-Item -ItemType Directory -Path $PSScriptRoot\temp -Force}

#endregion DIRECTORIES
#region PRODUCTS

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Select Products" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "---------------" -ForegroundColor DarkGray
    $_productIds  = @("Command")
    $productList = @("Monitor","Backup","Cleanup","DiskCheck","AzureADSync")
    foreach ($product in $productList) {
        $productResponseDefault = $product -in $productIds ? "Y" : "N"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $product ","[$productResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
        $productResponse = Read-Host
        if ([string]::IsNullOrEmpty($productResponse)) {$productResponse = $productResponseDefault}
        if ($productResponse -eq "Y") {
            $_productIds += $product
            if ($product -eq "AuzreADSync") {
                $_productIds += "AzureADCache"
            }
        }

    }
    $productIds = $_productIds
    Write-Host+ -NoTrace -NoTimestamp "Products: $($productIds -join ", ")" -IfDebug -ForegroundColor Yellow

#endregion PRODUCTS
#region PROVIDERS

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Select Providers" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "----------------" -ForegroundColor DarkGray
    $_providerIds = @("Views")
    $providerList = @("SMTP","MicrosoftTeams","TwilioSMS")
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

#endregion SAVE SETTINGS
#region FILES

    Write-Host+
    $message = "Configuration files : COPYING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray
    Write-Host+

    #region ENVIRON

        $sourceFile = "$PSScriptRoot\templates\environ\environ-template.ps1"
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
        Write-Host+ -NoTrace -NoTimestamp "  $($targetFileExists ? "Updated" : "Created") $targetFile" -ForegroundColor DarkGreen

        . $PSScriptRoot\environ.ps1

    #endregion ENVIRON
    #region PLATFORM INSTANCE DEFINITIONS

        Copy-File $PSScriptRoot\templates\definitions\definitions-overwatch-template.ps1
        Copy-File $PSScriptRoot\templates\definitions\definitions-os-$($operatingSystemId.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\definitions\definitions-platform-$($platformId.ToLower())-template.ps1

        $isSourceFileTemplate = $false
        $sourceFile = "$PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1"
        if (!(Test-Path $sourceFile) -or (Get-Content -Path $sourceFile | Select-String "<platformId>" -Quiet)) {
            $sourceFile = "$PSScriptRoot\templates\definitions\definitions-platforminstance-template.ps1"
            $isSourceFileTemplate = $true
        }
        $platformInstanceDefinitionsFile = Get-Content -Path $sourceFile
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformId>", ($platformId -replace " ","")
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstallLocation>", $platformInstallLocation
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceId>", $platformInstanceId
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<imagesUri>", $imagesUri
        $platformInstanceDefinitionsFile | Set-Content -Path $PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1
        Write-Host+ -NoTrace -NoTimestamp "  $($isSourceFileTemplate ? "Created" : "Updated") $PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1" -ForegroundColor DarkGreen

    #endregion PLATFORM INSTANCE DEFINITIONS
    #region COPY

        Copy-File $PSScriptRoot\source\services\services-$($operatingSystemId.ToLower())*.ps1 -Destination $PSScriptRoot\services
        Copy-File $PSScriptRoot\source\services\services-$($platformId.ToLower())*.ps1 -Destination $PSScriptRoot\services

        Copy-File $PSScriptRoot\templates\initialize\initialize-platform-overwatch-template.ps1
        Copy-File $PSScriptRoot\templates\initialize\initialize-platform-$($operatingSystemId.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\initialize\initialize-platform-$($platformId.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\initialize\initialize-platform-$($global:Environ.Instance)-template.ps1

        Copy-File $PSScriptRoot\templates\preflight\preflightchecks-overwatch-template.ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightchecks-os-$($global:Environ.OS.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightchecks-platform-$($global:Environ.Platform.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightchecks-platforminstance-$($global:Environ.Platform.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platforminstance-$($global:Environ.Instance).ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightupdates-overwatch-template.ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightupdates-os-$($global:Environ.OS.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightupdates-platform-$($global:Environ.Platform.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\preflight\preflightupdates-platforminstance-$($global:Environ.Platform.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platforminstance-$($global:Environ.Instance).ps1  

        Copy-File $PSScriptRoot\templates\postflight\postflightchecks-overwatch-template.ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightchecks-os-$($global:Environ.OS.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightchecks-platform-$($global:Environ.Platform.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightchecks-platforminstance-$($global:Environ.Platform.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platforminstance-$($global:Environ.Instance).ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightupdates-overwatch-template.ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightupdates-os-$($global:Environ.OS.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightupdates-platform-$($global:Environ.Platform.ToLower())-template.ps1
        Copy-File $PSScriptRoot\templates\postflight\postflightupdates-platforminstance-$($global:Environ.Platform.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platforminstance-$($global:Environ.Instance).ps1

        foreach ($product in $productIds) {
            Copy-File $PSScriptRoot\templates\definitions\definitions-product-$($product.ToLower())-template.ps1
            Copy-File $PSScriptRoot\source\products\$($product.ToLower()).ps1
        }      
        foreach ($provider in $providerIds) {
            Copy-File $PSScriptRoot\templates\definitions\definitions-provider-$($provider.ToLower())-template.ps1 -ConfirmOverwrite
            Copy-File $PSScriptRoot\source\providers\provider-$($provider.ToLower()).ps1
        }

        Write-Host+
        $message = "Configuration files : COPIED"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen
        Write-Host+

    #endregion COPY
#endregion FILES
#region MODULES-PACKAGES

    $message = "Powershell modules and packages : INSTALLING"
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
#region START OVERWATCH

    $message = "Overwatch : INITIALIZING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    pspref -xprefl -xpostfl -xwh -q

    $global:Product = @{Id="Install"}
    . $PSScriptRoot\definitions.ps1

    pspref -q

    $message = "$($emptyString.PadLeft(12,"`b"))INITIALIZED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion START OVERWATCH
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
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen
        Write-Host+

    }
    else {
        $message = "$($emptyString.PadLeft(8,"`b"))UPDATED "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion CONTACTS
#region CREDENTIALS

    $message = "Credentials : VALIDATING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    if (!$(Test-Credentials "localadmin-$($global:Platform.Instance)")) { 
        Write-Host+
        Write-Host+

        Request-Credentials -Message "    Enter the local admin credentials" -Prompt1 "    User" -Prompt2 "    Password" | Set-Credentials "localadmin-$($global:Platform.Instance)"
        
        Write-Host+
        $message = "Credentials : VALID"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen
        Write-Host+
    }
    else {
        $message = "$($emptyString.PadLeft(10,"`b"))VALID     "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion CREDENTIALS
#region LOG

    $message = "Log : CREATING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray

    if (!(Test-Log -Name $Platform.Instance)) {
        New-Log -Name $Platform.Instance | Out-Null
    }

    $message = "$($emptyString.PadLeft(8,"`b"))CREATED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion LOG 
#region MAIN

    [console]::CursorVisible = $false

        Write-Host+

        #region PRODUCTS

            $message = "Installing products : PENDING"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray
            Write-Host+

            $message = "  Product             Vendor              Status              Task*"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
            $message = "  -------             ------              ------              ----"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray


            $global:Environ.Product | ForEach-Object {Install-Product $_}

            Write-Host+
            $message = "  * Disabled tasks must be enabled manually"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
            
            Write-Host+
            $message = "Installing products : SUCCESS"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen

        #endregion PRODUCTS
        #region PROVIDERS
            
            Write-Host+
            $message = "Installing providers : PENDING"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGray
            Write-Host+

            $message = "  Provider            Vendor              Status"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
            $message = "  --------            ------              ------"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray            

            $global:Environ.Provider | ForEach-Object {Install-Provider $_}
            
            Write-Host+
            $message = "Installing providers : SUCCESS"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Blue,DarkGray,DarkGreen

        #region PROVIDERS

        Write-Host+
        $message = "Overwatch installation is complete."
        Write-Host+ -NoTrace -NoTimestamp $message
        Write-Host+

        Read-Host "Press any key to restart Overwatch"
        .\overwatch.ps1

    [console]::CursorVisible = $true

#endregion MAIN