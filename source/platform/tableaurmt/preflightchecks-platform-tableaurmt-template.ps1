#region PREFLIGHT

    Test-Connections
    Test-PSRemoting

    $heartbeat = Get-Heartbeat
    if ($heartbeat.IsOK) {
        Test-SslProtocol $global:Platform.Uri.Host 
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

#endregion PREFLIGHT