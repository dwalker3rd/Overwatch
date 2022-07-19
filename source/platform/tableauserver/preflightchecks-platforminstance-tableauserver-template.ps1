#region PREFLIGHT

$trustedHosts = @()
if ($trustedHosts) {

    Test-Connections $trustedHosts

    $platformStatus = Get-PlatformStatus
    if ($platformStatus.IsOK) {
        Test-RepositoryAccess $trustedHosts
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

}

#endregion PREFLIGHT