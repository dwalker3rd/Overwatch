Enable-WSManCredSSP -Role Server -Force
Enable-WSManCredSSP -Role Client -DelegateComputer * -Force
New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentialsWhenNTLMOnly -Force
New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name 1 -Value * -PropertyType String

$creds = Request-Credentials

# <Overwatch host> is the Overwatch host
invoke-command -authentication credssp -scriptblock {set-location f:\overwatch; pwsh command.ps1 show-platformstatus} -computername "<Overwatch host>" -Credential $creds