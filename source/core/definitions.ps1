﻿param(
    [switch]$MinimumDefinitions
)

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls13

#region ENVIRON

    . $PSScriptRoot\environ.ps1

#endregion ENVIRON
#region SYSINTERNALS

    . "$($global:Location.Definitions)\definitions-sysinternals.ps1"

#endregion SYSINTERNALS
#region POWERSHELL

    . "$($global:Location.Definitions)\definitions-powershell.ps1"

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
#region OVERWATCH DEFINITIONS
    
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-overwatch.ps1") {. "$($global:Location.Definitions)\definitions-overwatch.ps1"}

#endregion OVERWATCH DEFINITIONS
#region OS DEFINITIONS

    if (Test-Path -Path "$($global:Location.Definitions)\definitions-os-$($global:Environ.OS.ToLower()).ps1") {. "$($global:Location.Definitions)\definitions-OS-$($global:Environ.OS.ToLower()).ps1"}
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-cloud-$($global:Environ.Cloud.ToLower()).ps1") {. "$($global:Location.Definitions)\definitions-cloud-$($global:Environ.Cloud.ToLower()).ps1"}

#endregion OS DEFINITIONS
#region PLATFORM DEFINITIONS
    
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-platform-$($global:Environ.Platform.ToLower()).ps1") {. "$($global:Location.Definitions)\definitions-platform-$($global:Environ.Platform.ToLower()).ps1"}
    if (Test-Path -Path "$($global:Location.Definitions)\definitions-platformInstance-$($global:Environ.Instance.ToLower()).ps1") {. "$($global:Location.Definitions)\definitions-platformInstance-$($global:Environ.Instance.ToLower()).ps1"}

#endregion PLATFORM DEFINITIONS
#region LOADEARLY

    . "$($global:Location.Definitions)\definitions-services-loadearly.ps1"

#endregion LOADEARLY
#region SERVICES

    . "$($global:Location.Definitions)\definitions-services.ps1"

#endregion SERVICES
#region UPDATE CATALOG

    # once environ, catalog and services have all been loaded,
    # refresh/update each catalog object's installation status
    Update-Catalog

#endregion UPDATE CATALOG
#region MINIMUM DEFINITIONS RETURN

    if ($MinimumDefinitions) { 
        $providers = Get-Provider -ResetCache | Where-Object {$_.Installed -and $_.Installation.Flag -contains "AlwaysLoad"}
        if ($providers) {
            $providers.Id | ForEach-Object {
                if ((Test-Prerequisites -Uid "Provider.$($_)" -PrerequisiteType Installation -Quiet).Pass) {                    if (Test-Path -Path "$($global:Location.Providers)\provider-$($_).ps1") {
                        $null = . "$($global:Location.Providers)\provider-$($_).ps1"
                    }
                }
            }
        }
        return
    }

#endregion MINIMUM DEFINITIONS RETURN
#region PRODUCTS

    if (!$global:Environ.Product) {return}

    # reset product cache (all products installed for this platform)
    $products = Get-Product -ResetCache
    $products | Out-Null

    # define active/current product (based on $global:Product.Id)
    $productId = $global:Product.Id ?? "Command"
    $global:Product = (Get-Product -Id $productId) ?? @{ Id = $productId }

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
    Write-Host+ -NoTrace "  Control","$($global:Overwatch.DisplayName) $($global:Overwatch.Release)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    Write-Host+ -NoTrace "  Product","$($global:Product.Id)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    Write-Host+ -NoTrace "  Platform","$($global:Platform.Name)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ -NoTrace "  Instance","$($global:Platform.Instance)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    if ($global:Platform.Version) {
        Write-Host+ -NoTrace "  Version","$($global:Platform.Version)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    }
    if ($global:Platform.Build) {
        Write-Host+ -NoTrace "  Build","$($global:Platform.Build)" -ForegroundColor Gray,DarkBlue -Separator ":      "
    }
    Write-Host+ -NoTrace "  Products","$($products.Name -join ", ")" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ -NoTrace "  Providers","$($global:Environ.Provider -join ', ')" -ForegroundColor Gray,DarkBlue -Separator ":  "
    Write-Host+ -NoTrace "  Cloud","$($global:Environ.Cloud)" -ForegroundColor Gray,DarkBlue -Separator ":      "

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
        Show-MessagingStatus
    }

    Show-PlatformStatus -Required -Issues

    $_platformTasksDisabled = Get-PlatformTask -Disabled
    if ($_platformTasksDisabled.Count -gt 0) {
        Write-Host+
        Write-Host+ -NoTrace "Some platform tasks are DISABLED" -ForegroundColor DarkYellow
        if ($global:Product.HasTask) {
            if (Get-PlatformTask -Id $global:Product.Id -Disabled) {
                Write-Host+ -NoTrace "The platform task for","$($Overwatch.DisplayName) $($Product.Id)","is DISABLED" -ForegroundColor DarkYellow,DarkBlue,DarkYellow
            }
        }
        Write-Host+ -SetIndentGlobal 0 -SetTimeStampGlobal Exclude -SetTraceGlobal Exclude
        $_platformTasksDisabled | Show-PlatformTasks
        Write-Host+ -SetIndentGlobal $_indent -SetTimeStampGlobal Ignore -SetTraceGlobal Ignore
    }

#endregion WARNINGS
#region CLOSE

    Write-Host+ -Iff (!$_warnings)
    $message = "<$($Overwatch.DisplayName) $($Product.Id) <.>48> READY"
    Write-Host+ -NoTrace -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGreen
    Write-Host+
    
#endregion CLOSE