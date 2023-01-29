
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

$overwatchRoot = $PSScriptRoot -replace "\\install",""
$azureDefinitionsFile = "$overwatchRoot\definitions\definitions-cloud-azure.ps1"
if (Get-Content -Path $azureDefinitionsFile | Select-String "<azureAD(?:B2C)?TenantId>" -Quiet) {

    $interaction = $true

    Write-Host+

    do {

        do {

            if (![string]::IsNullOrEmpty($azureAdmin) -and $(Test-Credentials $azureAdmin -NoValidate)) {
                $creds = Get-Credentials $azureAdmin
            }
            else {
                if(!$interaction) { Write-Host+ }
                $interaction = $true
                $creds = Request-Credentials -Message "    Enter Azure Admin Credentials" -Prompt1 "      Username" -Prompt2 "      Password"
            }

            Write-Host+

            do {
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Azure Subscription ID ", "$($subscriptionId ? "[$subscriptionId] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
                if (!$UseDefaultResponses) {
                    $subscriptionIdResponse = Read-Host
                }
                else {
                    Write-Host+
                }
                $subscriptionId = ![string]::IsNullOrEmpty($subscriptionIdResponse) ? $subscriptionIdResponse : $subscriptionId
                if ([string]::IsNullOrEmpty($subscriptionId)) {
                    Write-Host+ -NoTrace -NoTimestamp "    NULL: Azure Subscription ID is required." -ForegroundColor Red
                    $subscriptionId = $null
                }
            } until ($subscriptionId)

            do {
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Azure Tenant ID ", "$($tenantId ? "[$tenantId] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
                if (!$UseDefaultResponses) {
                    $tenantIdResponse = Read-Host
                }
                else { 
                    Write-Host+
                }
                $tenantId = ![string]::IsNullOrEmpty($tenantIdResponse) ? $tenantIdResponse : $tenantId
                if ([string]::IsNullOrEmpty($tenantId)) {
                    Write-Host+ -NoTrace -NoTimestamp "    NULL: Azure tenant ID is required." -ForegroundColor Red
                    $tenantId = $null
                }
            } until ($tenantId)

            Write-Host+

            $azureProfile = Connect-AzAccount -Credential $creds -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            if (!$azureProfile) {
                $exception = [Microsoft.Azure.Commands.Common.Exceptions.AzPSAuthenticationFailedException](Get-Error).Exception
                if ($exception.DesensitizedErrorMessage -like "MFA*") {
                    $azureProfile = Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId
                }
            }

            if (!$azureProfile) {
                Write-Host+ -NoTrace -NoTimestamp "    Invalid Tenant ID, Subscription ID or Azure Admin Credentials." -ForegroundColor Red
                $tenantId = $subscriptionId = $creds = $null
            }

        } until ($azureProfile)

        # got the azure profile, therefore azure admin credentials are valid 
        $creds | Set-Credentials "$tenantKey-admin"

        $azTenant = Get-AzTenant -TenantId $tenantId

        $tenantDomain = $azTenant.DefaultDomain
        $tenantKey = ($azTenant.DefaultDomain -split "\.")[0]
        $tenantName = $azTenant.Name
        $tenantId = $azTenant.TenantId
        $tenantType = $azTenant.TenantType -replace "AAD","Azure AD"
        $subscriptionName = $azureProfile.Context.Subscription.Name
        $subscriptionId = $azureProfile.Context.Subscription.Id

        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "    Subscription: $subscriptionName ($subscriptionId)"
        Write-Host+ -NoTrace -NoTimestamp "    Tenant: $tenantName ($tenantId)"
        Write-Host+ -NoTrace -NoTimestamp "    DefaultDomain: $tenantDomain"
        Write-Host+ -NoTrace -NoTimestamp "    TenantType: $tenantType"
        Write-Host+

        $azureConfigurationResponse = Read-Host -Prompt "    Configure this Azure Subscription/Tenant? (Y/N)"
    
    } until ($azureConfigurationResponse.ToUpper().StartsWith("Y"))

    $_tenantType = $tenantType -eq "Azure AD" ? "azureAD" : "azureADB2C"

    $azureDefinitions = Get-Content -Path $azureDefinitionsFile
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)TenantDomain>", $tenantDomain
    $azureDefinitions = $azureDefinitions -replace "`"<$($_tenantType)TenantKeyNoQuotes>`"", $tenantKey
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)TenantKey>", $tenantKey
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)TenantName>", $tenantName
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)TenantId>", $tenantId
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)TenantType>", $tenantType
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)SubscriptionName>", $subscriptionName
    $azureDefinitions = $azureDefinitions -replace "<$($_tenantType)SubscriptionId>", $subscriptionId
    $azureDefinitions | Set-Content -Path $azureDefinitionsFile

    . $azureDefinitionsFile
    Initialize-AzureConfig -Reinitialize

    #region SAVE SETTINGS

        if (Test-Path $azureSettings) {Clear-Content -Path $azureSettings}
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $azureSettings
        "Param()" | Add-Content -Path $azureSettings
        "`$tenantId = `"$tenantId`"" | Add-Content -Path $azureSettings
        "`$subscriptionId = `"$subscriptionId`"" | Add-Content -Path $azureSettings
        "`$azureAdmin = `"$tenantKey-admin`"" | Add-Content -Path $azureSettings

    #endregion SAVE SETTINGS

}

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