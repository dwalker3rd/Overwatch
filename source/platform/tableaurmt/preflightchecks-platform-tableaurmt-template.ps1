#region PREFLIGHT

    Test-NetConnection+ -ComputerName (pt -nodes -k) | Out-Null
    Test-PSRemoting | Out-Null -ComputerName (pt -nodes -k) | Out-Null

    $heartbeat = Get-Heartbeat
    if ($heartbeat.IsOK) {
        Test-SslProtocol $global:Platform.Uri.Host 
    }
    else {
        $global:PreflightChecksCompleted = $false
    }

#endregion PREFLIGHT