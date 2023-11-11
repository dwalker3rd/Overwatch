#region PROVIDER DEFINITIONS

param(
    [switch]$MinimumDefinitions
)

if ($MinimumDefinitions) {
    $root = $PSScriptRoot -replace "\\definitions",""
    Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
}
else {
    . $PSScriptRoot\classes.ps1
}

$Provider = $null
$Provider = $global:Catalog.Provider."OnePassword"
$Provider.Config = @{
    RegexPattern = @{
        ErrorMessage = "^\[(.*)\]\s*(\d{4}\/\d{2}\/\d{2}\s*\d{2}\:\d{2}\:\d{2})\s*(.*)$"
    }
    Cache = @{
        Vaults = @{
            Enabled = $true
            Name = "opVaults"
            MaxAge = [timespan]::MaxValue
        }
        VaultItems = @{
            Enabled = $true
            Name = "opVaultItems"
            MaxAge = New-TimeSpan -Minutes 15
        }
        EncryptionKey = @{
            Name = "OP-CACHE-ENCRYPTION-KEY"
            Value = $null
        }
    }
    ServiceAccount = @{
        Name = "OP-SERVICE-ACCOUNT-TOKEN"
    }
}

if (!$Provider.Config.Cache.Vaults.Enabled) {
    Clear-Cache $Provider.Config.Cache.Vaults.Name
}
if (!$Provider.Config.Cache.VaultItems.Enabled) {
    Clear-Cache $Provider.Config.Cache.VaultItems.Name
}

# switch to Overwatch vault service to get/set the 1Password service account token
. "$($global:Location.Services)\vault.ps1"

$env:OP_SERVICE_ACCOUNT_TOKEN = (Get-Credentials $Provider.Config.ServiceAccount.Name).GetNetworkCredential().Password
$env:OP_FORMAT = "json"

if (Get-Credentials $Provider.Config.Cache.EncryptionKey.Name) {
    $Provider.Config.Cache.EncryptionKey.Value = [byte[]]((Get-Credentials $Provider.Config.Cache.EncryptionKey.Name).GetNetworkCredential().Password -split "\s")
}
if (!$Provider.Config.Cache.EncryptionKey.Value) {
    # create new encryption key
    Set-Credentials -Id $Provider.Config.Cache.EncryptionKey.Name -UserName "OnePassword" -Password ([string](New-EncryptionKey))
    # assign encryption key to provider config
    $Provider.Config.Cache.EncryptionKey.Value = [byte[]]((Get-Credentials $Provider.Config.Cache.EncryptionKey.Name).GetNetworkCredential().Password -split "\s")
    # since the encryption key has changed, clear the caches
    Clear-Cache $Provider.Config.Cache.Vaults.Name
    Clear-Cache $Provider.Config.Cache.VaultItems.Name
}

return $Provider

#endregion PROVIDER DEFINITION
