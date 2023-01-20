
$Service = Get-Catalog -Type Service Azure
$Name = $Service.Name 
$Publisher = $Service.Publisher

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

$azureSettings = "$PSScriptRoot\data\azureInstallSettings.ps1"
if (Test-Path -Path $azureSettings) {
    . $azureSettings
}

$overwatchRoot = $PSScriptRoot -replace "\\install",""
$azureDefinitionsFile = "$overwatchRoot\definitions\definitions-service-azure.ps1"
if (Get-Content -Path $azureDefinitionsFile | Select-String "<tenantId>" -Quiet) {

    $interaction = $true

    Write-Host+; Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "    Azure Configuration"
    Write-Host+ -NoTrace -NoTimestamp "    -------------------"

    do {

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

        if (![string]::IsNullOrEmpty($azureAdmin) -and $(Test-Credentials $azureAdmin -NoValidate)) {
            $creds = Get-Credentials $azureAdmin
        }
        else {
            if(!$interaction) { Write-Host+ }
            $interaction = $true
            $creds = Request-Credentials -Prompt1 "    Azure Admin Username" -Prompt2 "    Azure Admin Password"
        }

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

    $azVmContext = Get-AzVmContext

    $tenantDomain = $azVmContext.Tenant.Domain
    $tenantKey = ($azVmContext.Tenant.Domain -split "\.")[0]
    $tenantName = $azVmContext.Tenant.Name
    $tenantId = $azVmContext.Tenant.Id
    $tenantType = $azVmContext.Tenant.Type -replace "AAD","Azure AD"
    $subscriptionName = $azVmContext.Subscription.Name
    $subscriptionId = $azVmContext.Subscription.Id

    $azureDefinitions = Get-Content -Path $azureDefinitionsFile
    $azureDefinitions = $azureDefinitions -replace "<tenantDomain>", $tenantDomain
    $azureDefinitions = $azureDefinitions -replace "`"<tenantKeyNoQuotes>`"", $tenantKey
    $azureDefinitions = $azureDefinitions -replace "<tenantKey>", $tenantKey
    $azureDefinitions = $azureDefinitions -replace "<tenantName>", $tenantName
    $azureDefinitions = $azureDefinitions -replace "<tenantId>", $tenantId
    $azureDefinitions = $azureDefinitions -replace "<tenantType>", $tenantType
    $azureDefinitions = $azureDefinitions -replace "<subscriptionName>", $subscriptionName
    $azureDefinitions = $azureDefinitions -replace "<subscriptionId>", $subscriptionId
    $azureDefinitions | Set-Content -Path $azureDefinitionsFile

    #region SAVE SETTINGS

        if (Test-Path $azureSettings) {Clear-Content -Path $azureSettings}
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $azureSettings
        "Param()" | Add-Content -Path $azureSettings
        "`$tenantId = `"$tenantId`"" | Add-Content -Path $azureSettings
        "`$subscriptionId = `"$subscriptionId`"" | Add-Content -Path $azureSettings
        "`$azureAdmin = `"$tenantKey-admin`"" | Add-Content -Path $azureSettings

        $creds | Set-Credentials "$tenantKey-admin"

    #endregion SAVE SETTINGS

}

if ($interaction) {
    Write-Host+
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGreen
}
else {
    $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen
}

[console]::CursorVisible = $cursorVisible