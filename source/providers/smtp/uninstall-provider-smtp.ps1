
param (
    [switch]$UseDefaultResponses
)

# $Provider = Get-Provider -Id 'SMTP'
# $_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Testing the STMP uninstall script"
    Write-Host+

#endregion PROVIDER-SPECIFIC INSTALLATION