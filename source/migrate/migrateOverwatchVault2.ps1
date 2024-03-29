
$migrateToOverwatchVault2 = $false
try {
    $migrateToOverwatchVault2 = (Get-Vault secret).Exists -and !(Get-Vault credentialsKeys).Exists -and !(Get-Catalog -Type "Provider" -Id "OnePassword").Installed
}
catch {}
if (!$migrateToOverwatchVault2) { return }

$vaultItems = Read-Vault secret
$vaultItemNames = $vaultItems.Keys
foreach ($name in $vaultItemNames) {
    $encryptionKey = (Read-Vault key -ComputerName $ComputerName).$name
    $category = ($vaultItems.$name).Key -eq "connectionString" ? "Database" : "Login"
    switch ($category) {
        "Login" {
            $userName = [string]($vaultItems.$name).Keys
            $password = [string]($vaultItems.$name).Values | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
            Set-Credentials $name -UserName $userName -Password $password
        }
        "Database" {
            $connectionString = [string]($vaultItems.$name).Values
            $odbcParams = ConvertFrom-OdbcConnectionString -ConnectionString $connectionString
            $odbcParams.Password = $odbcParams.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
            $connectionString = ConvertTo-OdbcConnectionString -InputObject $odbcParams
            New-ConnectionString $name -ConnectionString $connectionString
        }
    }
}

New-Item -ItemType Directory "$($global:Location.Archive)\vault" -ErrorAction SilentlyContinue
Move-Item "$($global:Location.Data)\secret.vault" "$($global:Location.Archive)\vault"
Move-Item "$($global:Location.Data)\key.vault" "$($global:Location.Archive)\vault"