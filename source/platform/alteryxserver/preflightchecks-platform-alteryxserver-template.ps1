#region PREFLIGHT

    Test-NetConnection+ -ComputerName (pt nodes -k) | Out-Null
    Test-PSRemoting | Out-Null -ComputerName (pt nodes -k) | Out-Null

    #region Test-SslProtocol

        try {
            $alteryxServerStatus = Get-AlteryxServerStatus
        }
        catch {
            $global:PreflightChecksCompleted = $false
            throw $_
        }

        # the controller and [at least] one gallery must be running to test SSL 
        $alteryxGalleryIsRunning = $alteryxServerStatus.Gallery.Nodes.Values -contains "Running" -and $alteryxServerStatus.Controller.Status -eq "Running"
        if ($alteryxGalleryIsRunning) {
            Test-SslProtocol $global:Platform.Uri.Host
            Get-PlatformTopology components.gallery.nodes -Keys -Online | ForEach-Object {Test-SslProtocol ($_ + "." + $global:Platform.Domain) -PassFailOnly}
        }

    #endregion Test-SslProtocol

#endregion PREFLIGHT