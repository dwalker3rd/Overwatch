$Provider = Get-Provider -Id 'MicrosoftTeams'
$Provider | Out-Null

$message = "$($emptyString.PadLeft(7,"`b"))UNINSTALLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGreen