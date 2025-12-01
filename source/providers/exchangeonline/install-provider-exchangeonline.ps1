param (
    [switch]$UseDefaultResponses
)

$_provider = Get-Catalog -Type $_provider -Id ExchangeOnline
$_provider | Out-Null

#region LOAD SETTINGS

    $exchangeOnlineSettings = "$PSScriptRoot\data\exchangeOnlineInstallSettings.ps1"
    if (Test-Path -Path $exchangeOnlineSettings) {
        . $exchangeOnlineSettings
    }

#endregion LOAD SETTINGS

    $interaction = $true

    Write-Host+; Write-Host+

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
        $tenantKey = ![string]::IsNullOrEmpty($tenantResponse) ? $tenantResponse : ($configuredTenants.Count -eq 1 ? $configuredTenants : $tenantKey)
        Write-Host+ -NoTrace -NoTimestamp "Tenant: $tenantKey" -IfDebug -ForegroundColor Yellow
        if ($configuredTenants -notcontains $tenantKey) {
            Write-Host+ -NoTrace -NoTimestamp "    Tenant must be one of the following: $($configuredTenants -join ", ")" -ForegroundColor Red
        }
    } until ($configuredTenants -contains $tenantKey)

#region EXCHANGE ONLINE CREDENTIALS

    if (![string]::IsNullOrEmpty($exchangeOnlineCredentials) -and $(Test-Credentials $exchangeOnlineCredentials -NoValidate)) {
        $creds = Get-Credentials $exchangeOnlineCredentials
    }
    else {
        if(!$interaction) { Write-Host+ }
        $interaction = $true
        $creds = Request-Credentials -Message "    Enter Exchange Online Credentials" 
        $creds | Set-Credentials $exchangeOnlineCredentials
    }

    try {
        Connect-ExchangeOnline -Credential $creds -DisableWAM -ShowBanner:$false
    }
    catch {
        Write-Host+ -NoTrace -NoTimestamp "    Exchange Online connection error" -ForegroundColor Red
        $creds = $null
    }

#endregion EXCHANGE ONLINE CREDENTIALS
#region SAVE SETTINGS

    if (Test-Path $exchangeOnlineSettings) {Clear-Content -Path $exchangeOnlineSettings}
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $exchangeOnlineSettings
    "Param()" | Add-Content -Path $exchangeOnlineSettings
    "`$tenantKey = `"$tenantKey`"" | Add-Content -Path $exchangeOnlineSettings
    "`$exchangeOnlineCredentials = `"$exchangeOnlineCredentials`"" | Add-Content -Path $exchangeOnlineSettings

    $creds | Set-Credentials "$exchangeOnlineCredentials"

#endregion SAVE SETTINGS