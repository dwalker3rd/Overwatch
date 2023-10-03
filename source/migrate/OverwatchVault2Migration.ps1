# Convert from Overwatch Legacy Vault to Overwatch Vault 2.0
function global:ConvertTo-OverwatchVault2 {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$LegacyVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $legacyVaultItems = Read-Vault -Vault $LegacyVault
    $legacyVaultItemNames = $legacyVaultItems.Keys
    foreach ($name in $legacyVaultItemNames) {
        $encryptionKey = (Read-Vault key -ComputerName $ComputerName).$name
        $category = ($legacyVaultItems.$name).Key -eq "connectionString" ? "Database" : "Login"
        switch ($category) {
            "Login" {
                $userName = [string]($legacyVaultItems.$name).Keys
                $password = [string]($legacyVaultItems.$name).Values | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
                Set-Credentials $name -UserName $userName -Password $password
            }
            "Database" {
                $connectionString = [string]($legacyVaultItems.$name).Values
                $odbcParams = ConvertFrom-OdbcConnectionString -ConnectionString $connectionString
                $odbcParams.Password = $odbcParams.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
                $connectionString = ConvertTo-OdbcConnectionString -InputObject $odbcParams
                New-ConnectionString $name -ConnectionString $connectionString
            }
        }
    }

}