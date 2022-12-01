#region PREFLIGHT

    Test-Connections
    Test-PSRemoting

    #region Test-SslProtocol

        $alteryxServerStatus = Get-AlteryxServerStatus

        # the controller and [at least] one gallery must be running to test SSL 
        $alteryxGalleryIsRunning = $alteryxServerStatus.Gallery.Nodes.Values -contains "Running" -and $alteryxServerStatus.Controller.Status -eq "Running"
        if ($alteryxGalleryIsRunning) {
            Test-SslProtocol $global:Platform.Uri.Host
            # $global:PreflightChecksCompleted = $true
        }
        else {
            $global:PreflightChecksCompleted = $false
        }
    
    #endregion Test-SslProtocol

#endregion PREFLIGHT