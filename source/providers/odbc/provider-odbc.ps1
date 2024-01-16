function global:Connect-OdbcData {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$ConnectionString
    )

    if (!$ConnectionString.StartsWith("Driver={")) {
        $ConnectionString = Get-ConnectionString $ConnectionString | ConvertTo-OdbcConnectionString
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

function global:Get-OdbcInstalledDrivers {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][ValidateSet("32-bit","64-bit")][AllowNull()][string]$BitVersion = $null,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $cimSession = New-CimSession -ComputerName $ComputerName

    $params = @{ CimSession = $cimSession }
    if ($Name) { $params += @{ Name = $Name }}
    if ($Platform) { $params += @{ Platform = $Platform }}

    return Get-OdbcDriver @params
}

function ConvertFrom-OdbcConnectionString {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline)][string]$ConnectionString
    )

    begin {
        $validConnectionStringKeys = @(
            "Driver","Server","HostName","Port","Database","Uid","Pwd","UserName","Password","Sid","Alias","SslMode"
        )
        $ht = [ordered]@{}
    }
    process {
        if ($ConnectionString -match "^(.*?);*$") { $ConnectionString = $Matches[1] }
        $attributes = ($ConnectionString.Split(";")).Replace(";","")
        foreach ($attribute in $attributes) {
            $key = $attribute.Split("=")[0]
            if ($key -in $validConnectionStringKeys) {
                $value = $attribute.Split("=")[1]
                if ($value -match "^{(.*?)}$") { $value = $Matches[1] }
                if ($key -in @("Password","Pwd")) {
                    if ($value.GetType().Name -ne "SecureString") {
                        $value = $value | ConvertTo-SecureString -AsPlainText
                    }
                }
                $ht.$key = $value
            }
        }
    }
    end {
        return $ht
    }

}

function ConvertTo-OdbcConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline)][object]$InputObject
    )

    begin {
        # $validConnectionStringKeys specifies valid keys and the order in which they are added to $connectionString
        $validConnectionStringKeys = @(
            "Driver","Server","HostName","Port","Database","Uid","Pwd","UserName","Password","Sid","Alias","SslMode"
        )
        $connectionString = ""
    }
    process { 
        foreach ($key in $validConnectionStringKeys) {
            if ($key -in $InputObject.Keys) {
                $connectionString += switch ($key) {
                    "Driver" { "$key={$($InputObject.$key)};" }
                    {$_ -in @("Password","Pwd")} {
                        if ($InputObject.$key.GetType().Name -eq "SecureString") {
                            "$key=$($InputObject.$key | ConvertFrom-SecureString -AsPlainText);"
                        }
                    }
                    default { "$key=$($InputObject.$key);" }
                }
            }
        }
    }
    end { 
        return $connectionString 
    }

}