#region POSTFLIGHT

    #region IncompletePreflightChecks

        if (!$global:PreflightChecksCompleted) {

            Test-TsmController
            Confirm-PlatformLicenses
            # Show-PlatformLicenses
            Test-SslProtocol $global:Platform.Uri.Host 

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT