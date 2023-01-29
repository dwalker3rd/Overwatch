#region POSTFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    #region IncompletePreflightChecks

        $trustedHosts = @("")

        if (!$global:PreflightChecksCompleted) {

            if ($trustedHosts) {
                Test-RepositoryAccess $trustedHosts -SSL
            }

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT
        