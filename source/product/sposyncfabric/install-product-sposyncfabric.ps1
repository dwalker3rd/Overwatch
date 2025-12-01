param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "SPOSyncFabric"
$_productId = $_product.Id

#region GET SETTINGS

    $spoSyncFabricSettings = "$PSScriptRoot\data\spoSyncFabricInstallSettings.ps1"
    if (Test-Path -Path $spoSyncFabricSettings) {
        . $spoSyncFabricSettings
    }

#endregion GET SETTINGS
#region TENANTS

    $interaction = $true

    Write-Host+; Write-Host+

    if (!$global:Azure) { Initialize-AzureConfig }
    $configuredTenants = Get-AzureTenantKeys 

#region FABRIC

    do {
        $tenantResponse = $null
        
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Fabric tenant ", (![string]::IsNullOrEmpty($fabricTenantKey) ? "[$fabricTenantKey]" : $($configuredTenants ? "[$($configuredTenants -join ", ")]" : $null)), ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $tenantResponse = Read-Host
        }
        else {
            Write-Host+
            $interaction = $true
        }
        $fabricTenantKey = ![string]::IsNullOrEmpty($tenantResponse) ? $tenantResponse : ($configuredTenants.Count -eq 1 ? $configuredTenants : $fabricTenantKey)
        Write-Host+ -NoTrace -NoTimestamp "Fabric tenant: $fabricTenantKey" -IfDebug -ForegroundColor Yellow
        if ($configuredTenants -notcontains $fabricTenantKey) {
            Write-Host+ -NoTrace -NoTimestamp "    Fabric tenant must be one of the following: $($configuredTenants -join ", ")" -ForegroundColor Red
        }
    } until ($configuredTenants -contains $fabricTenantKey)      

#endregion FABRIC
#region SHAREPOINT    

    do {
        $tenantResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    SharePoint tenant ", (![string]::IsNullOrEmpty($sharePointTenantKey) ? "[$sharePointTenantKey]" : $($configuredTenants ? "[$($configuredTenants -join ", ")]" : $null)), ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $tenantResponse = Read-Host
        }
        else {
            Write-Host+
            $interaction = $true
        }
        $sharePointTenantKey = ![string]::IsNullOrEmpty($tenantResponse) ? $tenantResponse : ($configuredTenants.Count -eq 1 ? $configuredTenants : $sharePointTenantKey)
        Write-Host+ -NoTrace -NoTimestamp "SharePoint tenant: $sharePointTenantKey" -IfDebug -ForegroundColor Yellow
        if ($configuredTenants -notcontains $sharePointTenantKey) {
            Write-Host+ -NoTrace -NoTimestamp "    SharePoint tenant must be one of the following: $($configuredTenants -join ", ")" -ForegroundColor Red
        }
    } until ($configuredTenants -contains $sharePointTenantKey)      

    # sharepoint site
    do {
        $siteResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    SharePoint Site ", (![string]::IsNullOrEmpty($sharePointSite) ? "[$sharePointSite]" : $sharePointSite), ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $siteResponse = Read-Host
        }
        else {
            Write-Host+
            $interaction = $true
        }
        $sharePointSite = ![string]::IsNullOrEmpty($siteResponse) ? $siteResponse : $sharePointSite
        Write-Host+ -NoTrace -NoTimestamp "SharePoint Site: $sharePointSite" -IfDebug -ForegroundColor Yellow
    } until (![string]::IsNullOrEmpty($sharePointSite))    

#endregion SHAREPOINT
#region EXCHANGE ONLINE

    do {
        $tenantResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Exchange Online tenant ", (![string]::IsNullOrEmpty($exchangeOnlineTenantKey) ? "[$exchangeOnlineTenantKey]" : $($configuredTenants ? "[$($configuredTenants -join ", ")]" : $null)), ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $tenantResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $exchangeOnlineTenantKey = ![string]::IsNullOrEmpty($tenantResponse) ? $tenantResponse : ($configuredTenants.Count -eq 1 ? $configuredTenants : $exchangeOnlineTenantKey)
        Write-Host+ -NoTrace -NoTimestamp "Exchange Online tenant: $exchangeOnlineTenantKey" -IfDebug -ForegroundColor Yellow
        if ($configuredTenants -notcontains $exchangeOnlineTenantKey) {
            Write-Host+ -NoTrace -NoTimestamp "    Exchange Online tenant must be one of the following: $($configuredTenants -join ", ")" -ForegroundColor Red
        }
    } until ($configuredTenants -contains $exchangeOnlineTenantKey)

    $requestedCredentials = $false
    $creds = Get-Credentials "$exchangeOnlineTenantKey-exchangeonline"
    if (!$creds) {
        $requestedCredentials = $true
        if(!$interaction) { Write-Host+ }
        $interaction = $true
        $creds = Request-Credentials -Message "    Exchange Online credentials" 
    }

    try {
        Connect-ExchangeOnline -Credential $creds -DisableWAM -ShowBanner:$false
        if ($requestedCredentials) {
            $creds | Set-Credentials "$exchangeOnlineTenantKey-exchangeonline"
        }
    }
    catch {
        Write-Host+ -NoTrace -NoTimestamp "    Invalid Exchange Online credentials" -ForegroundColor Red
        $creds = $null
    }   

#endregion EXCHANGE ONLINE
#region SAVE SETTINGS

    if (Test-Path $spoSyncFabricSettings) {Clear-Content -Path $spoSyncFabricSettings}
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $spoSyncFabricSettings
    "Param()" | Add-Content -Path $spoSyncFabricSettings
    "`$fabricTenantKey = `"$fabricTenantKey`"" | Add-Content -Path $spoSyncFabricSettings
    "`$sharePointTenantKey = `"$sharePointTenantKey`"" | Add-Content -Path $spoSyncFabricSettings
    "`$sharePointSite = `"$sharePointSite`"" | Add-Content -Path $spoSyncFabricSettings
    "`$exchangeOnlineTenantKey = `"$exchangeOnlineTenantKey`"" | Add-Content -Path $spoSyncFabricSettings   

#endregion SAVE SETTINGS
#region UPDATE TEMPLATE

    $overwatchRoot = $PSScriptRoot -replace "\\install",""
    $destinationFile = "$overwatchRoot\definitions\definitions-product-$($_product.Id.ToLower()).ps1"
    $spoSyncFabricDefinitionsFile = Get-Content -Path $destinationFile
    $spoSyncFabricDefinitionsFile = $spoSyncFabricDefinitionsFile -replace "<sharePointTenantKey>", $sharePointTenantKey
    $spoSyncFabricDefinitionsFile = $spoSyncFabricDefinitionsFile -replace "<sharePointSite>", $sharePointSite
    $spoSyncFabricDefinitionsFile = $spoSyncFabricDefinitionsFile -replace "<fabricTenantKey>", $fabricTenantKey
    $spoSyncFabricDefinitionsFile = $spoSyncFabricDefinitionsFile -replace "<exchangeOnlineTenantKey>", $exchangeOnlineTenantKey
    $spoSyncFabricDefinitionsFile | Set-Content  -Path $destinationFile

#endregion UPDATE TEMPLATE
#region REGISTER PLATFORMTASK

    $productTask = Get-PlatformTask -Id $_productId
    if (!$productTask) {
        Register-PlatformTask -Id $_productId -execute $pwsh -Argument "$($global:Location.Scripts)\$($_productId).ps1" -WorkingDirectory $global:Location.Scripts `
            -Once -At $(Get-Date).AddMinutes(15) -RepetitionInterval $(New-TimeSpan -Minutes 15) `
            -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable
        $productTask = Get-PlatformTask -Id $_productId
    }

#endregion REGISTER PLATFORMTASK

if ($interaction) {
    Write-Host+
}