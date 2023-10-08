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
$Provider.Config = @{
    RegexPattern = @{
        ErrorMessage = "^\[(.*)\]\s*(\d{4}\/\d{2}\/\d{2}\s*\d{2}\:\d{2}\:\d{2})\s*(.*)$"
    }
}

$env:OP_SERVICE_ACCOUNT_TOKEN = "<serviceAccountToken>"
$env:OP_FORMAT = "json"

return $Provider

#endregion PROVIDER DEFINITION