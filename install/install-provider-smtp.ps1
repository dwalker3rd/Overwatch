$Provider = Get-Provider -Id 'SMTP'

New-Log -Name "smtp" | Out-Null

if (!$(Test-Credentials $Provider.Id -NoValidate)) {
    Request-Credentials -Prompt1 "Account" -Prompt2 "Password" -Title "$($Provider.DisplayName) Credentials" -Message "Enter your $($Provider.DisplayName) credentials" | Set-Credentials $Provider.Id
}