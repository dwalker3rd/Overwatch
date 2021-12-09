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

$global:Product = @{Id="Install"}
. $PSScriptRoot\definitions.ps1

#region MODULES-PACKAGES

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

#endregion MODULES-PACKAGES
#region VAULT PROVIDER

    $providersPath = $global:Location.Providers
    foreach ($providerName in $Environ.Provider) {
        $provider = Get-Provider $providerName
        if ($provider.Category -eq "Security" -and $provider.SubCategory -eq "Vault") {
            if (Test-Path -Path $definitionsPath\definitions-provider-$($provider.Id).ps1) {
                $null = . $definitionsPath\definitions-provider-$($provider.Id).ps1
            }
            if (Test-Path -Path $providersPath\provider-$($provider.Id).ps1) {
                $null = . $providersPath\provider-$($provider.Id).ps1
            }
        }
    }  

#endregion VAULT PROVIDER

function global:Install-Platform {

    [CmdletBinding()] Param()

    #region DIRECTORIES

        foreach ($node in (Get-PlatformTopology nodes -Online -Keys)) {
            $parameters = @{
                Session = Get-PSSession+ -ComputerName $node
                ScriptBlock = {
                    Param($Directory)
                    New-Item -ItemType Directory -Path $Directory -Force | Select-Object FullName, PSComputerName
                }
            }
            Invoke-Command @parameters -ArgumentList $global:Location.Data | Out-Null
            Invoke-Command @parameters -ArgumentList $global:Location.Logs | Out-Null
            Invoke-Command @parameters -ArgumentList $global:Location.Temp | Out-Null
        }

    #endregion DIRECTORIES
    #region LOG

        New-Log -Name $Platform.Instance -WarningAction SilentlyContinue | Out-Null

    #endregion LOG
    #region CREDENTIALS

        if (!$(Test-Credentials "localadmin-$($global:Platform.Instance)")) { 
            Request-Credentials -Message "    Enter the local admin credentials" -Prompt1 "    User" -Prompt2 "    Password" | Set-Credentials "localadmin-$($global:Platform.Instance)"
        }

    #endregion CREDENTIALS
}

function global:Install-Product {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context
    )

    $productToInstall = Get-Product $Context
    Write-Host+ -NoTrace "    $($productToInstall.Name) by $($productToInstall.Vendor)"

    if (Test-Path -Path $PSScriptRoot\install\install-product-$($productToInstall.Id).ps1) {. $PSScriptRoot\install\install-product-$($productToInstall.Id).ps1}
}

function global:Install-Provider {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$ProviderName
    )

    $providerToInstall = Get-Provider $ProviderName
    Write-Host+ -NoTrace "    $($providerToInstall.DisplayName) ($($providerToInstall.Category)) by $($providerToInstall.Vendor)"

    # . $PSScriptRoot\definitions.ps1
    
    if (Test-Path -Path $PSScriptRoot\install\install-provider-$($providerToInstall.Id).ps1) {. $PSScriptRoot\install\install-provider-$($providerToInstall.Id).ps1}

}

#region MAIN

$emptyString = ""

Write-Host+
$message = "$($Overwatch.DisplayName) $($Product.Id) : PENDING"
Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
Write-Host+

    # region PLATFORM

        $message = "  Configuring $($Platform.Name) platform : PENDING"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray

        Install-Platform

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        Write-Host+

    #endregion PLATFORM
    #region PRODUCTS

        $message = "  Installing products : PENDING"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
        Write-Host+

        $global:Environ.Product | ForEach-Object {Install-Product $_}
        
        Write-Host+
        $message = "  Installing products : SUCCESS"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
        Write-Host+

    #endregion PRODUCTS
    #region PROVIDERS

        $message = "  Installing providers : PENDING"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
        Write-Host+

        $global:Environ.Provider | ForEach-Object {Install-Provider $_}
        
        Write-Host+
        $message = "  Installing providers : SUCCESS"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
        Write-Host+

    #region PROVIDERS

$message = "$($Overwatch.DisplayName) $($Product.Id) : COMPLETED"
Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen

#endregion MAIN