$Provider = Get-Provider -Id 'TwilioSMS'
$Provider | Out-Null

$message = "$($emptyString.PadLeft(7,"`b"))UNINSTALLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGreen