#region POSTFLIGHT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    #region IncompletePreflightChecks

        if (!$global:PreflightChecksCompleted) {

            $alteryxServerStatus = Get-AlteryxServerStatus

            # the controller and [at least] one gallery must be running to test SSL 
            $alteryxGalleryIsRunning = $alteryxServerStatus.Gallery.Nodes.Values -contains "Running" -and $alteryxServerStatus.Controller.Status -eq "Running"
            if ($alteryxGalleryIsRunning) {
                Test-SslProtocol $global:Platform.Uri.Host
            }

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT