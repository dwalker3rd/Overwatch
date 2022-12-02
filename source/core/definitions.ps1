[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls11  

#region ENVIRON

    . $PSScriptRoot\environ.ps1

#endregion ENVIRON
#region POWERSHELL

    . "$($global:Location.Definitions)\definitions-ps-powershell.ps1"

#endregion POWERSHELL
#region CLASSES

    . "$($global:Location.Definitions)\classes.ps1"

#endregion CLASSES
#region CATALOG

    . "$($global:Location.Definitions)\catalog.ps1"

#endregion CATALOG
#region HELP

    . "$($global:Location.Definitions)\definitions-help.ps1"

#endregion HELP 
#region REGEX

    . "$($global:Location.Definitions)\definitions-regex.ps1"

#endregion REGEX  
#region VIEWS

    . "$($global:Location.Definitions)\definitions-views.ps1"

#endregion VIEWS  
#region DEFINITIONS

    $global:epoch = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0
    
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-overwatch.ps1") {. "$($global:Location.Definitions)\definitions-overwatch.ps1"}
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-OS-$($global:Environ.OS).ps1") {. "$($global:Location.Definitions)\definitions-OS-$($global:Environ.OS).ps1"}
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-Platform-$($global:Environ.Platform).ps1") {. "$($global:Location.Definitions)\definitions-Platform-$($global:Environ.Platform).ps1"}
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-PlatformInstance-$($global:Environ.Instance).ps1") {. "$($global:Location.Definitions)\definitions-PlatformInstance-$($global:Environ.Instance).ps1"}

#endregion DEFINITIONS
#region LOADEARLY

    . "$($global:Location.Definitions)\definitions-services-loadearly.ps1"

#endregion LOADFIRST
#region SERVICES

    . "$($global:Location.Definitions)\definitions-services.ps1"

#endregion SERVICES
#region PRODUCTS

    if (!$global:Environ.Product) {return}

    # reset product cache (all products installed for this platform)
    $products = Get-Product -ResetCache
    $products | Out-Null

    # define active/current product (based on $global:Product.Id)
    $global:Product = (Get-Product -Id $global:Product.Id) ?? @{ Id = $global:Product.Id}

#endregion PRODUCTS
#region PROVIDERS

    $providers = Get-Provider -ResetCache
    $providers.Id | ForEach-Object {
        if (Test-Path -Path "$($global:Location.Providers)\provider-$($_).ps1") {
            $null = . "$($global:Location.Providers)\provider-$($_).ps1"
        }
    }

#endregion PROVIDERS
#region INITIALIZE

    # INITIALIZE section must be after PROVIDERS section

    . "$($global:Location.Definitions)\definitions-initialize.ps1"
    Initialize-Environment

    Get-PlatformInfo

#endregion INITIALIZE
#region INTRO

    $message = "<$($Overwatch.DisplayName) $($Product.Id) <.>48> PENDING"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+
    Write-Host+ "  Environ","$($Overwatch.DisplayName)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    Write-Host+ "  Product","$($Product.Id)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    Write-Host+ "  Platform","$($global:Platform.Name)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ "  Instance","$($global:Platform.Instance)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    if ($global:Platform.Version) {
        Write-Host+ "  Version","$($global:Platform.Version)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    }
    if ($global:Platform.Build) {
        Write-Host+ "  Build","$($Platform.Build)" -ForegroundColor Gray,DarkBlue -Separator ":      "
    }
    Write-Host+ "  Products","$($products.Name -join ", ")" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ "  Providers","$($global:Environ.Provider -join ', ')" -ForegroundColor Gray,DarkBlue -Separator ":  "

#endregion INTRO
#region PREFLIGHT

    . "$($global:Location.Definitions)\definitions-preflight.ps1"
    Confirm-Preflight

#endregion PREFLIGHT
#region POSTFLIGHT

. "$($global:Location.Definitions)\definitions-postflight.ps1"

#endregion POSTFLIGHT
#region WARNINGS

    if (IsMessagingDisabled) {
        Write-Host+
        Write-Host+ -NoTrace "Messaging DISABLED" -ForegroundColor DarkYellow
    }

#endregion WARNINGS
#region CLOSE

    Write-Host+ ""
    $message = "<$($Overwatch.DisplayName) $($Product.Id) <.>48> READY"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
    Write-Host+
    
#endregion CLOSE