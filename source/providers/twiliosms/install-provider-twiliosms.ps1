$Provider = Get-Provider -Id 'TwilioSMS'
$Name = $Provider.Name 
$Publisher = $Provider.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

if (!(Test-Log -Name $Provider.Id.ToLower())) {
    New-Log -Name $Provider.Id.ToLower() | Out-Null
}

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$twilioSmsSettings = "$PSScriptRoot\data\twilioInstallSettings.ps1"
if (Test-Path -Path $twilioSmsSettings) {
    . $twilioSmsSettings
}

$interaction = $false
$overwatchRoot = $PSScriptRoot -replace "\\install",""
if (Get-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1 | Select-String "<fromPhone>" -Quiet) {

    $interaction = $true

    Write-Host+; Write-Host+
    # Write-Host+ -NoTrace -NoTimestamp "    Twilio SMS Configuration"
    # Write-Host+ -NoTrace -NoTimestamp "    ------------------------"

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Twilio phone number ", "$($fromPhone ? "[$fromPhone] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
        $fromPhoneResponse = Read-Host
        $fromPhone = ![string]::IsNullOrEmpty($fromPhoneResponse) ? $fromPhoneResponse : $fromPhone
        $fromPhone = $fromPhone.Replace(" ","").Replace("-","")
        if ([string]::IsNullOrEmpty($fromPhone)) {
            Write-Host+ -NoTrace -NoTimestamp "NULL: Twilio phone number is required" -ForegroundColor Red
            $fromPhone = $null
        }
        if ($fromPhone -notmatch "^\+{0,1}[0-9]*$") {
            Write-Host+ -NoTrace -NoTimestamp "INVALID: Format must match `"^\+{0,1}[0-9]*$`"" -ForegroundColor Red
            $fromPhone = $null
        }
    } until ($fromPhone)

    $twilioSmsDefinitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1
    $twilioSmsDefinitionsFile = $twilioSmsDefinitionsFile -replace "<fromPhone>", $fromPhone
    $twilioSmsDefinitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1

    #region SAVE SETTINGS

        if (Test-Path $twilioSmsSettings) {Clear-Content -Path $twilioSmsSettings}
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $twilioSmsSettings
        "Param()" | Add-Content -Path $twilioSmsSettings
        "`$fromPhone = `"$fromPhone`"" | Add-Content -Path $twilioSmsSettings

    #endregion SAVE SETTINGS
    
}

if (!$(Test-Credentials $Provider.Id -NoValidate)) { 
    if(!$interaction) {
        Write-Host+
        # Write-Host+ -NoTrace -NoTimestamp "    Twilio SMS Configuration"
        # Write-Host+ -NoTrace -NoTimestamp "    ------------------------"
    }
    $interaction = $true
    Request-Credentials -Prompt1 "    Account SID" -Prompt2 "    Auth Token" | Set-Credentials $Provider.Id
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