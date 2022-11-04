#region PREFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    $trustedHosts = @()
    if ($trustedHosts) {

        Test-Connections $trustedHosts

        $heartbeat = Get-Heartbeat
        if ($heartbeat.IsOK) {        
            Test-RepositoryAccess $trustedHosts
        }
        else {
            $global:PreflightChecksCompleted = $false
        }

    }

#endregion PREFLIGHT