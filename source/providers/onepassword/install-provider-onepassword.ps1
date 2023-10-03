param (
    [switch]$UseDefaultResponses
)

$_provider = Get-Provider -Id "OnePassword"
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    $installSettings = "$PSScriptRoot\data\$($_provider.Id)InstallSettings.ps1"
    if (Test-Path -Path $installSettings) {
        . $installSettings
    }

    $overwatchRoot = $PSScriptRoot -replace "\\install",""
    if (Get-Content -Path $overwatchRoot\definitions\definitions-provider-$($_provider.Id).ps1 | Select-String "<serviceAccountToken>" -Quiet) {

        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Service Account Token ", "$($serviceAccountToken ? "[$serviceAccountToken] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $serviceAccountTokenResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $serviceAccountToken = ![string]::IsNullOrEmpty($serviceAccountTokenResponse) ? $serviceAccountTokenResponse : $serviceAccountToken
            if ([string]::IsNullOrEmpty($server)) {
                Write-Host+ -NoTrace -NoTimestamp "NULL: Service account token is required" -ForegroundColor Red
                $serviceAccountToken = $null
            }
        } until ($serviceAccountToken)

        $definitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-provider-$($_provider.Id).ps1
        $definitionsFile = $definitionsFile -replace "<serviceAccountToken>", $serviceAccountToken
        $definitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-provider-$($_provider.Id).ps1

        if (Test-Path $installSettings) {Clear-Content -Path $installSettings}
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $installSettings
        "Param()" | Add-Content -Path $installSettings
        "`$serviceAccountToken = `"$serviceAccountToken`"" | Add-Content -Path $installSettings

    }

    $migrateToOnePassword = ((Get-Vault credentialsKeys).Exists -or (Get-Vault connectionStringsKeys).Exists) -and !(Get-Catalog -Type "Provider" -Id $_provider.Id).IsInstalled

    if ($migrateToOnePassword) {

        .\source\providers\$($_provider.Id.ToLower())\provider-$($_provider.Id.ToLower()).ps1

        $env:OP_SERVICE_ACCOUNT_TOKEN = $serviceAccountToken
        $env:OP_FORMAT = "json"
        
        New-Item -ItemType Directory "$($global:Location.Data)\vaultArchive" -ErrorAction SilentlyContinue

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

            Move-Item $vault.Path "$($global:Location.Data)\vaultArchive"

            Write-Host+ -NoTrace "Migration of Overwatch ",$vault," to 1Password ","COMPLETED" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkGreen
            Write-Host+

        }

        Write-Host+ -NoTrace "Migration to 1Password","COMPLETED" -ForegroundColor DarkGray,DarkGreen
    
    }

#endregion PROVIDER-SPECIFIC INSTALLATION