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
$Provider = $global:Catalog.Provider.Postgres

$Provider.Config = @{}
$Provider.Config += @{
    Parser = @{
        Regex = @{
            TableAliases = "(?'alias'\S*?)?"
            Columns = "^select\s+(?'column'.*?)\s+from"
            SubQuery = "\((?'subquery'.*)\)"
        }
    }
    DataTypes = @{
        "character varying" = @{ MapTo = @{ PowerShell = "string" } }
        "integer" = @{ MapTo = @{ PowerShell = "int" } }
        "timestamp without time zone" = @{ MapTo = @{ PowerShell = "datetime" } }
        "boolean" = @{ MapTo = @{ PowerShell = "bool" } }
        "bigint" = @{ MapTo = @{ PowerShell = "int" } }
        "text" = @{ MapTo = @{ PowerShell = "string" } }
        "uuid" = @{ MapTo = @{ PowerShell = "string" } }
    }
}
$Provider.Config.Parser.Regex.Tables = "(?:from|join|(?<=,))\s+(?'table'$($Provider.Config.Parser.Regex.SubQuery)|\S*?)(?:(?:\s+|(?=,))$($Provider.Config.Parser.Regex.TableAliases)(?:,|on|where|\s|$)|$)"

return $Provider

#endregion PROVIDER DEFINITIONS