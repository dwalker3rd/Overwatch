$Provider = Get-Provider -Id 'TwilioSMS'

New-Log -Name "twiliosms" | Out-Null

if (!$(Test-Credentials $Provider.Id)) { 
    Request-Credentials -Prompt1 "Account SID" -Prompt2 "Auth Token" -Title "$($Provider.DisplayName) Credentials" -Message "Enter your $($Provider.DisplayName) credentials" | Set-Credentials $Provider.Id
}