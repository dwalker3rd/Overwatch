#region POSTFLIGHT

    #region IncompletePreflightChecks

        if (!$global:PreflightChecksCompleted) {

            Test-RepositoryAccess $trustedHosts

        }
        else {

            $message = "  No postflight checks"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor Yellow

        }

    #endregion IncompletePreflightChecks

#endregion POSTFLIGHT
        