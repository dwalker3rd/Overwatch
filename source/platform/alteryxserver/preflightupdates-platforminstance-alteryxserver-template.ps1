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
    try{
        $offlineNodes = foreach ($component in (pt components -k)) {pt components.$component.Offline}
        Set-PlatformService -Name "AlteryxService" -StartupType "Disabled" -Computername $offlineNodes
    }
    catch{}

    # confirm that the required crypto/ssl files are in the DLLs directory
    # see https://github.com/conda/conda/issues/8273
    Repair-PythonSSL -ComputerName (Get-PlatformTopology nodes -keys)

    # install any additional python packages required for your Alteryx Server environment
    # these are in addition to those python packages installed by Alteryx Server
    $requiredPythonPackages = @(<requiredPythonPackages>)
    if ($requiredPythonPackages) {
        Install-PythonPackage -Package $requiredPythonPackages -Pip $global:Location.Python.Pip -ComputerName (Get-PlatformTopology nodes -keys)
    }

    # enable powershell 'double-hop' with credssp on controller
    Enable-CredSspDoubleHop -ComputerName (pt components.controller.nodes -k)

#endregion PREFLIGHT