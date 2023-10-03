.\source\providers\onepassword\provider-onepassword.ps1

#region DEFINITIONS

    # Data For Action Service Account Token
    $env:OP_SERVICE_ACCOUNT_TOKEN = "ops_eyJzaWduSW5BZGRyZXNzIjoiZGF0YTRhY3Rpb24uMXBhc3N3b3JkLmNvbSIsInVzZXJBdXRoIjp7Im1ldGhvZCI6IlNSUGctNDA5NiIsImFsZyI6IlBCRVMyZy1IUzI1NiIsIml0ZXJhdGlvbnMiOjY1MDAwMCwic2FsdCI6Im9URW9Pb2p6dDVCRDFnaUJKUU8yeEEifSwiZW1haWwiOiJ0aWY2eWdwbDR5N3lvQDFwYXNzd29yZHNlcnZpY2VhY2NvdW50cy5jb20iLCJzcnBYIjoiN2FhNjEzZGMxNzBmZWYwMzQzZWIzM2IzYTdkZTUwYmM5MmZkY2Q4MTdkNjhkZDA1NjEzZTVjODg1YzhkZGJmYyIsIm11ayI6eyJhbGciOiJBMjU2R0NNIiwiZXh0Ijp0cnVlLCJrIjoiUjlfV3dPZ2lRb2wzX1RwOENhOGZMeFF1Z053NDNuWHVoQmlKaHZuejltSSIsImtleV9vcHMiOlsiZW5jcnlwdCIsImRlY3J5cHQiXSwia3R5Ijoib2N0Iiwia2lkIjoibXAifSwic2VjcmV0S2V5IjoiQTMtOEpaU0xMLTZHUlRNVi1aRFg3TC1NWTNUWC01SzU5Ti1NUVQ4USIsInRocm90dGxlU2VjcmV0Ijp7InNlZWQiOiIwYzk4MDYyN2VkNDgyMjFhMDVhMWYzMmJlMWY0YzQyZWUzZmFmZjgyZjRlZjdiYzlkMjdiNWU0M2NhYWY4YTkxIiwidXVpZCI6IkpCT1pOTFc2VU5DWkpERUNYVzdPN0pUSzVJIn0sImRldmljZVV1aWQiOiJ5c3k3cnV6NDNldnBibWU0b2g3bmV3M2oyZSJ9"
    $env:OP_FORMAT = "json"

#endregion DEFINITIONS
#region MAIN

    Write-Host+

    $overwatchVaults = @("Credentials","ConnectionStrings")
    foreach ($vault in $overwatchVaults) {

        Write-Host+ -NoTrace "Migrating Overwatch ",$vault," to 1Password" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray

        if ($vault -notin (Get-Vaults).name) { 
            Write-Host+ -NoTrace "  Creating 1Password Vault ",$vault -NoSeparator -ForegroundColor DarkGray,DarkBlue
            New-Vault -Vault $vault 
        }

        $vaultItems = Import-Clixml "$($global:Location.Data)\$($vault).vault"
        $encryptionKeys = Import-Clixml "$($global:Location.Data)\$($vault)Keys.vault"

        foreach ($Id in $vaultItems.Keys) {
            $vaultItem = $vaultItems.$Id
            $encryptionKey = $encryptionKeys.$Id
            $_vaultItem = @{}
            switch ($vaultItem.Category) {
                "Login" {
                    $vaultItem.Password = $vaultItem.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText

                    if ($Id -notin (Get-VaultItems -Vault $vault).id -and $Id -notin (Get-VaultItems -Vault $vault).title) {
                        Write-Host+ -NoTrace "  Creating ","LOGIN"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $_vaultItem = New-VaultItem -Vault credentials -Title $Id @vaultItem -Category Login
                    }
                    else {
                        Write-Host+ -NoTrace "  Updating ","LOGIN"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $_vaultItem = Update-VaultItem -Vault credentials -Title $Id @vaultItem -Category Login
                    }
                }
                "SSH Key" {}
                "Database" {
                    $vaultItem.remove("Category")
                    $vaultItem.remove("ConnectionString")
                    $vaultItem.Password = $vaultItem.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText

                    if ($Id -notin (Get-VaultItems -Vault $vault).id -and $Id -notin (Get-VaultItems -Vault $vault).title) {
                        Write-Host+ -NoTrace "  Creating ","DATABASE"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $_vaultItem = New-VaultItem -Vault connectionStrings -Title $Id @vaultItem -Category Database -DriverType ODBC 
                    }
                    else {
                        Write-Host+ -NoTrace "  Updating ","DATABASE"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $_vaultItem = Update-VaultItem -Vault connectionStrings -Title $Id @vaultItem -DriverType ODBC -Category Database
                    } 
                }
            }
            $_vaultItem | Out-Null
        }

        Write-Host+ -NoTrace "Migration of Overwatch ",$vault," to 1Password ","COMPLETED" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkGreen
        Write-Host+

    }



#endregion MAIN