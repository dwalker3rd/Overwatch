param (
    [switch]$UseDefaultResponses
)

$Provider = Get-Provider -Id 'TwilioSMS'
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    $interaction = $false

    $twilioSmsSettings = "$PSScriptRoot\data\twilioInstallSettings.ps1"
    if (Test-Path -Path $twilioSmsSettings) {
        . $twilioSmsSettings
    }

    $overwatchRoot = $PSScriptRoot -replace "\\install",""
    if (Get-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1 | Select-String "<SMS From>" -Quiet) {

        $interaction = $true

        if (!$global:WriteHostPlusEndOfLine) { Write-Host+ } # close any pending newline

        Write-Host+

        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Twilio phone number ", "$($fromPhone ? "[$fromPhone] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $fromPhoneResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $fromPhone = ![string]::IsNullOrEmpty($fromPhoneResponse) ? $fromPhoneResponse : $fromPhone
            $fromPhone = $fromPhone.Replace(" ","").Replace("-","")
            if ([string]::IsNullOrEmpty($fromPhone)) {
                Write-Host+ -NoTrace -NoTimestamp "    NULL: Twilio phone number is required" -ForegroundColor Red
                $fromPhone = $null
            }
            if ($fromPhone -notmatch "^\+{0,1}[0-9]*$") {
                Write-Host+ -NoTrace -NoTimestamp "    INVALID: Format must match `"^\+{0,1}[0-9]*$`"" -ForegroundColor Red
                $fromPhone = $null
            }
        } until ($fromPhone)

        $twilioSmsDefinitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1
        $twilioSmsDefinitionsFile = $twilioSmsDefinitionsFile -replace "<SMS From>", $fromPhone
        $twilioSmsDefinitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1

        #region SAVE SETTINGS

            if (Test-Path $twilioSmsSettings) {Clear-Content -Path $twilioSmsSettings}
            '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $twilioSmsSettings
            "Param()" | Add-Content -Path $twilioSmsSettings
            "`$fromPhone = `"$fromPhone`"" | Add-Content -Path $twilioSmsSettings

        #endregion SAVE SETTINGS
        
    }

    if (!$(Test-Credentials $Provider.Id -NoValidate)) { 
        if (!$global:WriteHostPlusEndOfLine) { Write-Host+ } # close any pending newline
        $interaction = $true
        Request-Credentials -Title "    Twilio Account Credentials" -Prompt1 "    Account SID" -Prompt2 "    Auth Token" | Set-Credentials $Provider.Id
    }

    if ($interaction) {
        Write-Host+
    }

#endregion PROVIDER-SPECIFIC INSTALLATION