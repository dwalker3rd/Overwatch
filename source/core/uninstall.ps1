#Requires -RunAsAdministrator
#Requires -Version 7

param(
    [Parameter(Mandatory=$false,Position=0)][ValidateSet("Provider","Product")][string]$Type,
    [Parameter(Mandatory=$false,Position=1)][string]$Name,
    [switch]$Force
)

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "SilentlyContinue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:ConfirmPreference = "None"

$global:Product = @{Id="Uninstall"}
. $PSScriptRoot\definitions.ps1
. $PSScriptRoot\services\services-overwatch-install.ps1

$installSettingsFile = "$($global:Location.Root)\install\data\installSettings.ps1"

function Remove-ProviderFiles {

    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Provider
    )

    Remove-Files $PSScriptRoot\install\install-provider-$($Provider.ToLower()).ps1
    Remove-Files $PSScriptRoot\definitions\definitions-provider-$($Provider.ToLower()).ps1
    Remove-Files $PSScriptRoot\providers\provider-$($Provider.ToLower()).ps1

}

function Remove-ProductFiles {

    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Product
    )

    Remove-Files $PSScriptRoot\config\config-product-$($Product.ToLower()).ps1
    Remove-Files $PSScriptRoot\install\install-product-$($Product.ToLower()).ps1
    Remove-Files $PSScriptRoot\definitions\definitions-product-$($Product.ToLower()).ps1
    Remove-Files $PSScriptRoot\$($Product.ToLower()).ps1

    $allProductSpecificServices = @()
    foreach ($key in $global:catalog.Product.Keys) {
        if ($global:Catalog.Product.$key.Installation.Prerequisite.Service) {
            if ((Get-Product $global:Catalog.Product.$key.Id).IsInstalled) {
                $allProductSpecificServices += $global:Catalog.Product.$key.Installation.Prerequisite.Service
            }
        }
    }
    # $allProductSpecificServices | Sort-Object -Unique 
    $productSpecificServices = @()
    foreach ($service in $global:catalog.Product.$Product.Installation.Prerequisite.Service) {
        if ($service -notin $allProductSpecificServices) {
            $productSpecificServices += $global:catalog.Product.$Product.Installation.Prerequisite.Service
        }
    }

    $definitionsServices = "$($global:Location.Definitions)\definitions-services.ps1"
    $definitionsServicesFile = Get-Content -Path $definitionsServices
    foreach ($productSpecificService in $productSpecificServices) {
        if (Test-Path "$($global:Location.Definitions)\definitions-service-$($productSpecificService.ToLower()).ps1") {
            Remove-Files $($global:Location.Definitions)\definitions-service-$($productSpecificService.ToLower()).ps1
            $contentLine = '. \$definitionsPath\\definitions-service-' + $productSpecificService.Service.ToLower() + '.ps1'
            foreach ($line in $definitionsServicesFile) {
                if ($line -match $contentLine) {
                    $definitionsServicesFile = $definitionsServicesFile | Where-Object {$_ -ne $line}
                }
            }
        }
        Remove-Files $PSScriptRoot\services\services-$($productSpecificService.ToLower()).ps1
        $contentLine = '. \$servicesPath\\services-' + $productSpecificService.ToLower() + '.ps1'  # string must be in single quotes b/c of $ character
        foreach ($line in $definitionsServicesFile) {
            if ($line -match $contentLine) {
                $definitionsServicesFile = $definitionsServicesFile | Where-Object {$_ -ne $line}
            }
        }
        
    }
    $definitionsServicesFile | Set-Content -Path $definitionsServices

}

function Remove-PlatformInstanceFiles {

    Remove-Files $PSScriptRoot\config\config-platforminstance-$($global:Environ.Instance.ToLower()).ps1
    Remove-Files $PSScriptRoot\definitions\definitions-platforminstance-$($global:Environ.Instance.ToLower()).ps1
    Remove-Files $PSScriptRoot\initialize\initialize-platforminstance-$($global:Environ.Instance.ToLower()).ps1
    Remove-Files $PSScriptRoot\preflight\preflight*-platforminstance-$($global:Environ.Instance.ToLower()).ps1
    Remove-Files $PSScriptRoot\postflight\postflight*-platforminstance-$($global:Environ.Instance.ToLower()).ps1

}

function Remove-PlatformFiles {

    Remove-Files $PSScriptRoot\config\config-platform-$($global:Environ.Platform.ToLower()).ps1
    Remove-Files $PSScriptRoot\definitions\definitions-platform-$($global:Environ.Platform.ToLower()).ps1
    Remove-Files $PSScriptRoot\initialize\initialize-platform-$($global:Environ.Platform.ToLower()).ps1
    Remove-Files $PSScriptRoot\preflight\preflight*-platform-$($global:Environ.Platform.ToLower()).ps1
    Remove-Files $PSScriptRoot\postflight\postflight*-platform-$($global:Environ.Platform.ToLower()).ps1
    Remove-Files $PSScriptRoot\services\services-$($global:Environ.Platform.ToLower())*.ps1

}

function Remove-OSFiles {

    Remove-Files $PSScriptRoot\config\config-os-$($global:Environ.OS.ToLower()).ps1
    Remove-Files $PSScriptRoot\definitions\definitions-os-$($global:Environ.OS.ToLower()).ps1
    Remove-Files $PSScriptRoot\initialize\initialize-os-$($global:Environ.OS.ToLower()).ps1
    Remove-Files $PSScriptRoot\preflight\preflight*-os-$($global:Environ.OS.ToLower()).ps1
    Remove-Files $PSScriptRoot\postflight\postflight*-os-$($global:Environ.OS.ToLower()).ps1
    Remove-Files $PSScriptRoot\services\services-$($global:Environ.OS.ToLower())*.ps1

}

function Remove-CoreFiles {

    $files = (Get-ChildItem $PSScriptRoot\source\core -File -Recurse -Exclude uninstall.ps1).VersionInfo.FileName
    foreach ($file in $files) { Remove-Files $file.replace("\source\core","")}
    
    $coreDirectories = @("config","definitions","docs","img","initialize","logs","preflight","postflight","providers","services","temp")
    foreach ($coreDirectory in $coreDirectories) {
        if (Test-Path "$PSScriptRoot\$coreDirectory") {
            Remove-Item "$PSScriptRoot\$coreDirectory" -Recurse}
    }

    Remove-Files $PSScriptRoot\environ.ps1
    Remove-Files $PSScriptRoot\uninstall.ps1

}

function Update-Environ {

    param(
        [Parameter(Mandatory=$false)][ValidateSet("Overwatch","Provider","Product")][Alias("Provider","Product")][string]$Type,
        [Parameter(Mandatory=$false)][string]$Name
    )

    if ($Type -eq "Overwatch") {
        Copy-File "$PSScriptRoot\source\environ\environ-template.ps1" "$PSScriptRoot\environ.ps1" -Component Environ -WhatIf -Quiet
    }
    
    $environItems = Select-String $PSScriptRoot\environ.ps1 -Pattern "$Type = " -Raw
    $updatedEnvironItems = $environItems.Replace("`"$Name`"","").Replace(", ,",",").Replace("(, ","(").Replace(", )",")")
    $content = Get-Content $PSScriptRoot\environ.ps1 
    $newContent = $content | Foreach-Object {$_.Replace($environItems,$updatedEnvironItems)}
    Set-Content $PSScriptRoot\environ.ps1 -Value $newContent

}

function Uninstall-Provider {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Provider,
        [switch]$Force
    )

    $providerToUninstall = Get-Provider $Provider
    if (!$Force -and $providerToUninstall.Installation.Flag -eq "UninstallProtected") { return }

    $Name = $providerToUninstall.Name ?? $Provider
    $Publisher = $providerToUninstall.Publisher ?? $global:Catalog.Provider.$Provider.Publisher

    $message = "    $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    
    if (Test-Path -Path $PSScriptRoot\install\uninstall-provider-$($providerToUninstall.Id).ps1) {. $PSScriptRoot\install\uninstall-provider-$($providerToUninstall.Id).ps1}

    Remove-ProviderFiles $Provider
    Update-Environ -Type Provider -Name $Provider
    Get-Provider -ResetCache | Out-Null
    
    $message = "$($emptyString.PadLeft(7,"`b"))UNINSTALLED"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

}

function Uninstall-Product {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Product,
        [switch]$Force
    )

    $productToUninstall = Get-Product $Product
    if (!$Force -and $productToUninstall.Installation.Flag -eq "UninstallProtected") { return }
    
    $Name = $productToUninstall.Name ?? $Product
    $Publisher = $productToUninstall.Publisher ?? $global:Catalog.Product.$Product.Publisher

    $message = "    $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

    if (Test-Path -Path $PSScriptRoot\install\uninstall-product-$($productToUninstall.Id).ps1) {. $PSScriptRoot\install\uninstall-product-$($productToUninstall.Id).ps1}

    if ($productToUninstall.HasTask -and $(Get-PlatformTask -Id $Product)) {
        
        $message = "$($emptyString.PadLeft(40,"`b"))STOPPING$($emptyString.PadLeft(12," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkYellow

        $isStopped = Stop-PlatformTask -Id $Product -Quiet
        $isStopped | Out-Null

        $message = "$($emptyString.PadLeft(20,"`b"))STOPPED$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red

        Unregister-PlatformTask -Id $Product

    }
    else {
        $message = "$($emptyString.PadLeft(40,"`b"))STOPPED$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red
    }

    $message = "$($emptyString.PadLeft(20,"`b"))DELETED$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red
        
    Remove-ProductFiles $Product
    Update-Environ -Type Product -Name $Product
    Get-Product -ResetCache | Out-Null

    if ($productToUninstall.HasTask) {
        $message = "UNINSTALLED$($emptyString.PadLeft(9," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }
    else {
        $message = "$($emptyString.PadLeft(20,"`b"))N/A$($emptyString.PadLeft(17," "))","UNINSTALLED"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGray, DarkGreen
    }

}

function Uninstall-Platform {

    [CmdletBinding()]
    Param (
        [switch]$Force
    )

    Remove-PlatformInstanceFiles
    Remove-PlatformFiles
    Remove-Files "$($global:Location.Data)\*.cache"

}

function Uninstall-OS { 

    [CmdletBinding()]
    Param (
        [switch]$Force
    )

    Remove-OSFiles 

}

function Uninstall-Overwatch { 
    
    [CmdletBinding()]
    Param (
        [switch]$Force
    )
    
    Remove-CoreFiles 
    Update-Environ -Type Overwatch

}

#region MAIN

    [console]::CursorVisible = $false

    Write-Host+ -ResetIndentGlobal

    if ((![string]::IsNullOrEmpty($Type) -and [string]::IsNullOrEmpty($Name)) -or 
        ([string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Name))) {
        throw "Both `"Type`" and `"Name`" must be specified or both must be null."
    }

    #region LoAD INSTALL SETTINGS
    
        if (Test-Path -Path $installSettingsFile) {
            . $installSettingsFile
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        } 

    #endregion LoAD INSTALL SETTINGS
    #region UNINSTALL PRODUCT/PROVIDER

        if (![string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Name)) {

            # this ensures the case is correct
            $Type = (Get-Culture).TextInfo.ToTitleCase($Type)
            if ($Type -eq "Product") { $Name = $global:Catalog.Product.Keys | Where-Object {$_ -eq $Name} }
            if ($Type -eq "Provider") { $Name = $global:Catalog.Provider.Keys | Where-Object {$_ -eq $Name} }

            [console]::CursorVisible = $true
            $uninstallTarget = ![string]::IsNullOrEmpty($Type) ? $Type : "Overwatch"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "Uninstall $($uninstallTarget.ToLower()) $Name (Y/N)? " -ForegroundColor DarkYellow
            $continue = Read-Host
            [console]::CursorVisible = $false
            if ($continue.ToUpper() -ne "Y") {
                Write-Host+ -NoTimestamp -NoTrace "Uninstall canceled." -ForegroundColor DarkYellow
                return
            }
            Write-Host+

            if ($global:Catalog.$Type.$Name.Installation.Flag -contains "UninstallProtected") {
                Write-Host+ -NoTrace "WARN: $Type `"$Name`" is protected and cannot be uninstalled." -ForegroundColor DarkYellow
                return
            }

            if (!(Invoke-Expression "Get-$Type $Name -ResetCache").IsInstalled) {
                Write-Host+ -NoTrace "WARN: $Type `"$Name`" is NOT installed." -ForegroundColor DarkYellow
                Write-Host+ -NoTrace "INFO: To uninstall anyway, add the -Force switch." -ForegroundColor DarkYellow
                if (!$Force) { return }
                Write-Host+
            }

            if ($Type -eq "Product") {
                $dependentProducts = @()
                foreach ($key in $global:Catalog.Product.Keys) {
                    if ([array]$global:Catalog.Product.$key.Installation.Prerequisite.Product -contains $Name) {
                        if ((Get-Product $key).IsInstalled) {
                            $dependentProducts += $key
                        }
                    }
                }
                if ($dependentProducts) {
                    Write-Host+ -NoTrace "ERROR: Unable to uninstall $($Type.ToLower()) $Name" -ForegroundColor Red
                    Write-Host+ -NoTrace "ERROR: $($dependentProducts -join ", ") $($dependentProducts.Count -eq 1 ? "is" : "are") dependent on $($Type.ToLower()) $Name`'s services" -ForegroundColor Red
                    return
                }
            }

            $message = "<  Uninstalling $($Type.ToLower())s <.>48> PENDING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
            Write-Host+

            switch ($Type) {
                "Provider" {
                    $message = "    Provider            Publisher           Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    --------            ---------           ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray    
                }
                "Product" {
                    $message = "    Product             Publisher           Task                Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    -------             ---------           ----                ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                }
            }

            $expression = "Uninstall-$Type $Name"
            $expression += $Force ? " -Force" : ""
            Invoke-Expression $expression

            Write-Host+
            $message = "<  Uninstalling $($Type.ToLower())s <.>48> SUCCESS"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
            Write-Host+

        }

    #endregion UNINSTALL PRODUCT/PROVIDER
    #region UNINSTALL OVERWATCH

        else {

            Write-Host+
            $message = "<$($Overwatch.DisplayName) <.>48> UNINSTALLING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
            Write-Host+

                #region PROVIDERS

                    $message = "<  Uninstalling providers <.>48> PENDING"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
                    Write-Host+

                    $message = "    Provider            Publisher           Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    --------            ---------           ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray            

                    $global:Environ.Provider | ForEach-Object {Uninstall-Provider $_}
                    
                    Write-Host+
                    $message = "<  Uninstalling providers <.>48> SUCCESS"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
                    Write-Host+

                #region PROVIDERS
                #region PRODUCTS

                    $message = "<  Uninstalling products <.>48> PENDING"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
                    Write-Host+

                    $message = "    Product             Publisher           Task                Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    -------             ---------           ----                ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray

                    $global:Environ.Product | ForEach-Object {Uninstall-Product $_}
                    
                    Write-Host+
                    $message = "<  Uninstalling products <.>48> SUCCESS"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
                    Write-Host+

                #endregion PRODUCTS    
                #region PLATFORM

                    $message = "<  Uninstalling $($global:Environ.Platform) platform <.>48> PENDING"
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

                    Uninstall-Platform

                    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                    Write-Host+

                #endregion PLATFORM    
                #region OS

                    $message = "<  Uninstalling $($global:Environ.OS) OS <.>48> PENDING"
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

                    Uninstall-OS

                    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                    Write-Host+

                #endregion OS    
                #region OVERWATCH

                    $message = "<  Uninstalling Overwatch <.>48> PENDING"
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

                    Uninstall-Overwatch

                    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                    Write-Host+

                #endregion OVERWATCH  

            $message = "<$($Overwatch.DisplayName) <.>48> UNINSTALLED"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen

        }

    #endregion UNINSTALL OVERWATCH
    #region UPDATE INSTALL SETTINGS

        if (Test-Path -Path $installSettingsFile) {

            Clear-Content -Path $installSettingsFile
            
            if ($UninstallTarget -ne "Overwatch") {

                . $PSScriptRoot\environ.ps1
                
                '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $installSettingsFile
                "Param()" | Add-Content -Path $installSettingsFile
                if (![string]::IsNullOrEmpty($operatingSystemId)) {
                    "`$operatingSystemId = ""$operatingSystemId""" | Add-Content -Path $installSettingsFile
                }
                if (![string]::IsNullOrEmpty($platformId)) {
                    "`$platformId = ""$platformId""" | Add-Content -Path $installSettingsFile
                }
                if (![string]::IsNullOrEmpty($platformInstallLocation)) {
                    "`$platformInstallLocation = ""$platformInstallLocation""" | Add-Content -Path $installSettingsFile
                }
                if (![string]::IsNullOrEmpty($platformInstanceId)) {
                    "`$platformInstanceId = ""$platformInstanceId""" | Add-Content -Path $installSettingsFile
                }
                if ($global:Environ.Product.Count -gt 0) {
                    "`$productIds = @('$($global:Environ.Product -join "', '")')" | Add-Content -Path $installSettingsFile
                }
                if ($global:Environ.Provider.Count -gt 0) {
                    "`$providerIds = @('$($global:Environ.Provider -join "', '")')" | Add-Content -Path $installSettingsFile
                }
                if (![string]::IsNullOrEmpty($imagesUri)) {
                    "`$imagesUri = [System.Uri]::new(""$imagesUri"")" | Add-Content -Path $installSettingsFile
                }
                if (![string]::IsNullOrEmpty($platformInstanceUri)) {
                    "`$platformInstanceUri = [System.Uri]::new(""$platformInstanceUri"")" | Add-Content -Path $installSettingsFile
                }
                if (![string]::IsNullOrEmpty($platformInstanceDomain)) {
                    "`$platformInstanceDomain = ""$platformInstanceDomain""" | Add-Content -Path $installSettingsFile
                }
                if ($platformInstanceNodes.Count -gt 0) {
                    "`$platformInstanceNodes = @('$($platformInstanceNodes -join "', '")')" | Add-Content -Path $installSettingsFile
                }
                if ($requiredPythonPackages.Count -gt 0) {
                    "`$requiredPythonPackages = @('$($requiredPythonPackages -join "', '")')" | Add-Content -Path $installSettingsFile
                }
            }
        }

    #endregion UPDATE INSTALL SETTINGS

    [console]::CursorVisible = $true

#endregion MAIN