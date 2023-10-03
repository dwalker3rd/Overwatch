function global:Add-PostgresData {


    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$false)][string]$Schema = "public",
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$false)][Alias("Field")][string[]]$Columns,
        [Parameter(Mandatory=$true)][string[]]$Values
    )

    $connection = Connect-OdbcData "$Database-admin-$($Platform.Instance)"
    $query = "INSERT INTO $Schema.$Table"
    if ($Columns) { $query += " ($($Columns -join ", "))"}
    $query += " VALUES ('$($Values -join "', '")')"
    $result = Insert-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    return $result

}
Set-Alias -Name pgInsert -Value Add-PostgresData -Scope Global
Set-Alias -Name Insert-PostgresData -Value Add-PostgresData -Scope Global

function global:Read-PostgresData {


    [CmdletBinding(DefaultParameterSetName = "Query")]
    param (
        
        [Parameter(Mandatory=$true,ParameterSetName="Query")]
        [Parameter(Mandatory=$true,ParameterSetName="Table")]
        [string]$Database,

        [Parameter(Mandatory=$false,ParameterSetName="Query")]
        [Parameter(Mandatory=$false,ParameterSetName="Table")]
        [string]$Schema = "public",

        [Parameter(Mandatory=$true,ParameterSetName="Table")]
        [string]$Table,

        [Parameter(Mandatory=$false,ParameterSetName="Table")]
        [Alias("Field")][string[]]$Column = "*",

        [Parameter(Mandatory=$true,ParameterSetName="Query")]
        [string]$Query,

        [Parameter(Mandatory=$false,ParameterSetName="Query")]
        [Parameter(Mandatory=$false,ParameterSetName="Table")]
        [string]$Filter
    )

    #region GET PROVIDER META
    
        $Provider = Get-Provider "Postgres"
    
    #endregion GET PROVIDER META
    #region CONNECT

        $connection = Connect-OdbcData "$Database-readonly-$($Platform.Instance)"
    
    #endregion CONNECT
    #region QUERY EXECUTION

        $Query = $Query ? $Query : "SELECT $($Column -join ",") FROM $Table"
        if ($Filter) { $Query += " WHERE $Filter" }
        $_dataRows = Read-OdbcData -Connection $connection -Query $Query

    #endregion QUERY EXECUTION
    #region COLUMNS METADATA

        $_queryColumns = @()
        $_queryColumns += ([regex]::Matches($Query, $Provider.Config.Parser.Regex.Columns, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object {$_.Groups['column'].value.Trim()}) -split ","
        if ($_queryColumns -eq "*") {
            $_queryColumns = @()
            $_table = [regex]::Matches($Query, $Provider.Config.Parser.Regex.Tables, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object {$_.Groups['table'].value}
            $_columnsMetaQuery = "SELECT table_catalog,table_schema,table_name,column_name,data_type from information_schema.columns"
            $_columnsMetaQuery += " where table_catalog = '$($Database)' and table_schema = '$($Schema)'"
            $_columnsMetaQuery += " and table_name in ('$(($_table | Select-Object -Unique) -join ",")')"
            $_columnsMeta = Read-OdbcData -Connection $connection -Query $_columnsMetaQuery
            $_queryColumns += $_columnsMeta.column_name
        }

        $_columns = @()
        foreach ($_queryColumn in $_queryColumns) {
            $_column = [PSCustomObject]@{
                table_name = ![string]::IsNullOrEmpty($Table) ? $Table : ""
                table_alias = ![string]::IsNullOrEmpty($Table) ? $Table : ($_queryColumn -split "\.")[0]
                column_name = ![string]::IsNullOrEmpty($Table) ? $_queryColumn : ((($_queryColumn -split "\.")[1] -split " as ")[0] -split "::")[0]
                column_alias = ![string]::IsNullOrEmpty($Table) ? $_queryColumn : (($_queryColumn -split "\.")[1] -split " as ")[1] ?? ((($_queryColumn -split "\.")[1]) -split " as ")[0]
                data_type = @{}
            }
            if ([string]::IsNullOrEmpty($Table)) {
                # this code isn't recursive [yet] so it doesn't support recasting when the query includes a subquery
                $_column.table_name = [regex]::Matches($Query, $Provider.Config.Parser.Regex.Tables.Replace($Provider.Config.Parser.Regex.TableAliases,$_column.table_alias), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object {$_.Groups['table'].value}
                if ($_column.table_alias -match $Provider.Config.Parser.Regex.SubQuery) {
                    $_column.table_name = ""
                }
            }
            if (![string]::IsNullOrEmpty($_column.table_name)) {
                $_columns += $_column
            }
        }

        if ($_columns) {
            $_columnsMetaQuery = "SELECT table_catalog,table_schema,table_name,column_name,data_type from information_schema.columns"
            $_columnsMetaQuery += " where table_catalog = '$($Database)' and table_schema = '$($Schema)'"
            $_columnsMetaQuery += " and table_name in ('$(($_columns.table_name | Select-Object -Unique) -join "','")')"
            $_columnsMetaQuery += " and column_name in ('$(($_columns.column_name | Select-Object -Unique) -join "','")')"
            $_columnsMeta = Read-OdbcData -Connection $connection -Query $_columnsMetaQuery
        }

        foreach ($_column in $_columns) {
            $_columnMeta = $_columnsMeta | Where-Object {$_.table_name -eq $_column.table_name -and $_.column_name-eq $_column.column_name}
            $_column.data_type += @{ postgres = $_columnMeta.data_type }
            $_column.data_type += @{ powershell = $Provider.Config.DataTypes.($_column.data_type.postgres).MapTo.PowerShell }
        }

    #endregion COLUMNS METADATA
    #region DATATYPE CONVERSION

        $dataRows = @()
        if ($_columns) {
            foreach ($_dataRow in $_dataRows) {
                $dataRow = @{}
                foreach ($_column in $_columns) {
                    $dataRow += @{
                        $($_column.column_alias) =  
                            switch ($_column.data_type.powershell) {
                                "bool" {
                                    switch ($_dataRow.($_column.column_alias)) {
                                        "0" { $false }; "false" { $false }
                                        "1" { $true }; "true" { $true }
                                    }
                                }
                                default {
                                    $_dataRow.($_column.column_alias) -as $_column.data_type.powershell
                                }
                            }
                    }
                }
                $dataRows += [PSCustomObject]$dataRow
            }
        }
        else {
            $dataRows += $_dataRows
        }

    #endregion DATATYPE CONVERSION        
    #region DISCONNECT
    
        Disconnect-OdbcData -Connection $connection

    #endregion DISCONNECT

    return $dataRows

}
Set-Alias -Name pgRead -Value Read-PostgresData -Scope Global

function global:Update-PostgresData {


    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$false)][string]$Schema = "public",
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$true)][Alias("Field")][string]$Column,
        [Parameter(Mandatory=$true)][string]$Value,
        [Parameter(Mandatory=$false)][string]$Filter
    )

    $connection = Connect-OdbcData "$Database-admin-$($Platform.Instance)"
    $query = "UPDATE $Schema.$Table SET $Column = '$Value'"
    if ($Filter) { $query += " WHERE $Filter" }
    $result = Update-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    return $result

}
Set-Alias -Name pgUpdate -Value Update-PostgresData -Scope Global

function global:Remove-PostgresData {


    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$false)][string]$Schema = "public",
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$false)][string]$Filter
    )

    $connection = Connect-OdbcData "$Database-admin-$($Platform.Instance)"
    $query = "DELETE FROM $Schema.$Table"
    if ($Filter) { $query += " WHERE $Filter" }
    $result = Delete-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    return $result

}
Set-Alias -Name pgDelete -Value Remove-PostgresData -Scope Global
Set-Alias -Name Delete-PostgresData -Value Remove-PostgresData -Scope Global