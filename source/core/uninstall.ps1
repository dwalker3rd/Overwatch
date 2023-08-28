#Requires -RunAsAdministrator
#Requires -Version 7

param(
    [Parameter(Mandatory=$false,Position=0)][ValidateSet("Cloud","Provider","Product")][string]$Type,
    [Parameter(Mandatory=$false,Position=1)][string]$Id,
    [switch]$Force
)

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"
$global:ConfirmPreference = "None"

$global:Product = @{Id="Uninstall"}
. $PSScriptRoot\definitions.ps1
. $PSScriptRoot\services\services-overwatch-install.ps1

#region MAIN

    Set-CursorInvisible

    Write-Host+ -ResetIndentGlobal

    if ((![string]::IsNullOrEmpty($Type) -and [string]::IsNullOrEmpty($Id)) -or 
        ([string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Id))) {
        throw "Both `"Type`" and `"Id`" must be specified or both must be null."
    }

    #region LOAD INSTALL SETTINGS
    
        if (Test-Path -Path $($global:InstallSettings)) {
            . $($global:InstallSettings)
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        } 

    #endregion LOAD INSTALL SETTINGS
    #region UNINSTALL SINGLE CATALOG OBJECT

        if (![string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Id)) {

            $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}
            $Id = $global:Catalog.$Type.$Id.Id
            $catalogObject = Get-Catalog -Type $Type -Id $Id

            # This component is not installed
            if (!$catalogObject.IsInstalled()) {
                Write-Host+ -NoTrace "WARN: $Type `"$Id`" is NOT installed." -ForegroundColor DarkYellow
                Write-Host+ -Iff $(!($Force.IsPresent)) -NoTrace "INFO: To force the uninstall, add the -Force switch." -ForegroundColor DarkYellow
                Write-Host+ -Iff $($Force.IsPresent) -NoTrace "INFO: Uninstalling with FORCE." -ForegroundColor DarkYellow
                if (!$Force) { return }
                $Force = $false
                Write-Host+
            }

            Write-Host+ -Iff $($Force.IsPresent) -NoTrace "WARN: Ignoring -Force switch." -ForegroundColor DarkYellow
            Write-Host+ -Iff $($Force.IsPresent) 

            # This component is protected by the UninstallProtected catalog flag and cannot be uinstalled
            if ($global:Catalog.$Type.$Id.Installation.Flag -contains "UninstallProtected") {
                Write-Host+ -NoTrace "WARN: $Type `"$Id`" is protected and cannot be uninstalled." -ForegroundColor DarkYellow
                return
            }

            # check for dependencies on this component by other installed components
            # this component cannot be uninstalled if other installed components have dependencies on it
            $dependents = Get-CatalogDependents -Type $Type -Id $Id | 
                ForEach-Object {Invoke-Expression "Get-$($_.Type) $($_.Id)"} | 
                    Where-Object {$_.IsInstalled()}
            if ($dependents) {
                Write-Host+ -NoTrace "ERROR: Unable to uninstall the $Id $($Type.ToLower())" -ForegroundColor Red
                foreach ($dependent in $dependents) {
                    Write-Host+ -NoTrace "ERROR: The $($dependent.Id) $($dependent.Type) is dependent on the $Id $($Type.ToLower())" -ForegroundColor Red
                }
                Write-Host+
                return
            }
    
            # delete/retain definitions, install setttings and data
            $deleteAllData = $false
            Set-CursorVisible
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Delete data for $Type $Id (Y/N)? ", "[N]", ": " -ForegroundColor DarkYellow, Blue, DarkYellow
            $continue = Read-Host
            Set-CursorInvisible
            $deleteAllData = $continue.ToUpper() -eq "Y"

            # the inevitable "Are you sure?" prompt
            Set-CursorVisible
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Uninstall $Type $Id $($deleteAllData ? "and delete ALL data" : $null) (Y/N)? ", "[N]", ": " -ForegroundColor DarkYellow, Blue, DarkYellow
            $continue = Read-Host
            Set-CursorInvisible
            if ($continue.ToUpper() -ne "Y") {
                Write-Host+ -NoTimestamp -NoTrace "Uninstall canceled." -ForegroundColor DarkYellow
                return
            }
            Write-Host+

            $message = "<  Uninstalling $($Type.ToLower())s <.>48> PENDING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
            Write-Host+ 

            switch ($Type) {
                default {
                    $message = "    $($Type)$($emptyString.PadLeft(20-$Type.Length," "))Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    $($emptyString.PadLeft($Type.Length,"-"))$($emptyString.PadLeft(20-$Type.Length," "))------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray                       
                }
                "Product" {
                    $message = "    Product             Task                Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    -------             ----                ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                }
            }

            Uninstall-CatalogObject -Type $Type -Id $Id -DeleteAllData:$deleteAllData -Force:$Force.IsPresent
            # $expression = "Uninstall-$Type $Id"
            # $expression += $Force ? " -Force" : ""
            # Invoke-Expression $expression

            Write-Host+
            $message = "<  Uninstalling $($Type.ToLower())s <.>48> SUCCESS"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
            Write-Host+

        }

    #endregion UNINSTALL SINGLE CATALOG OBJECT
    #region UNINSTALL OVERWATCH

        else {

            # delete/retain definitions, install setttings and data
            $deleteAllData = $false
            Set-CursorVisible
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Delete ALL data (Y/N)? ", "[N]", ": " -ForegroundColor DarkYellow, Blue, DarkYellow
            $continue = Read-Host
            Set-CursorInvisible
            $deleteAllData = $continue.ToUpper() -eq "Y"

            # the inevitable "Are you sure?" prompt
            Set-CursorVisible
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Uninstall Overwatch $($deleteAllData ? "and delete ALL data" : $null) (Y/N)? ", "[N]", ": " -ForegroundColor DarkYellow, Blue, DarkYellow
            $continue = Read-Host
            Set-CursorInvisible
            if ($continue.ToUpper() -ne "Y") {
                Write-Host+ -NoTimestamp -NoTrace "Uninstall canceled." -ForegroundColor DarkYellow
                return
            }
            Write-Host+

            Write-Host+
            $message = "<$($Overwatch.DisplayName) <.>48> UNINSTALLING"
            Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
            Write-Host+

                #region PROVIDERS

                    $message = "<  Uninstalling providers <.>48> PENDING"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
                    Write-Host+

                    $message = "    Provider            Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    --------            ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray            

                    $global:Environ.Provider | ForEach-Object {Uninstall-CatalogObject -Type Provider -Id $_}
                    
                    Write-Host+
                    $message = "<  Uninstalling providers <.>48> SUCCESS"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
                    Write-Host+

                #region PROVIDERS
                #region PRODUCTS

                    $message = "<  Uninstalling products <.>48> PENDING"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
                    Write-Host+

                    $message = "    Product             Task                Status"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                    $message = "    -------             ----                ------"
                    Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray

                    $global:Environ.Product | ForEach-Object {Uninstall-CatalogObject -Type Provider -Id $_}
                    
                    Write-Host+
                    $message = "<  Uninstalling products <.>48> SUCCESS"
                    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
                    Write-Host+

                #endregion PRODUCTS    
                #region CLOUD

                    $message = "<  Uninstalling $($global:Environ.Cloud) Cloud <.>48> PENDING"
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

                    Uninstall-CatalogObject -Type Cloud -Id $global:Environ.Cloud

                    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                    Write-Host+

                #endregion OS 
                #region PLATFORM

                    $message = "<  Uninstalling $($global:Environ.Platform) platform <.>48> PENDING"
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

                    Uninstall-CatalogObject -Type Platform -Id $global:Environ.Platform

                    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
                    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
                    Write-Host+

                #endregion PLATFORM    
                #region OS

                    $message = "<  Uninstalling $($global:Environ.OS) OS <.>48> PENDING"
                    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

                    Uninstall-CatalogObject -Type OS -$global:Environ.OS

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
    #region REMOVE PSSESSION
    
        Remove-PSSession+

    #endregion REMOVE PSSESSION

    Set-CursorVisible

#endregion MAIN