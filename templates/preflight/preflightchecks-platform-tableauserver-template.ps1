#region PREFLIGHT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    Test-Connections
    Test-PSRemoting

    $platformStatus = Get-PlatformStatus -NoCache
    if ($platformStatus.IsOK) {
        Test-TsmController
        Confirm-PlatformLicenses
        Test-SslProtocol $global:Platform.Uri.Host 
        # $global:PreflightChecksCompleted = $true
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

#endregion PREFLIGHT