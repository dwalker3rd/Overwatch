param (
    [switch]$UseDefaultResponses
)

$_providerId = "OnePassword"
# $_provider = Get-Provider -Id $_providerId
# $_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    Write-Host+; Write-Host+

    # switch to Overwatch vault service to get/set the 1Password service account token
    . "$($global:Location.Services)\vault.ps1"

    $opServiceAccountToken = $null
    $migrateToOnePassword = $false
    $opServiceAccountCredentials = Get-Credentials "op-service-account-token"
    if ($opServiceAccountCredentials) { $opServiceAccountToken = $opServiceAccountCredentials.GetNetworkCredential().Password }
    if (!$opServiceAccountCredentials) { $migrateToOnePassword = $true }
    $opServiceAccountTokenMasked = $opServiceAccountToken -match "^(.{8}).*(.{4})$" ? $matches[1] + "..." + $matches[2] : $null

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    1Password Service Account Token ", "$($opServiceAccountToken ? "[$opServiceAccountTokenMasked] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $opServiceAccountTokenResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $opServiceAccountToken = ![string]::IsNullOrEmpty($opServiceAccountTokenResponse) ? $opServiceAccountTokenResponse : $opServiceAccountToken
        if ([string]::IsNullOrEmpty($opServiceAccountToken)) {
            Write-Host+ -NoTrace -NoTimestamp "    NULL: Service account token is required" -ForegroundColor Red
            $opServiceAccountToken = $null
        }
    } until ($opServiceAccountToken)

    Set-Credentials -Id "op-service-account-token" -Account "Overwatch" -Token $opServiceAccountToken

    if ($migrateToOnePassword) {

        Write-Host+

        $overwatchVaults = (Get-Vaults).FileNameWithoutExtension | Where-Object {$_ -notlike "*Keys"}

        # switch back to 1Password provider
        . "$($global:Location.Source)\providers\$($_providerId.ToLower())\provider-$($_providerId).ps1"

        $env:OP_SERVICE_ACCOUNT_TOKEN = $opServiceAccountToken
        $env:OP_FORMAT = "json"
        
        New-Item -ItemType Directory "$($global:Location.Data)\vaultArchive" -ErrorAction SilentlyContinue

        foreach ($vault in $overwatchVaults) {

            Write-Host+ -NoTrace -NoTimestamp "    Migrating Overwatch vault ",$vault," to 1Password" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray

            if ($vault -notin (Get-Vaults).name) { 
                Write-Host+ -NoTrace -NoTimestamp "      Creating 1Password vault ",$vault -NoSeparator -ForegroundColor DarkGray,DarkBlue
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
                            Write-Host+ -NoTrace -NoTimestamp "      Creating ","LOGIN"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                            $_vaultItem = New-VaultItem -Vault credentials -Title $Id @vaultItem -Category Login
                        }
                        else {
                            Write-Host+ -NoTrace -NoTimestamp "      Found ","LOGIN"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                            # $_vaultItem = Update-VaultItem -Vault credentials -Id $Id @vaultItem -Category Login
                        }
                    }
                    "SSH Key" {}
                    "Database" {
                        $vaultItem.remove("Category")
                        $vaultItem.remove("ConnectionString")
                        $vaultItem.Password = $vaultItem.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText

                        if ($Id -notin (Get-VaultItems -Vault $vault).id -and $Id -notin (Get-VaultItems -Vault $vault).title) {
                            Write-Host+ -NoTrace -NoTimestamp "      Creating ","DATABASE"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                            $_vaultItem = New-VaultItem -Vault connectionStrings -Title $Id @vaultItem -Category Database -DriverType ODBC 
                        }
                        else {
                            Write-Host+ -NoTrace -NoTimestamp "      Found ","DATABASE"," item ",$Id -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                            # $_vaultItem = Update-VaultItem -Vault connectionStrings -Id $Id @vaultItem -DriverType ODBC -Category Database
                        } 
                    }
                }
                $_vaultItem | Out-Null
            }

            Move-Item "$($global:Location.Data)\$($vault).vault" "$($global:Location.Data)\vaultArchive" -ErrorAction SilentlyContinue
            Move-Item "$($global:Location.Data)\$($vault)Keys.vault" "$($global:Location.Data)\vaultArchive" -ErrorAction SilentlyContinue

            # Write-Host+ -NoTrace -NoTimestamp "    Migration of Overwatch vault ",$vault," to 1Password ","COMPLETED" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkGreen
            Write-Host+

        }

        # Write-Host+ -NoTrace -NoTimestamp "    Migration to 1Password","COMPLETED" -ForegroundColor DarkGray,DarkGreen
    
    }

    # switch to Overwatch vault service to get/set the 1Password service account token
    . "$($global:Location.Services)\vault.ps1"

    Set-Credentials -Id "op-service-account-token" -Account "Overwatch" -Token $opServiceAccountToken

    # switch back to 1Password provider
    . "$($global:Location.Source)\providers\$($_providerId.ToLower())\provider-$($_providerId).ps1"

    Write-Host+

#endregion PROVIDER-SPECIFIC INSTALLATION