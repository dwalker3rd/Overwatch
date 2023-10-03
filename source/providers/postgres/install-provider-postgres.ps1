param (
    [switch]$UseDefaultResponses
)

$_provider = Get-Provider -Id 'Postgres'
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION
#endregion PROVIDER-SPECIFIC INSTALLATION