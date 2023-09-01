#region PREFLIGHT

    Test-NetConnection+ -ComputerName (pt -nodes -k) | Out-Null
    Test-PSRemoting | Out-Null -ComputerName (pt -nodes -k) | Out-Null

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