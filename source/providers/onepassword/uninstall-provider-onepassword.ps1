param (
    [switch]$UseDefaultResponses
)

$_providerId = "OnePassword"
$script:OnePassword = Get-Provider $_providerId
$script:opVaultsCacheName = $OnePassword.Config.Cache.Vaults.Name ?? "opVaults"
$script:opVaultItemsCacheName = $OnePassword.Config.Cache.VaultItems.Name ?? "opVaultItems"

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
    # foreach ($opVault in (Get-Vault credentials)) {
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
    }

    foreach ($opVault in $opVaults) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "    Migrating 1Password vault ",$opVault.id," to Overwatch" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray

        if ($opVault.id -notin (Get-Vaults).FileNameWithoutExtension) { 
            Write-Host+ -NoTrace -NoTimestamp "      Creating Overwatch vault ",$opVault.id -NoSeparator -ForegroundColor DarkGray,DarkBlue
            New-Vault -Vault $opVault.id 
        }

        $owVaultItems = Get-VaultItems -Vault $opVault.id

        foreach ($opVaultItem in $opVault.vaultItems) {
            
            switch ($opVaultItem.Category) {
                "Login" {
                    if ($opVaultItem.name -notin $owVaultItems.name) {
                        Write-Host+ -NoTrace -NoTimestamp "      Creating ","LOGIN"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $opVaultItem.Id = $opVaultItem.Name 
                        $commandParameters = (Get-Command New-VaultItem).Parameters.Keys
                        foreach ($opVaultItemParameter in ($opVaultItem.Keys | Copy-Object)) {
                            if ($opVaultItemParameter -notin $commandParameters) { $opVaultItem.Remove($opVaultItemParameter) }
                        }
                        $opNewVaultItem = New-VaultItem -Vault credentials -Name $opVaultItem.name @opVaultItem
                    }
                    else {
                        # Write-Host+ -NoTrace -NoTimestamp "      Found ","LOGIN"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        Write-Host+ -NoTrace -NoTimestamp "      Updating ","LOGIN"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $opVaultItem.Id = $opVaultItem.Name 
                        $commandParameters = (Get-Command New-VaultItem).Parameters.Keys
                        foreach ($opVaultItemParameter in ($opVaultItem.Keys | Copy-Object)) {
                            if ($opVaultItemParameter -notin $commandParameters) { $opVaultItem.Remove($opVaultItemParameter) }
                        }
                        Remove-VaultItem -Vault credentials -Id $opVaultItem.Id -ErrorAction SilentlyContinue | Out-Null
                        $opNewVaultItem = New-VaultItem -Vault credentials -Name $opVaultItem.name @opVaultItem
                    }
                }
                "SSH Key" {}
                "Database" {
                    if ($opVaultItem.name -notin $owVaultItems.name) {
                        Write-Host+ -NoTrace -NoTimestamp "      Creating ","DATABASE"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $opVaultItem.Id = $opVaultItem.Name 
                        $commandParameters = (Get-Command New-VaultItem).Parameters.Keys
                        foreach ($opVaultItemParameter in ($opVaultItem.Keys | Copy-Object)) {
                            if ($opVaultItemParameter -notin $commandParameters) { $opVaultItem.Remove($opVaultItemParameter) }
                        }
                        $opNewVaultItem = New-VaultItem -Vault connectionStrings -Name $opVaultItem.name @opVaultItem
                    }
                    else {
                        # Write-Host+ -NoTrace -NoTimestamp "      Found ","DATABASE"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        Write-Host+ -NoTrace -NoTimestamp "      Creating ","DATABASE"," item ",$opVaultItem.name -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $opVaultItem.Id = $opVaultItem.Name 
                        $commandParameters = (Get-Command New-VaultItem).Parameters.Keys
                        foreach ($opVaultItemParameter in ($opVaultItem.Keys | Copy-Object)) {
                            if ($opVaultItemParameter -notin $commandParameters) { $opVaultItem.Remove($opVaultItemParameter) }
                        }
                        Remove-VaultItem -Vault connectionStrings -Id $opVaultItem.Id -ErrorAction SilentlyContinue | Out-Null
                        $opNewVaultItem = New-VaultItem -Vault connectionStrings -Name $opVaultItem.name @opVaultItem
                    } 
                }
            }
            $opNewVaultItem  | Out-Null
            
        }

    }

    $_providerId = "OnePassword"
    $script:OnePassword = Get-Provider $_providerId
    $script:opVaultsCacheName = $OnePassword.Config.Cache.Vaults.Name ?? "opVaults"
    $script:opVaultItemsCacheName = $OnePassword.Config.Cache.VaultItems.Name ?? "opVaultItems"

    Clear-Cache -Name $script:opVaultsCacheName
    Clear-Cache -Name $script:opVaultItemsCacheName

    if ($interaction) {
        Write-Host+
    }

    return $interaction

#endregion PROVIDER-SPECIFIC INSTALLATION