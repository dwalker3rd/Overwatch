#region PREFLIGHT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $trustedHosts = @("tbl-mgmt-01")
    Test-Connections $trustedHosts

    $platformStatus = Get-PlatformStatus -NoCache
    if ($platformStatus.IsOK) {
        Test-RepositoryAccess $trustedHosts
        # $global:PreflightChecksCompleted = $true
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

#endregion PREFLIGHT