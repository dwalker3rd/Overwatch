#region PREFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    $allowedRepositoryHosts = @()
    if ($allowedRepositoryHosts) {

        Test-NetConnection+ -ComputerName $allowedRepositoryHosts | Out-Null

        $heartbeat = Get-Heartbeat
        if ($heartbeat.IsOK) {        
            Test-RepositoryAccess $allowedRepositoryHosts -SSL
        }
        else {
            $global:PreflightChecksCompleted = $false
        }

    }

#endregion PREFLIGHT