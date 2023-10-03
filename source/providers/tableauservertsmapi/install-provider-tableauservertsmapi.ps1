param (
    [switch]$UseDefaultResponses
)

$_provider = Get-Provider -Id 'TableauServerTsmApi'
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION
#endregion PROVIDER-SPECIFIC INSTALLATION