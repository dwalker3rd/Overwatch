
$Cloud = Get-Catalog -Type Cloud Azure
$Name = $Cloud.Name 

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Remove-Variable subscriptionId -ErrorAction SilentlyContinue
Remove-Variable tenantId -ErrorAction SilentlyContinue

$azureSettings = "$PSScriptRoot\data\azureInstallSettings.ps1"
if (Test-Path -Path $azureSettings) {
    . $azureSettings
}

$interaction = ![string]::IsNullOrEmpty($subscriptionId) -or ![string]::IsNullOrEmpty($tenantId) -or ![string]::IsNullOrEmpty($azureAdmin)

Update-AzureConfig -SubscriptionId $subscriptionId -TenantId $tenantId -Credentials $azureAdmin

#region SAVE SETTINGS

    if (Test-Path $azureSettings) {Clear-Content -Path $azureSettings}
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $azureSettings
    "Param()" | Add-Content -Path $azureSettings
    "`$tenantId = `"$tenantId`"" | Add-Content -Path $azureSettings
    "`$subscriptionId = `"$subscriptionId`"" | Add-Content -Path $azureSettings
    "`$azureAdmin = `"$tenantKey-admin`"" | Add-Content -Path $azureSettings

#endregion SAVE SETTINGS

if ($interaction) {
    Write-Host+
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGreen
}
else {
    $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen
}

[console]::CursorVisible = $cursorVisible