param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureADSyncB2C"
$Id = $product.Id 

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

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

    $interaction = [string]::IsNullOrEmpty($subscriptionId) -or [string]::IsNullOrEmpty($tenantId) -or [string]::IsNullOrEmpty($azureAdmin)

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
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "AzureADSyncB2C"
}

if ($interaction) {
    Write-Host+
    $message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}
else {
    $message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
}

[console]::CursorVisible = $cursorVisible