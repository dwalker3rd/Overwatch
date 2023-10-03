#region PROVIDER DEFINITIONS

param(
    [switch]$MinimumDefinitions
)

if ($MinimumDefinitions) {
    $root = $PSScriptRoot -replace "\\definitions",""
    Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
}
else {
    . $PSScriptRoot\classes.ps1
}

$Provider = $null
$Provider = $global:Catalog.Provider."OnePassword"
$Provider.Config = @{}

$env:OP_SERVICE_ACCOUNT_TOKEN = "<op_service_account_token"
$env:OP_FORMAT = "json"

return $Provider

#endregion PROVIDER DEFINITIONS