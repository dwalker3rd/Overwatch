#region PROVIDER DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$Provider = $null
$Provider = $global:Catalog.Provider.Okta

return $Provider

#endregion PROVIDER DEFINITIONS