[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls11  

switch ($PSVersionTable.PSVersion.Major) {
    default {$global:pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"}
}

#region CLASSES

    $definitionsPath = "$($PSScriptRoot)\definitions"
    . $definitionsPath\classes.ps1

#endregion CLASSES
#region ENVIRON

    . $PSScriptRoot\environ.ps1

#endregion ENVIRON
#region HELP

    . $definitionsPath\definitions-help.ps1

#endregion HELP 
#region MISCELLANEOUS

    . $definitionsPath\definitions-regex.ps1

#endregion MISCELLANEOUS  
#region DEFINITIONS

    $global:epoch = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0
    
    if (Test-Path -Path $definitionsPath\definitions-overwatch.ps1) {. $definitionsPath\definitions-overwatch.ps1}
    if (Test-Path -Path $definitionsPath\definitions-OS-$($global:Environ.OS).ps1) {. $definitionsPath\definitions-OS-$($global:Environ.OS).ps1}
    if (Test-Path -Path $definitionsPath\definitions-Platform-$($global:Environ.Platform).ps1) {. $definitionsPath\definitions-Platform-$($global:Environ.Platform).ps1}
    if (Test-Path -Path $definitionsPath\definitions-PlatformInstance-$($global:Environ.Instance).ps1) {. $definitionsPath\definitions-PlatformInstance-$($global:Environ.Instance).ps1}

#endregion DEFINITIONS
#region LOADEARLY

    . $definitionsPath\definitions-services-loadearly.ps1

#endregion LOADFIRST
#region INTRO

    Write-Host+ -Clear
    $message = "$($Overwatch.DisplayName) $($Product.Id) : PENDING"
    Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
    Write-Host+
    Write-Host+ "  Environ","$($Overwatch.DisplayName)" -ForegroundColor Gray,DarkBlue -Separator ":    "
    Write-Host+ "  Product","$($Product.Id)" -ForegroundColor Gray,DarkBlue -Separator ":    "

#endregion INTRO
#region SERVICES

    . $definitionsPath\definitions-services.ps1

#endregion SERVICES

if ($Product.Id -in ("Install","Uninstall")) {

    Write-Host+ "  Platform","$($global:Platform.Name)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ "  Instance","$($global:Platform.Instance)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ "  Products","$($global:Environ.Product -join ", ")" -ForegroundColor Gray,DarkBlue -Separator ":   "  
    Write-Host+ "  Providers","$($global:Environ.Provider -join ', ')" -ForegroundColor Gray,DarkBlue -Separator ":  "

    . $definitionsPath\definitions-initialize.ps1
    Initialize-Environment

}
else {

    # Get-PlatformInfo -ResetCache
    # $global:Platform.DisplayName = "$($Platform.Name) $($Platform.Version)"

    Write-Host+ "  Platform","$($global:Platform.Name)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    Write-Host+ "  Instance","$($global:Platform.Instance)" -ForegroundColor Gray,DarkBlue -Separator ":   "
    # Write-Host+ "  Version","$($global:Platform.Version) ($($Platform.Build))" -ForegroundColor Gray,DarkBlue -Separator ":    "

    #region PRODUCTS

        if (!$global:Environ.Product) {return}

        # reset product cache (all products installed for this platform)
        $products = Get-Product -ResetCache
        $products | Out-Null

        # define active/current product (based on $global:Product.Id)
        $global:Product = Get-Product -Id $global:Product.Id

        Write-Host+ "  Products","$($products.Name -join ", ")" -ForegroundColor Gray,DarkBlue -Separator ":   "

    #endregion PRODUCTS
    #region PROVIDERS

        $providersPath = $global:Location.Providers
        $global:Environ.Provider | ForEach-Object {
            if (Test-Path -Path $definitionsPath\definitions-provider-$($_).ps1) {
                $null = . $definitionsPath\definitions-provider-$($_).ps1
            }
            if (Test-Path -Path $providersPath\provider-$($_).ps1) {
                $null = . $providersPath\provider-$($_).ps1
            }
        }

        Write-Host+ "  Providers","$($global:Environ.Provider -join ', ')" -ForegroundColor Gray,DarkBlue -Separator ":  "

    #endregion PROVIDERS
    #region INITIALIZE

        . $definitionsPath\definitions-initialize.ps1
        Initialize-Environment

    #endregion INITIALIZE
    #region PREFLIGHT

        . $definitionsPath\definitions-preflight.ps1
        Confirm-Preflight

    #endregion PREFLIGHT
    #region POSTFLIGHT

    . $definitionsPath\definitions-postflight.ps1

    #endregion POSTFLIGHT

    #region CLOSE

        Write-Host+
        $message = "$($Overwatch.DisplayName) $($Product.Id) : READY"
        Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGreen
        Write-Host+
        
    #endregion CLOSE

}