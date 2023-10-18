param (
    [switch]$UseDefaultResponses
)

$_providerId = "OnePassword"
# $_provider = Get-Provider -Id $_providerId
# $_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    Write-Host+; Write-Host+

    # switch to 1Password provider to get vaults and items
    . "$($global:Location.Providers)\$($_providerId.ToLower())\provider-$($_providerId).ps1"

    $vaults = @()
    foreach ($vault in (Get-Vaults)) {
        $vaults += @{
            Id = $vault.Title
            VaultItems = Get-VaultItems -Vault $vault.Id
        }
    }

    # switch to Overwatch vault service to migrate vaults and items
    . "$($global:Location.Services)\vault.ps1"

    foreach ($vault in $vaults) {

        Write-Host+ -NoTrace -NoTimestamp "    Migrating 1Password vault ",$vault.Id," to Overwatch" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray

        if ($vault.Id -notin (Get-Vaults).Name) { 
            Write-Host+ -NoTrace -NoTimestamp "      Creating Overwatch vault ",$vault.Id -NoSeparator -ForegroundColor DarkGray,DarkBlue
            New-Vault -Vault $vault.Id 
        }

        foreach ($vaultItem in $vaults.$($vault.Id).VaultItems) {
            switch ($vaultItem.Category) {
                "Login" {
                    if ($vaultItem.Title -notin (Get-VaultItems -Vault $vault).Name) {
                        Write-Host+ -NoTrace -NoTimestamp "      Creating ","LOGIN"," item ",$vaultItem.Title -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $newVaultItem = New-VaultItem -Vault credentials -Name $vaultItem.Title @vaultItem
                    }
                    else {
                        Write-Host+ -NoTrace -NoTimestamp "      Found ","LOGIN"," item ",$vaultItem.Title -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                    }
                }
                "SSH Key" {}
                "Database" {
                    if ($vaultItem.Title -notin (Get-VaultItems -Vault $vault).Name) {
                        Write-Host+ -NoTrace -NoTimestamp "      Creating ","DATABASE"," item ",$vaultItem.Title -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $newVaultItem  = New-VaultItem -Vault connectionStrings -Name $vaultItem.Title @vaultItem
                    }
                    else {
                        Write-Host+ -NoTrace -NoTimestamp "      Found ","DATABASE"," item ",$vaultItem.Title -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                    } 
                }
            }
            $newVaultItem  | Out-Null
        }

        Write-Host+

    }

    # switch back to 1Password provider
    . "$($global:Location.Providers)\$($_providerId.ToLower())\provider-$($_providerId).ps1"

    Write-Host+

#endregion PROVIDER-SPECIFIC INSTALLATION