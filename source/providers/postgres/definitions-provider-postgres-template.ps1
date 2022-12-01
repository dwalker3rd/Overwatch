#region PROVIDER DEFINITIONS

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$Provider = $null
$Provider = $global:Catalog.Provider.Postgres

return $Provider

#endregion PROVIDER DEFINITIONS