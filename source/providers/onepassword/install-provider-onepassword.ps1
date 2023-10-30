param (
    [switch]$UseDefaultResponses
)

$_providerId = "OnePassword"
# $_provider = Get-Provider -Id $_providerId
# $_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    # complete previous Write-Host+ -NoNewLine
    Write-Host+

    Write-Host+ -SetIndentGlobal 8
    Write-Host+

    # switch to Overwatch vault service to get/set the 1Password service account token
    . "$($global:Location.Services)\vault.ps1"

    $opServiceAccountTokenId = "op-service-account-token"
    $opServiceAccountToken = $null
    $opServiceAccountCredentials = Get-Credentials $opServiceAccountTokenId
    if ($opServiceAccountCredentials) { $opServiceAccountToken = $opServiceAccountCredentials.GetNetworkCredential().Password }
    # if (!$opServiceAccountCredentials) { $migrateToOnePassword = $true }
    $opServiceAccountTokenMasked = $opServiceAccountToken -match "^(.{8}).*(.{4})$" ? $matches[1] + "..." + $matches[2] : $null

    do {
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "1Password Service Account Token ", "$($opServiceAccountToken ? "[$opServiceAccountTokenMasked] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $opServiceAccountTokenResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $opServiceAccountToken = ![string]::IsNullOrEmpty($opServiceAccountTokenResponse) ? $opServiceAccountTokenResponse : $opServiceAccountToken
        if ([string]::IsNullOrEmpty($opServiceAccountToken)) {
            Write-Host+ -NoTrace -NoTimestamp "NULL: Service account token is required" -ForegroundColor Red
            $opServiceAccountToken = $null
        }
    } until ($opServiceAccountToken)

    # this seems redundant given that the credentials are set below, but ...
    # it is needed for when the migration script calls Get-Provider which loads providers w/their definition files
    # and the definition file for this provider sets the 1password service token
    Set-Credentials -Id $opServiceAccountTokenId -Account "Overwatch" -Token $opServiceAccountToken

    $owVaults = (Get-Vaults).FileNameWithoutExtension | Where-Object {$_ -notlike "*Keys"}

    New-Item -ItemType Directory "$($global:Location.Archive)\vault" -ErrorAction SilentlyContinue

    Clear-Cache -Name onePasswordVaults
    Clear-Cache -Name onePasswordItems

    # switch back to 1Password provider
    . "$($global:Location.Source)\providers\$($_providerId.ToLower())\provider-$($_providerId).ps1"

    $env:OP_SERVICE_ACCOUNT_TOKEN = $opServiceAccountToken
    $env:OP_FORMAT = "json"

    foreach ($owVault in $owVaults) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Migrating Overwatch vault ",$owVault," to 1Password" -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray

        if ($owVault -notin (Get-Vaults).name) { 
            Write-Host+ -NoTrace -NoTimestamp "  Creating 1Password vault ",$owVault -NoSeparator -ForegroundColor DarkGray,DarkBlue
            New-Vault -Vault $owVault 
        }

        $owVaultItems = Import-Clixml "$($global:Location.Data)\$($owVault).vault"
        $owEncryptionKeys = Import-Clixml "$($global:Location.Data)\$($owVault)Keys.vault"

        # if (!(Test-Path -Path "$($global:Location.Archive)\vault\$($owVault).vault")) {
            $timeStamp = $(Get-Date -Format 'yyyyMMddHHmmss')
            Move-Item "$($global:Location.Data)\$($owVault).vault" "$($global:Location.Archive)\vault\$($owVault).vault.$timeStamp" -ErrorAction SilentlyContinue
            Move-Item "$($global:Location.Data)\$($owVault)Keys.vault" "$($global:Location.Archive)\vault\$($owVault).vault$timeStamp" -ErrorAction SilentlyContinue
        # }

        $opVaultItems = Get-VaultItems -Vault $owVault

        foreach ($key in $owVaultItems.Keys | Where-Object {$_ -ne $opServiceAccountTokenId}) {
            $owVaultItem = $owVaultItems.$key
            $encryptionKey = $owEncryptionKeys.$key
            switch ($owVaultItem.Category) {
                "Login" {
                    if ($key -notin $opVaultItems.id -and $key -notin $opVaultItems.name) {
                        Write-Host+ -NoTrace -NoTimestamp "  Creating ","LOGIN"," item ",$key -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $owVaultItem.Password = $owVaultItem.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
                        $owNewVaultItem = New-VaultItem -Vault credentials -Title $key @owVaultItem -Category Login
                    }
                    else {
                        Write-Host+ -NoTrace -NoTimestamp "  Found ","LOGIN"," item ",$key -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                    }
                }
                "SSH Key" {}
                "Database" {
                    if ($key -notin $opVaultItems.id -and $key -notin $opVaultItems.name) {
                        Write-Host+ -NoTrace -NoTimestamp "  Creating ","DATABASE"," item ",$key -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                        $owVaultItem.remove("Category")
                        $owVaultItem.remove("ConnectionString")
                        $owVaultItem.Pwd = $owVaultItem.Pwd | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
                        $owNewVaultItem = New-VaultItem -Vault connectionStrings -Title $key @owVaultItem -Category Database -DriverType ODBC 
                    }
                    else {
                        Write-Host+ -NoTrace -NoTimestamp "  Found ","DATABASE"," item ",$key -NoSeparator -ForegroundColor DarkGray,DarkBlue,DarkGray,DarkBlue
                    } 
                }
            }
            $owNewVaultItem | Out-Null
        }

    }

    # switch to Overwatch vault service to get/set the 1Password service account token
    . "$($global:Location.Services)\vault.ps1"

    Set-Credentials -Id $opServiceAccountTokenId -Account "Overwatch" -Token $opServiceAccountToken

    # switch back to 1Password provider
    . "$($global:Location.Source)\providers\$($_providerId.ToLower())\provider-$($_providerId).ps1"

    Write-Host+
    Write-Host+ -SetIndentGlobal -8

#endregion PROVIDER-SPECIFIC INSTALLATION