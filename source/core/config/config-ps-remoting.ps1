[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param(
    [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=(Get-PlatformTopology nodes -Keys),
    [Parameter(Mandatory=$false)][string[]]$TrustedHosts=$ComputerName
)

$currentWarningPreference = $global:WarningPreference
$global:WarningPreference = "SilentlyContinue"

#region POWERSHELL REMOTING

    $message = "<Powershell remoting <.>48> PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    # this node is assumed to be the Overwatch controller for this platforminstance
    $thisNode = $env:COMPUTERNAME.ToLower()

    try {

        # if the $global:PSSessionConfigurationName PSSessionConfiguration is not using the version of PowerShell
        # most recently installed on the Overwatch controller, then unregister the $global:PSSessionConfigurationName 
        # PSSessionConfiguration and create a new version using the config-ps-powershell.pssc PSSessionConfigurationFile 
        $_psRequiredSessionConfigurationFile = "$($global:Location.Config)\config-ps-powershell.pssc"
        if (!($ComputerName.Count -eq 1 -and $ComputerName -eq $env:COMPUTERNAME)) {
            Copy-Files -Path $_psRequiredSessionConfigurationFile -ComputerName $ComputerName -ExcludeComputerName $env:COMPUTERNAME -Quiet
        }
        
        # verify that the config-ps-powershell.pssc PSSessionConfigurationFile has been copied to all nodes
        $_psRequiredSessionConfigurationFileExists = $true
        foreach ($node in $ComputerName) {
            $_psRequiredSessionConfigurationFileExistsOnNode = [FileObject]::new($_psRequiredSessionConfigurationFile,$node).Exists
            if (!$_psRequiredSessionConfigurationFileExistsOnNode) {
                throw ("Required PSSessionConfigurationFile `"$_psRequiredSessionConfigurationFile`" not found on $node")
            }
            $_psRequiredSessionConfigurationFileExists = $_psRequiredSessionConfigurationFileExists -and $_psRequiredSessionConfigurationFileExistsOnNode
        }
        if (!$_psRequiredSessionConfigurationFileExists) {
            throw("Unable to update required PSSessionConfiguration `"$($global:PSSessionConfigurationName)`"")
        }

        foreach ($node in $ComputerName) {

            # use the $global:PSSessionConfigurationName PSSessionConfiguration to connect and get all other PSSessionConfigurations;
            # find the PSSessionConfiguration with the highest version of PowerShell (exclude the $global:PSSessionConfigurationName PSSessionConfiguration)
            $_psSessionConfiguration = invoke-command -computername $node -configurationname $global:PSSessionConfigurationName -ScriptBlock {Get-PSSessionConfiguration | Where-Object {$_.Name -ne $using:PSSessionConfigurationName}}

            if (!$_psSessionConfiguration) {
                # Enable-PSRemoting to recreate the PSSession configurations since we just unregistered PowerShell.7
                # easiest way to enable psremoting remotely: psexec is part of the Microsoft SysInternals Suite
                $psexecResults = . "$($global:Location.Sysinternals)\psexec.exe" "\\$node" -h -s pwsh.exe -Command "Enable-PSRemoting -SkipNetworkProfileCheck -Force" # -accepteula -nobanner 2>&1
                $_psSessionConfiguration = invoke-command -computername $node -configurationname $global:PSSessionConfigurationName -ScriptBlock {Get-PSSessionConfiguration | Where-Object {$_.Name -ne $using:PSSessionConfigurationName}}
            }

            $_psSessionConfigurationName = ($_psSessionConfiguration | Sort-Object -Descending)[0].Name

            # connecting with that PSSessionConfiguration is necessary b/c the $global:PSSessionConfigurationName PSSessionConfiguration will be unregistered/registered
            # WarningAction, ErrorAction and Out-Null are used to prevent all the warning/error messages generated by WinRM being restarted by registering a new PSSessionConfiguration
            invoke-command -computername $node -configurationname $_psSessionConfigurationName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue `
                -ScriptBlock {
                    $_psVersion = $PSVersionTable.PSVersion.Patch -eq 0 ? "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" : $PSVersionTable.PSVersion
                    $_psRequiredConfiguration = Get-PSSessionConfiguration -Name $using:PSSessionConfigurationName -ErrorAction SilentlyContinue
                    if ($null -ne $_psRequiredConfiguration -and $_psRequiredConfiguration.FileName -notmatch "^.*\\PowerShell\\$($_psVersion)\\.*$") {
                        
                        Unregister-PSSessionConfiguration -Name $using:PSSessionConfigurationName | Out-Null
                        
                        # Enable-PSRemoting to recreate the PSSession configurations since we just unregistered PowerShell.7
                        # easiest way to enable psremoting remotely: psexec is part of the Microsoft SysInternals Suite
                        $psexecResults = . "$($global:Location.Sysinternals)\psexec.exe" "\\$node" -h -s pwsh.exe -Command "Enable-PSRemoting -SkipNetworkProfileCheck -Force" # -accepteula -nobanner 2>&1

                        # $_psRequiredConfiguration = Get-PSSessionConfiguration -Name $using:PSSessionConfigurationName -ErrorAction SilentlyContinue

                    }
                } 

        }

        # configure basic powershell remoting config (for this node)
        # $ignoreOutput = winrm quickconfig -Quiet
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
        $trustedHosts = Add-WSManTrustedHosts -ComputerName $TrustedHosts
        $trustedHosts | Out-Null

        # enable WSMan Credssp for Server (for remote nodes)
        $nodes = @()
        $nodes += pt nodes -k | Where-Object {$_ -ne $thisNode}
        if ($nodes) {
            $psSession = New-PsSession+ -ComputerName $nodes
            if ($null -ne $psSession) {
                $ignoreOutput = Invoke-Command -ScriptBlock {Enable-WSManCredSSP -Role Server -Force} -Session $psSession
                $ignoreOutput = Remove-PSSession+ -Session $psSession
            }
        }

        $message = "$($emptyString.PadLeft(8,"`b")) CONFIGURED"
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen

    }
    catch {

        $message = "$($emptyString.PadLeft(8,"`b")) FAILED "
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor Red

    }

#endregion POWERSHELL REMOTING

$global:WarningPreference = $currentWarningPreference