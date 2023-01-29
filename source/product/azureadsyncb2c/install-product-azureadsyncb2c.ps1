param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureADSyncB2C"
$Name = $product.Name 

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
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

    # $overwatchRoot = $PSScriptRoot -replace "\\install",""
    # $azureDefinitionsFile = "$overwatchRoot\definitions\definitions-cloud-azure.ps1"
    # if (Get-Content -Path $azureDefinitionsFile | Select-String "<azureADTenantId>" -Quiet) {

        $interaction = $true

        Write-Host+; Write-Host+
        # Write-Host+ -NoTrace -NoTimestamp "    Subscription and Tenant"
        # Write-Host+ -NoTrace -NoTimestamp "    -----------------------"

        Update-AzureConfig -TenantId $tenantId -SubscriptionId $subscriptionId -Sync

        #region SAVE SETTINGS

            if (Test-Path $azureADSyncInstallSettings) {Clear-Content -Path $azureADSyncInstallSettings}
            '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $azureADSyncInstallSettings
            "Param()" | Add-Content -Path $azureADSyncInstallSettings
            "`$tenantId = `"$tenantId`"" | Add-Content -Path $azureADSyncInstallSettings
            "`$subscriptionId = `"$subscriptionId`"" | Add-Content -Path $azureADSyncInstallSettings
            # "`$azureADAdmin = `"$tenantKey-admin`"" | Add-Content -Path $azureSettings

        #endregion SAVE SETTINGS

    # }

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
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}
else {
    $message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
}

[console]::CursorVisible = $cursorVisible