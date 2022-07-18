function global:Connect-OdbcData {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$ConnectionString
    )

    if (!$ConnectionString.StartsWith("Driver={")) {
        $ConnectionString = Get-ConnectionString $ConnectionString
    }

    $conn = New-Object System.Data.Odbc.OdbcConnection
    $conn.ConnectionString = $ConnectionString
    $conn.open()

    return $conn
    
}
Set-Alias -Name odbcConnect -Value Connect-OdbcData -Scope Global

function global:Disconnect-OdbcData {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][System.Data.Odbc.OdbcConnection]$Connection
    )

    $Connection.Close()
    
}
Set-Alias -Name odbcDisconnect -Value Disconnect-OdbcData -Scope Global

function global:Read-OdbcData {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][System.Data.Odbc.OdbcConnection]$Connection,
        [Parameter(Mandatory=$true)][string]$Query
    )

    $command = New-Object System.Data.Odbc.OdbcCommand($Query,$Connection)

    $reader = $command.ExecuteReader()  

    $DataSet = New-Object Data.Dataset -Property @{ EnforceConstraints = $false }  
    $DataTable = New-Object Data.DataTable
    $DataSet.Tables.Add($DataTable)
    $DataTable.Load($reader,[Data.LoadOption]::OverwriteChanges)

    $command.Dispose()

    return $DataTable

}
Set-Alias -Name odbcRead -Value Read-OdbcData -Scope Global


function global:Update-OdbcData {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][System.Data.Odbc.OdbcConnection]$Connection,
        [Parameter(Mandatory=$true)][string]$Query
    )

    $command = New-Object System.Data.Odbc.OdbcCommand($Query,$Connection)
    $command.ExecuteNonQuery()
    $command.Dispose()

    return

}
Set-Alias -Name odbcUpdate -Value Update-OdbcData -Scope Global
Set-Alias -Name odbcInsert -Value Update-OdbcData -Scope Global
Set-Alias -Name odbcDelete -Value Update-OdbcData -Scope Global
Set-Alias -Name Insert-OdbcData -Value Update-OdbcData -Scope Global
Set-Alias -Name Delete-OdbcData -Value Update-OdbcData -Scope Global