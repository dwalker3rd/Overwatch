#region POSTFLIGHT

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Platform > Tableau Server > Trusted Hosts

    #region IncompletePreflightChecks

        $repositoryAllowedList = @("")

        if (!$global:PreflightChecksCompleted) {

            if ($repositoryAllowedList) {
                Test-RepositoryAccess $repositoryAllowedList -SSL
            }

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT
        