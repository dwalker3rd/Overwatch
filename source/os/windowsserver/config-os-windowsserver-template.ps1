[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param()

$currentWarningPreference = $global:WarningPreference
$global:WarningPreference = "SilentlyContinue"

#region POWERSHELL REMOTING

    $message = "<Configuring Powershell remoting <.>48> PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    # this node is assumed to be the Overwatch controller for this platforminstance
    $thisNode = $env:COMPUTERNAME.ToLower()

    try {

        # configure basic powershell remoting config (for this node)
        $ignoreOutput = winrm quickconfig
        $ignoreOutput = enable-psremoting -skipnetworkprofilecheck -force
        $ignoreOutput = set-netfirewallrule -name "WINRM-HTTP-In-TCP-PUBLIC" -RemoteAddress Any

        # enable WSMan Credssp for both Server and Client (for this node)
        $ignoreOutput = Enable-WSManCredSSP -Role Server -Force
        $ignoreOutput = Enable-WSManCredSSP -Role Client -DelegateComputer $thisNode -Force

        # configure local group credssp policy (for this node)
        $ignoreOutput = New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentials -Force
        $ignoreOutput = New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -Name 1 -Value * -PropertyType String
        $ignoreOutput = New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentialsWhenNTLMOnly -Force
        $ignoreOutput = New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name 1 -Value * -PropertyType String

        # configure trusted hosts (for this node)
        $trustedHosts = Get-Item WSMan:\localhost\Client\TrustedHosts
        foreach ($node in (pt nodes -k)) {
            if ($node -notin $trustedHosts) {
                $ignoreOutput = Set-Item WSMan:\localhost\Client\TrustedHosts -Value $node -Concatenate -Force
            }
        }

        # enable WSMan Credssp for Server (for remote nodes)
        $psSessions = Get-PsSession+ -ComputerName (pt nodes -k | Where-Object {$_ -ne $thisNode})
        $ignoreOutput = Invoke-Command -ScriptBlock {Enable-WSManCredSSP -Role Server -Force} -Session $psSessions
        $ignoreOutput = Remove-PSSession $psSessions

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    }
    catch {
        $message = "$($emptyString.PadLeft(8,"`b")) FAILURE"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
    }

#endregion POWERSHELL REMOTING

$global:WarningPreference = $currentWarningPreference