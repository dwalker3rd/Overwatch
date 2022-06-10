$Provider = Get-Provider -Id 'TwilioSMS'
$Name = $Provider.Name 
$Publisher = $Provider.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

if (!(Get-Log -Name "twiliosms")) {
    New-Log -Name "twiliosms" | Out-Null
}

$interaction = $false
$overwatchRoot = $PSScriptRoot -replace "\\install",""
if (Get-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1 | Select-String "<fromPhone>" -Quiet) {

    $interaction = $true

    Write-Host+; Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "    Twilio SMS Configuration"
    Write-Host+ -NoTrace -NoTimestamp "    ------------------------"
    $fromPhone = Read-Host "      Twilio phone number"

    $smtpDefinitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1
    $smtpDefinitionsFile = $smtpDefinitionsFile -replace "<fromPhone>", $fromPhone
    $smtpDefinitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-provider-twiliosms.ps1
    
}

if (!$(Test-Credentials $Provider.Id -NoValidate)) { 
    if(!$interaction) {
        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "    Twilio SMS Configuration"
        Write-Host+ -NoTrace -NoTimestamp "    ------------------------"
    }
    $interaction = $true
    Request-Credentials -Prompt1 "      Account SID" -Prompt2 "      Auth Token" | Set-Credentials $Provider.Id
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