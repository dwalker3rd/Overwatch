#region PREFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    $repositoryAllowedList = @()
    if ($repositoryAllowedList) {

        Test-NetConnection+ -ComputerName $repositoryAllowedList | Out-Null

        $heartbeat = Get-Heartbeat
        if ($heartbeat.IsOK) {        
            Test-RepositoryAccess $repositoryAllowedList -SSL
        }
        else {
            $global:PreflightChecksCompleted = $false
        }

    }

#endregion PREFLIGHT