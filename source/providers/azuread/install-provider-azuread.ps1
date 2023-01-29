
$Provider = Get-Catalog -Type Provider AzureAD
$Name = $Provider.Name 

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

#region LOAD SETTINGS

    $azureADSettings = "$PSScriptRoot\data\azureADInstallSettings.ps1"
    if (Test-Path -Path $azureADSettings) {
        . $azureADSettings
    }

#endregion LOAD SETTINGS

    $interaction = $true

    Write-Host+; Write-Host+
    # Write-Host+ -NoTrace -NoTimestamp "    Subscription and Tenant"
    # Write-Host+ -NoTrace -NoTimestamp "    -----------------------"

    $configuredTenants = Get-AzureTenantKeys 
    do {
        $tenantResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Select Tenant ", "$($configuredTenants ? "[$($configuredTenants -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $tenantResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $tenantKey = ![string]::IsNullOrEmpty($tenantResponse) ? $tenantResponse : $tenantKey
        Write-Host+ -NoTrace -NoTimestamp "Tenant: $tenantKey" -IfDebug -ForegroundColor Yellow
        if ($configuredTenants -notcontains $tenantKey) {
            Write-Host+ -NoTrace -NoTimestamp "    Tenant must be one of the following: $($configuredTenants -join ", ")" -ForegroundColor Red
        }
    } until ($configuredTenants -contains $tenantKey)

#region MSGRAPH CREDENTIALS

    do {

        if (![string]::IsNullOrEmpty($azureMsGraph) -and $(Test-Credentials $azureMsGraph -NoValidate)) {
            $creds = Get-Credentials $azureMsGraph
        }
        else {
            if(!$interaction) { Write-Host+ }
            $interaction = $true
            $creds = Request-Credentials -Message "    Enter MSGraph App Id/Secret" -Prompt1 "      App Id" -Prompt2 "      Secret"
            $creds | Set-Credentials "$tenantKey-msgraph"
        }

        try {
            Connect-AzureAD -Tenant $tenantKey
        }
        catch {}

        if ([string]::IsNullOrEmpty($global:Azure.$tenantKey.MsGraph.AccessToken)) {
            Write-Host+ -NoTrace -NoTimestamp "    Invalid MSGraph App Id or Secret." -ForegroundColor Red
            $creds = $null
        }

    } until (![string]::IsNullOrEmpty($global:Azure.$tenantKey.MsGraph.AccessToken))


#endregion MSGRAPH CREDENTIALS
#region SAVE SETTINGS

    if (Test-Path $azureADSettings) {Clear-Content -Path $azureADSettings}
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $azureADSettings
    "Param()" | Add-Content -Path $azureADSettings
    "`$tenantKey = `"$tenantKey`"" | Add-Content -Path $azureADSettings
    "`$azureMsGraph = `"$tenantKey-msgraph`"" | Add-Content -Path $azureADSettings

    $creds | Set-Credentials "$tenantKey-msgraph"

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