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
$Provider = $global:Catalog.Provider.AzureAD

return $Provider

#endregion PROVIDER DEFINITIONS