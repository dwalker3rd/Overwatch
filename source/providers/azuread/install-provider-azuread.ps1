param (
    [switch]$UseDefaultResponses
)

    # Local version for installation only
    # The global Provider version isn't yet installed
    function Connect-AzureAD {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Tenant
        )

        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:Azure.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}

        $appCredentials = Get-Credentials $global:Azure.$tenantKey.MsGraph.Credentials
        if (!$appCredentials) {
            throw "Unable to find the MSGraph credentials `"$($global:Azure.$tenantKey.MsGraph.Credentials)`""
        }
        
        $appId = $appCredentials.UserName
        $appSecret = $appCredentials.GetNetworkCredential().Password
        $scope = $global:Azure.$tenantKey.MsGraph.Scope
        $tenantDomain = $global:Azure.$tenantKey.Tenant.Domain

        $uri = "https://login.microsoftonline.com/$tenantDomain/oauth2/v2.0/token"

        # Add-Type -AssemblyName System.Web

        $body = @{
            client_id = $appId
            client_secret = $appSecret
            scope = $scope
            grant_type = 'client_credentials'
        }

        $restParams = @{
            ContentType = 'application/x-www-form-urlencoded'
            Method = 'POST'
            Body = $body
            Uri = $uri
        }

        # request token
        $response = Invoke-RestMethod @restParams

        #TODO: try/catch for expired secret with critical messaging
        
        # headers
        $global:Azure.$tenantKey.MsGraph.AccessToken = "$($response.token_type) $($response.access_token)"

        return

    }

$_provider = Get-Catalog -Type $_provider -Id AzureAD
$_provider | Out-Null

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
        $tenantKey = ![string]::IsNullOrEmpty($tenantResponse) ? $tenantResponse : ($configuredTenants.Count -eq 1 ? $configuredTenants : $tenantKey)
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