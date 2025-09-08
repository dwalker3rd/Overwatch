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

    $configuredTenants = Get-AzureTenantKeys 

    # fabric tenant
    do {
        $tenantResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Fabric tenant ", "$($configuredTenants ? "[$($configuredTenants -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray 
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

    # sharepoint tenant
    do {
        $tenantResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    SharePoint tenant ", "$($configuredTenants ? "[$($configuredTenants -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray 
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

#endregion TENANTS
#region SITE

    # sharepoint site
    do {
        $sharePointSite = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    SharePoint Site ", "[]", ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $sharePointSite = Read-Host
        }
        else {
            Write-Host+
            $interaction = $true
        }
        Write-Host+ -NoTrace -NoTimestamp "SharePoint Site: $sharePointSite" -IfDebug -ForegroundColor Yellow
    } until (![string]::IsNullOrEmpty($sharePointSite))    

#endregion SITE
#region SAVE SETTINGS

    if (Test-Path $spoSyncFabricSettings) {Clear-Content -Path $spoSyncFabricSettings}
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $exchangeOnlineSettings
    "Param()" | Add-Content -Path $spoSyncFabricSettings
    "`$fabricTenantKey = `"$fabricTenantKey`"" | Add-Content -Path $spoSyncFabricSettings
    "`$sharePointTenantKey = `"$sharePointTenantKey`"" | Add-Content -Path $spoSyncFabricSettings
    "`$sharePointSite = `"$sharePointSite`"" | Add-Content -Path $spoSyncFabricSettings

#endregion SAVE SETTINGS
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