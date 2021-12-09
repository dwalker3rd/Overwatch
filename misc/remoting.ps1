winrm quickconfig
enable-psremoting -skipnetworkprofilecheck -force
set-netfirewallrule -name "WINRM-HTTP-In-TCP-PUBLIC" -RemoteAddress Any

# <hosts> comma-separated list of hosts in the environ NOT including the Overwatch host
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<hosts>" -Concatenate

Get-PSSessionConfiguration
$session = New-PSSession -ComputerName localhost -ConfigurationName PowerShell.7
Invoke-Command -Session $session -ScriptBlock { $PSVersionTable }