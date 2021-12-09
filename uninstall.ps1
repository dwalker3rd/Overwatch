#Requires -RunAsAdministrator
#Requires -Version 7

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

#region MODULES-PACKAGES

    # if (!(Get-PackageSource -ProviderName PowerShellGet)) {
    #     Register-PackageSource -Name PSGallery -Location "https://www.powershellgallery.com/api/v2" -ProviderName PowerShellGet -ErrorAction SilentlyContinue | Out-Null
    # }
    # $requiredModules = @("PsIni")
    # foreach ($module in $requiredModules) {
    #     if (!(Get-Module -Name $module -ErrorAction SilentlyContinue | Out-Null)) {
    #         Install-Module -Name $module -ErrorAction SilentlyContinue | Out-Null
    #         Import-Module -Name $module -ErrorAction SilentlyContinue | Out-Null
    #     }
    # }

    # if (!(Get-PackageSource -ProviderName NuGet -ErrorAction SilentlyContinue)) {
    #     Register-PackageSource -Name Nuget -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -ErrorAction SilentlyContinue | Out-Null
    # }
    # $requiredPackages = @("Portable.BouncyCastle","MimeKit","MailKit")
    # foreach ($package in $requiredPackages) {
    #     if (!(Get-Package -Name $package -ErrorAction SilentlyContinue)) {
    #         Install-Package -Name $package -SkipDependencies -Force | Out-Null
    #     }
    # }

#endregion MODULES-PACKAGES

function global:Uninstall-Platform {

    [CmdletBinding()] Param()

}

function global:Uninstall-Product {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context
    )

    $productToUninstall = Get-Product $Context
    Write-Host+ -NoTrace "    $($productToUninstall.Name) by $($productToUninstall.Vendor)"

    if (Test-Path -Path $PSScriptRoot\uninstall\uninstall-product-$($productToUninstall.Id).ps1) {. $PSScriptRoot\uninstall\uninstall-product-$($productToUninstall.Id).ps1}
}

function global:Uninstall-Provider {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$ProviderName
    )

    $providerToUninstall = Get-Provider $ProviderName
    Write-Host+ -NoTrace "    $($providerToUninstall.DisplayName) ($($providerToUninstall.Category)) by $($providerToUninstall.Vendor)"

    # . $PSScriptRoot\definitions.ps1
    
    if (Test-Path -Path $PSScriptRoot\uninstall\uninstall-provider-$($providerToUninstall.Id).ps1) {. $PSScriptRoot\uninstall\uninstall-provider-$($providerToUninstall.Id).ps1}

}

#region MAIN

$emptyString = ""

Write-Host+
$message = "$($Overwatch.DisplayName) $($Product.Id) : PENDING"
Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
Write-Host+

    #region PROVIDERS

        $message = "  Uninstalling providers : PENDING"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
        Write-Host+

        $global:Environ.Provider | ForEach-Object {Uninstall-Provider $_}
        
        Write-Host+
        $message = "  Uninstalling providers : SUCCESS"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
        Write-Host+

    #region PROVIDERS
    #region PRODUCTS

        $message = "  Uninstalling products : PENDING"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
        Write-Host+

        $global:Environ.Product | ForEach-Object {Uninstall-Product $_}
        
        Write-Host+
        $message = "  Uninstalling products : SUCCESS"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
        Write-Host+

    #endregion PRODUCTS    
    # region PLATFORM

        $message = "  Configuring $($Platform.Name) platform : PENDING"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray

        Uninstall-Platform

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        Write-Host+

    #endregion PLATFORM    

$message = "$($Overwatch.DisplayName) $($Product.Id) : SUCCESS"
Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen

#endregion MAIN