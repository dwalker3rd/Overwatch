#region POSTFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    #region IncompletePreflightChecks

        if (!$global:PreflightChecksCompleted) {

            Test-RepositoryAccess $trustedHosts -SSL

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT
        