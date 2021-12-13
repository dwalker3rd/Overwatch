#region PREFLIGHT

    # if Alteryx Server was upgraded, force read of platform info
    Clear-Cache platforminfo
    
    #region ALTERYXSERVICE-RUNAS

        # confirm that the AlteryxService service is configured with run as account
        # the run as account and credentials are stored in the vault under "AlteryxService" 
        $secUpdates += Set-ServiceSecurity AlteryxService -ComputerName (Get-PlatformTopology nodes -Keys) 
        if ($secUpdates) {
            Write-Host+ -NoTrace "Service security changes were applied." -ForegroundColor Yellow
            Write-Host+ -NoTrace "Restart platform ASAP." -ForegroundColor Yellow
        }

    #region ALTERYXSERVICE-RUNAS

    # ensure that the AlteryxService service is disabled for offline nodes
    $standbyNodes = foreach ($component in (pt components -k)) {pt components.$component.Standby}
    Set-PlatformService -Name "AlteryxService" -StartupType "Disabled" -Computername $standbyNodes

    # confirm that the required crypto/ssl files are in the DLLs directory
    # see https://github.com/conda/conda/issues/8273
    Repair-PythonSSL -ComputerName (Get-PlatformTopology nodes -keys)

    # confirm that required python packages have been installed
    # these packages are in addition to those installed by Alteryx
    $requiredPythonPackages = @()
    if ($requiredPythonPackages) {
        Install-PythonPackage -Package $requiredPythonPackages -Pip $global:Location.Pip -ComputerName (Get-PlatformTopology nodes -keys)
    }

    # enable powershell 'double-hop' with credssp on controller
    Enable-CredSspDoubleHop -ComputerName (pt components.controller.nodes -k)

#endregion PREFLIGHT