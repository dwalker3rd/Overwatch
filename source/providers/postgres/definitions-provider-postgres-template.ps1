#region PROVIDER DEFINITIONS

. "$($global:Location.Definitions)\classes.ps1"

$Provider = $null
$Provider = $global:Catalog.Provider.Postgres

return $Provider

#endregion PROVIDER DEFINITIONS