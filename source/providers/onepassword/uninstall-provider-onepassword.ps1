param (
    [switch]$UseDefaultResponses
)

$_providerId = "OnePassword"
# $_provider = Get-Provider -Id $_providerId
# $_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    $interaction = $false

    # switch to 1Password provider to get vaults and items
    if (Test-Path -Path "$($global:Location.Providers)\provider-$($_providerId).ps1") {
        . "$($global:Location.Providers)\provider-$($_providerId).ps1"
    }
    else {
        . "$($global:Location.Source)\providers\$($_providerId.ToLower())\provider-$($_providerId).ps1"
    }

    $opVaults = @()
    foreach ($opVault in (Get-Vaults)) {
        $opVaults += @{
            id = $opVault.name
            vaultItems = Get-VaultItems -Vault $opVault.id
        }
    }

    # switch to Overwatch vault service to migrate vaults and items
    . "$($global:Location.Services)\vault.ps1"

    $interaction = $opVaults.Count -gt 0

    if ($interaction) {
        # complete previous Write-Host+ -NoNewLine
        Write-Host+

        Write-Host+ -SetIndentGlobal 8
    }

    foreach ($opVault in $opVaults) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Migrating 1Password vault ",$opVault.id," to Overwatch" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray

        if ($opVault.id -notin (Get-Vaults).FileNameWithoutExtension) { 
            Write-Host+ -NoTrace -NoTimestamp "  Creating Overwatch vault ",$opVault.id -NoSeparator -ForegroundColor DarkGray,DarkBlue
            New-Vault -Vault $opVault.id 
        }

        $owVaultItems = Get-VaultItems -Vault $opVault.id

        foreach ($opVaultItem in $opVault.vaultItems) {
            switch ($opVaultItem.Category) {
                "Login" {
                    if ($opVaultItem.name -notin $owVaultItems.Keys) {
                        Write-Host+ -NoTrace -NoTimestamp "  Creating ","LOGIN"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $opVaultItem.Id = $opVaultItem.Name 
                        $opNewVaultItem = New-VaultItem -Vault credentials -Name $opVaultItem.name @vaultItem
                    }
                    else {
                        Write-Host+ -NoTrace -NoTimestamp "  Found ","LOGIN"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                    }
                }
                "SSH Key" {}
                "Database" {
                    if ($opVaultItem.name -notin $owVaultItems.Keys) {
                        Write-Host+ -NoTrace -NoTimestamp "  Creating ","DATABASE"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $opVaultItem.Id = $opVaultItem.Name 
                        $opNewVaultItem = New-VaultItem -Vault connectionStrings -Name $opVaultItem.name @vaultItem
                    }
                    else {
                        Write-Host+ -NoTrace -NoTimestamp "  Found ","DATABASE"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                    } 
                }
            }
            $opNewVaultItem  | Out-Null
        }

    }

    # switch back to 1Password provider IFF the password provider files still exist
    if (Test-Path -Path "$($global:Location.Providers)\provider-$($_providerId).ps1") {
        . "$($global:Location.Providers)\provider-$($_providerId).ps1"
    }

    Clear-Cache -Name onePasswordVaults
    Clear-Cache -Name onePasswordItems

    if ($interaction) {
        Write-Host+
        Write-Host+ -SetIndentGlobal -8
    }

    return $interaction

#endregion PROVIDER-SPECIFIC INSTALLATION