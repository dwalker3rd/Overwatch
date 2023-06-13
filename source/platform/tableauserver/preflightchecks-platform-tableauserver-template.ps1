#region PREFLIGHT

    Test-Connections
    Test-PSRemoting

    $heartbeat = Get-Heartbeat
    if ($heartbeat.IsOK) {
        Test-TsmController
        Confirm-PlatformLicenses
        Test-SslProtocol $global:Platform.Uri.Host 
        Get-PlatformTopology nodes -Keys | ForEach-Object {Test-SslProtocol ($_ + "." + $global:Platform.Domain) -PassFailOnly}
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

#endregion PREFLIGHT