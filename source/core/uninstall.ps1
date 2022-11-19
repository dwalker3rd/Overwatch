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

#region MAIN

    [console]::CursorVisible = $false

    Write-Host+ -ResetIndentGlobal

    if ((![string]::IsNullOrEmpty($Type) -and [string]::IsNullOrEmpty($Name)) -or 
        ([string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Name))) {
        throw "Both `"Type`" and `"Name`" must be specified or both must be null."
    }

    #region LOAD INSTALL SETTINGS
    
        if (Test-Path -Path $installSettingsFile) {
            . $installSettingsFile
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        } 

    #endregion LOAD INSTALL SETTINGS
    #region UNINSTALL PRODUCT/PROVIDER

        if (![string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Name)) {

            # this ensures the case is correct
            $Type = (Get-Culture).TextInfo.ToTitleCase($Type)
            if ($Type -eq "Product") { $Name = $global:Catalog.Product.Keys | Where-Object {$_ -eq $Name} }
            if ($Type -eq "Provider") { $Name = $global:Catalog.Provider.Keys | Where-Object {$_ -eq $Name} }

            # This component is not installed
            if (!(Invoke-Expression "Get-$Type $Name -ResetCache").IsInstalled) {
                Write-Host+ -NoTrace "WARN: $Type `"$Name`" is NOT installed." -ForegroundColor DarkYellow
                Write-Host+ -Iff $(!($Force.IsPresent)) -NoTrace "INFO: To force the uninstall, add the -Force switch." -ForegroundColor DarkYellow
                Write-Host+ -Iff $($Force.IsPresent) -NoTrace "INFO: Uninstalling with FORCE." -ForegroundColor DarkYellow
                if (!$Force) { return }
                $Force = $false
                Write-Host+
            }

            Write-Host+ -Iff $($Force.IsPresent) -NoTrace "WARN: Ignoring -Force switch." -ForegroundColor DarkYellow
            Write-Host+ -Iff $($Force.IsPresent) 

            # This component is protected by the UninstallProtected catalog flag and cannot be uinstalled
            if ($global:Catalog.$Type.$Name.Installation.Flag -contains "UninstallProtected") {
                Write-Host+ -NoTrace "WARN: $Type `"$Name`" is protected and cannot be uninstalled." -ForegroundColor DarkYellow
                return
            }

            # check for dependencies on this component by other installed components
            # this component cannot be uninstalled if other installed components have dependencies on it
            $dependents = Get-CatalogDependents -Type $Type -Name $Name -Installed
            if ($dependents) {
                Write-Host+ -NoTrace "ERROR: Unable to uninstall the $Name $($Type.ToLower())" -ForegroundColor Red
                foreach ($dependent in $dependents) {
                    Write-Host+ -NoTrace "ERROR: The $($dependent.Name) $($dependent.Type) is dependent on the $Name $($Type.ToLower())" -ForegroundColor Red
                }
                Write-Host+
                return
            }

            # the inevitable "Are you sure?" prompt
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

        Update-InstallSettings 

    #endregion UPDATE INSTALL SETTINGS

    [console]::CursorVisible = $true

#endregion MAIN