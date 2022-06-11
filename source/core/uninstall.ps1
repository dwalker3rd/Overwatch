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

function global:Uninstall-Platform {

    [CmdletBinding()] Param()

    #region REMOVE-CACHE

        Remove-Files "$($global:Location.Data)\*.cache"

    #endregion REMOVE-CACHE
}

function global:Uninstall-PlatformTask {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context
    )

    if ($(Get-PlatformTask -Id $Context)) {
        
        $message = "$($emptyString.PadLeft(40,"`b"))STOPPING$($emptyString.PadLeft(12," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkYellow

        $isStopped = Stop-PlatformTask -Id $Context
        $isStopped | Out-Null

        $message = "$($emptyString.PadLeft(20,"`b"))STOPPED$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red

        Unregister-PlatformTask -Id $Context

    }
    else {
        $message = "$($emptyString.PadLeft(40,"`b"))STOPPED$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red
    }

    $message = "$($emptyString.PadLeft(20,"`b"))DELETED$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red

    $message = "UNINSTALLED$($emptyString.PadLeft(9," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGreen

}

function global:Uninstall-Product {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context
    )

    $productToUninstall = Get-Product $Context
    $Name = $productToUninstall.Name 
    $Publisher = $productToUninstall.Publisher

    $message = "    $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

    if (Test-Path -Path $PSScriptRoot\install\uninstall-product-$($productToUninstall.Id).ps1) {. $PSScriptRoot\install\uninstall-product-$($productToUninstall.Id).ps1}

    Write-Host+

}

function global:Uninstall-Provider {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$ProviderName
    )

    $providerToUninstall = Get-Provider $ProviderName
    $Name = $providerToUninstall.Name 
    $Publisher = $providerToUninstall.Publisher

    $message = "    $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    
    if (Test-Path -Path $PSScriptRoot\install\uninstall-provider-$($providerToUninstall.Id).ps1) {. $PSScriptRoot\install\uninstall-provider-$($providerToUninstall.Id).ps1}

    Write-Host+

}

#region MAIN

    [console]::CursorVisible = $false

    Write-Host+ -ResetIndentGlobal

    Write-Host+
    $message = "$($Overwatch.DisplayName) $($Product.Id) : PENDING"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
    Write-Host+

        #region PROVIDERS

            $message = "  Uninstalling providers : PENDING"
            Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
            Write-Host+

            $message = "    Provider            Publisher           Status"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "    --------            ---------           ------"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray            

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

            $message = "    Product             Publisher           Task                Status"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "    -------             ---------           ----                ------"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray

            $global:Environ.Product | Where-Object {$_ -ne "Command"} | ForEach-Object {Uninstall-Product $_}
            
            Write-Host+
            $message = "  Uninstalling products : SUCCESS"
            Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
            Write-Host+

        #endregion PRODUCTS        
        # region PLATFORM

            $message = "  Deconfiguring $($Platform.Name) platform : PENDING"
            Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray

            Uninstall-Platform

            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
            Write-Host+

        #endregion PLATFORM        

    $message = "$($Overwatch.DisplayName) $($Product.Id) : COMPLETED"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen

    [console]::CursorVisible = $true

#endregion MAIN