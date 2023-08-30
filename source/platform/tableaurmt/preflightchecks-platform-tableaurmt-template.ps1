#region PREFLIGHT

    Test-NetConnection+ | Out-Null
    Test-PSRemoting | Out-Null

    $heartbeat = Get-Heartbeat
    if ($heartbeat.IsOK) {
        Test-SslProtocol $global:Platform.Uri.Host 
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

#endregion PREFLIGHT