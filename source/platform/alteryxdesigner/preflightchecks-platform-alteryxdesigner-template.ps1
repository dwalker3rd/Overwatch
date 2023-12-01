#region PREFLIGHT

    Test-NetConnection+ -ComputerName (pt nodes -k) | Out-Null
    Test-PSRemoting -ComputerName (pt nodes -k) | Out-Null

    #region Test-SslProtocol

        try {
        }
        catch {
            $global:PreflightChecksCompleted = $false
            throw $_
        }

    #endregion Test-SslProtocol

#endregion PREFLIGHT