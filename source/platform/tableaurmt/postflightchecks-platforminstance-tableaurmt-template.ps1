#region POSTFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    #region IncompletePreflightChecks

        $allowedRepositoryHosts = @("")

        if (!$global:PreflightChecksCompleted) {

            if ($allowedRepositoryHosts) {
                Test-RepositoryAccess $allowedRepositoryHosts -SSL
            }

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT
        