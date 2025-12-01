param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "AzureADSyncB2C"
$_product

Remove-Variable subscriptionId -ErrorAction SilentlyContinue
Remove-Variable tenantId -ErrorAction SilentlyContinue

$azureADSyncInstallSettings = "$PSScriptRoot\data\azureADSyncInstallSettings.ps1"
if (Test-Path -Path $azureADSyncInstallSettings) {
    . $azureADSyncInstallSettings
}

# installation requires default tenant to be Azure AD B2C
# TODO: make this a catalog installation prerequisite
if (!(Get-AzureTenantKeys -AzureADB2C)) { 
    Write-Host+ -NoTrace -NoTimestamp "    $($Product.Id) requires the default tenant to be an Azure AD B2C tenant." -ForegroundColor Red
    return
}

# if there is an Azure AD B2C tenant, but not an Azure AD tenant, configure an Azure AD tenant
# TODO: this section of code is duplicated in install-product-azureadsyncb2c.ps1, install-product-azureadsyncts.ps1 and install-azure.ps1; convert to a function in services-azure.ps1
if (!(Get-AzureTenantKeys -AzureAD)) {

    $azConfigUpdate = Update-AzureConfig -SubscriptionId $subscriptionId -TenantId $tenantId -Credentials $azureADAdmin
    
    #region SAVE SETTINGS
    
        if (Test-Path $azureSettings) {Clear-Content -Path $azureSettings}
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $azureSettings
        "Param()" | Add-Content -Path $azureSettings
        "`$tenantId = `"$($azConfigUpdate.TenantId)`"" | Add-Content -Path $azureSettings
        "`$subscriptionId = `"$($azConfigUpdate.SubscriptionId)`"" | Add-Content -Path $azureSettings
        "`$azureADAdmin = `"$($azConfigUpdate.Credentials)`"" | Add-Content -Path $azureSettings
    
    #endregion SAVE SETTINGS

}

foreach ($node in (pt nodes -k)) {
    $remotedirectory = "\\$node\$(($global:Azure.Location.Data).Replace(":","$"))"
    if (!(Test-Path $remotedirectory)) { 
        New-Item -ItemType Directory -Path $remotedirectory -Force | Out-Null
    }
}

$productTask = Get-PlatformTask -Id "AzureADSyncB2C"
if (!$productTask) {
    Register-PlatformTask -Id "AzureADSyncB2C" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AzureADSyncB2C").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RandomDelay $(New-TimeSpan -Minutes 3) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "AzureADSyncB2C"
}