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

        # if the PowerShell.7 PSSessionConfiguration is not the current/installed version of PowerShell, unregister it
        # enable-psremoting (next step) will recreate the PowerShell.7 PSSessionConfiguration with the current/installed PowerShell version
        $_psRequiredSessionConfigurationFile = "$($global:Location.Config)\$($global:PSSessionConfigurationName).pssc"
        Copy-Files -Path $_psRequiredSessionConfigurationFile -ComputerName (pt nodes -k) -ExcludeComputerName $env:COMPUTERNAME -Quiet
        
        $_psRequiredSessionConfigurationFileExists = $true
        foreach ($node in (pt nodes -k)) {
            $_psRequiredSessionConfigurationFileExistsOnNode = [FileObject]::new($_psRequiredSessionConfigurationFile,$node).Exists()
            if (!$_psRequiredSessionConfigurationFileExistsOnNode) {
                throw ("Required PSSessionConfigurationFile `"$_psRequiredSessionConfigurationFile`" not found on $node")
            }
            $_psRequiredSessionConfigurationFileExists = $_psRequiredSessionConfigurationFileExists -and $_psRequiredSessionConfigurationFileExistsOnNode
        }
        if (!$_psRequiredSessionConfigurationFileExists) {
            throw("Unable to update required PSSessionConfiguration `"$($global:PSSessionConfigurationName)`"")
        }
        else {
            foreach ($node in (pt nodes -k)) {

                try {
                    $_psSessionConfiguration = invoke-command -computername $node -configurationname "PowerShell.7" -ScriptBlock {Get-PSSessionConfiguration | Where-Object {$_.Name -ne "PowerShell.7"}}
                    $_psSessionConfigurationName = ($_psSessionConfiguration | Where-Object {$_.PSVersion -eq ($_pssessionConfiguration.PSVersion | Sort-Object -Descending)}).Name
                }
                catch {
                    throw ("Error remoting to $node using the PSSessionConfiguration `"PowerShell.$($PSVersionTable.PSVersion)`"")
                }

                invoke-command -computername $node -configurationname $_psSessionConfigurationName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                    -ScriptBlock {
                        $_psVersion = $PSVersionTable.PSVersion.Patch -eq 0 ? "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" : $PSVersionTable.PSVersion
                        $_psRequiredConfiguration = Get-PSSessionConfiguration -Name $using:PSSessionConfigurationName -ErrorAction SilentlyContinue
                        # if ($null -ne $_psRequiredConfiguration -and $_psRequiredConfiguration.PSVersion -ne $_psVersion) {
                            Unregister-PSSessionConfiguration -Name $using:PSSessionConfigurationName | Out-Null
                            $_psRequiredConfiguration = Get-PSSessionConfiguration -Name $using:PSSessionConfigurationName -ErrorAction SilentlyContinue
                        # }
                        if ($null -eq $_psRequiredConfiguration) {
                            Register-PSSessionConfiguration -Name $using:PSSessionConfigurationName -Path $using:_psRequiredSessionConfigurationFile -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                        }
                    } 

            }
        }

        # configure basic powershell remoting config (for this node)
        $ignoreOutput = winrm quickconfig -Quiet
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
        if ($trustedHosts.Value -notcontains "*") {
            foreach ($node in (pt nodes -k)) {
                if ($node -notin $trustedHosts.Value) {
                    $ignoreOutput = Set-Item WSMan:\localhost\Client\TrustedHosts -Value $node -Concatenate -Force
                }
            }
        }

        # enable WSMan Credssp for Server (for remote nodes)
        $psSession = Get-PsSession+ -ComputerName (pt nodes -k | Where-Object {$_ -ne $thisNode})
        if ($null -ne $psSession) {
            $ignoreOutput = Invoke-Command -ScriptBlock {Enable-WSManCredSSP -Role Server -Force} -Session $psSession
            $ignoreOutput = Remove-PSSession $psSession
        }

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    }
    catch {
        $message = "$($emptyString.PadLeft(8,"`b")) FAILURE"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
    }

#endregion POWERSHELL REMOTING

$global:WarningPreference = $currentWarningPreference