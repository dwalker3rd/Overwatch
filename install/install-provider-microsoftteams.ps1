$Provider = Get-Provider -Id 'MicrosoftTeams'
$Provider | Out-Null

New-Log -Name "microsoftteams" | Out-Null