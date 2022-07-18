function ConvertFrom-PostgresConnectionString {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$ConnectionString
    )

    $ht = [ordered]@{}
    if ($ConnectionString -match "^(.*?);*$") { $ConnectionString = $Matches[1] }
    $attributes = ($ConnectionString.Split(";")).Replace(";","")
    foreach ($attribute in $attributes) {
        $key = $attribute.Split("=")[0]
        $value = $attribute.Split("=")[1]
        if ($value -match "^{(.*?)}$") { $value = $Matches[1] }
        $ht.$key = $value
    }

    return $ht

}

function ConvertTo-PostgresConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][object]$InputObject
    )

    $connectionString = ""
    foreach ($key in $InputObject.Keys) {
        $connectionString += switch ($key) {
            "Driver" { "$key={$($InputObject.$key)};" }
            default { "$key=$($InputObject.$key);" }
        }
    }

    return $connectionString

}
function global:New-PostgresConnectionString {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Driver,
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$Port,
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$true)][string]$Credentials,

        [Parameter(Mandatory=$false)]
        [ValidateSet("disable","allow","prefer","require","verify-ca","verify-full")]
        [AllowNull()]
        [string]$SslMode = $null,

        [switch]$Test
    
    )

    $odbcDriver = Get-OdbcDataDriver -Name $Driver
    if (!$odbcDriver) {
        throw "ERROR: No ODBC driver found with the name `"$Driver`""
    }

    $creds = Get-Credentials $Credentials
    if (!$creds) {
        throw "ERROR: No credentials found with the name `"$Credentials`""
    }

    $dataSource = [ordered]@{
        Driver = $Driver
        Server = $Server
        Port = $Port
        Database = $Database
        Uid = $creds.UserName
        Pwd = [System.Web.HttpUtility]::UrlEncode($creds.GetNetworkCredential().Password)
    }
    if ($SslMode) { $dataSource.sslmode = $SslMode }

    $connectionString = ConvertTo-PostgresConnectionString $dataSource

    Set-ConnectionString -Name $Name -ConnectionString $connectionString

    return

}

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
    $status = Insert-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    if ($status -ne 1 -and $ErrorActionPreference -eq "Continue") {
        throw "Failed to update `"$Schema.$Table.$Column`" in database `"$Database`""
    }

    return

}
Set-Alias -Name pgInsert -Value Add-PostgresData -Scope Global
Set-Alias -Name Insert-PostgresData -Value Add-PostgresData -Scope Global

function global:Read-PostgresData {


    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$false)][string]$Schema = "public",
        [Parameter(Mandatory=$true)][string]$Table,
        [Parameter(Mandatory=$false)][Alias("Field")][string]$Column = "*",
        [Parameter(Mandatory=$false)][string]$Filter
    )

    $connection = Connect-OdbcData "$Database-readonly-$($Platform.Instance)"
    $query = "SELECT $Column FROM $Schema.$Table"
    if ($Filter) { $query += " WHERE $Filter" }
    $dataRow = Read-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    return $dataRow

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
    $status = Update-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    if ($status -ne 1 -and $ErrorActionPreference -eq "Continue") {
        throw "Failed to update `"$Schema.$Table.$Column`" in database `"$Database`""
    }

    return

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
    $query = "REMOVE $Schema.$Table"
    if ($Filter) { $query += " WHERE $Filter" }
    $status = Delete-OdbcData -Connection $connection -Query $Query
    Disconnect-OdbcData -Connection $connection

    if ($status -ne 1 -and $ErrorActionPreference -eq "Continue") {
        throw "Failed to delete rows from `"$Schema.$Table`" in database `"$Database`""
    }

    return

}
Set-Alias -Name pgDelete -Value Remove-PostgresData -Scope Global
Set-Alias -Name Delete-PostgresData -Value Remove-PostgresData -Scope Global