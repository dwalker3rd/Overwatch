param (
    [switch]$UseDefaultResponses
)

$_provider = Get-Provider -Id 'Fabric'
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION
#endregion PROVIDER-SPECIFIC INSTALLATION