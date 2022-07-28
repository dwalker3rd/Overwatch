#region PREFLIGHT

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