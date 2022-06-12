<# 
.Synopsis
Vault service for Overwatch
.Description
This script provides file-based caching for Overwatch objects via Powershell's Import-Clixml 
and Export-Clixml cmdlets.
#>

$global:Vault = @{
    Secret = @{ Name = "secret" }
    Key = @{ Name = "key" }
}

$global:lockRetryDelay = New-Timespan -Seconds 1
$global:lockRetryMaxAttempts = 5

<# 
.Synopsis
Gets the properties of an Overwatch vault.
.Description
Returns the properties of Overwatch vaults.
.Parameter Name
The name of the vault.  If the named vault does not exist, then a stubbed vault object is returned to
the caller.  If Name is not specified, then the properties of ALL Overwatch vaults are returned.  
.Outputs
Vault object properties (not the content of the vault).
#>
function global:Get-Vault {
    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name
    ) 

    $path = "$($global:Location.Data)\$($Name).vault"
    $vault = [VaultObject]::new($path)

    return $vault
}

<# 
.Synopsis
Get the keys of an Overwatch vault.
.Description
Get the vault (hashtable) keys.
.Parameter Vault
Vault name. 
.Outputs
Vault keys.
#>
function global:Get-VaultKeys {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault
    )

    return (Read-Vault $Vault).keys

}
function global:Get-KeysFromSecretVault {
    return Get-VaultKeys -Vault secret
}
function global:Get-KeysFromKeyVault {
    return Get-VaultKeys -Vault key
}
<# 
.Synopsis
Read the contents of an Overwatch object from vault.
.Description
Retrieves the contents of a named vault and returns the object to the caller.  If the vault has expired, 
the vault is cleared and a null object is returned to the caller.
.Parameter Name
The name of the vault.
.Outputs
Overwatch (or null) object.
#>
function global:Read-Vault {
    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name
    )
    $vault = Get-Vault $Name
    if ($vault.Exists()) {
        $lock = Lock-Vault $Name -Share "Read"
        if ($lock) {
            $outputObject = Import-Clixml $vault.Path
            # $outputObject = Get-Content $vault.Path | ConvertFrom-Json | ConvertTo-Hashtable
            Unlock-Vault $lock
            return $outputObject
        }
        else {
            throw "Unable to acquire lock on vault $Name"
        }
    }
    else {
        return $null
    }
}

<# 
.Synopsis
Write an Overwatch to vault.
.Description
Writes the contents of an object to the named vault.
.Parameter Name
The name of the vault.
.Parameter InputObject
The object to be vaultd.
#>
function global:Write-Vault {
    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(Mandatory=$true,ValueFromPipeline)][Object]$InputObject
    )
    begin {
        $vault = Get-Vault $Name
        $outputObject = @()
    }
    process {
        $outputObject += $InputObject
    }
    end {
        $lock = Lock-Vault $Name -Share "None"
        if ($lock) {
            $outputObject  | Export-Clixml $vault.Path
            # $outputobject | ConvertTo-Json | Set-Content $vault.Path
            Unlock-Vault $lock
        }
        else {
            throw "Unable to acquire lock on vault $Name"
        }
    }
}

<# 
.Synopsis
Locks an Overwatch vault.
.Description
Creates a separate file used to indicate the vault is locked.
.Parameter Name
The name of the vault.
.Parameter Share
None (exclusive access) or Read (others can read).
.Outputs
The FileStream object for the lock file.
#>
function global:Lock-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(Mandatory=$false)][ValidateSet("Read","None")][String]$Share = "Read"
    )

    $vault = Get-Vault $Name
    $lockFile = $vault.FullPathName -replace $vault.Extension,".lock"
    
    $lockRetryAttempts = 0
    while (!$FileStream.CanWrite) {
        # if (!(Test-Path -Path $lockFile)) {
        #     Set-Content -Path $lockFile -Value (Get-Date -AsUTC)
        # }
        try {
            if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
                $message = "Unable to acquire lock after $($lockRetryAttempts) attempts."
                $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
                Write-Log -Action "LockVault" -Target $vault.FileNameWithoutExtension -Status "Error" -Message $message -Data $lockMeta -EntryType "Error"
                return $null
            }
            $lockRetryAttempts++
            $FileStream = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', $Share)
        }
        catch {
            Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
        }
    }

    if ($lockRetryAttempts -gt 2) {
        $message = "Lock acquired after $($lockRetryAttempts) attempts."
        $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "LockVault" -Target $vault.FileNameWithoutExtension -Status "Success" -Message $message -Data $lockMeta -Force
    }

    return $FileStream
}

<# 
.Synopsis
Unlocks a locked Overwatch vault.
.Description
Removes the vault's lock file making the vault available.
.Parameter Lock
The FileStream object for the lock file.
.Outputs
None.
#>
function global:Unlock-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][object]$Lock
    )

    $Lock.Close()
    $Lock.Dispose()
    Remove-Item -Path $Lock.Name -Force

    # Write-Log -Action "UnlockVault" -Target $vault.FileNameWithoutExtension -Status "Success" -Force

}

<# 
.Synopsis
Determine if vault is locked.
.Description
Uses Test-Path to check for the existence of a vault lock file.
.Parameter Name
The name of the vault.
.Outputs
Boolean result from Test-Path
#>
function global:Test-IsVaultLocked {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name
    )

    $vault = Get-Vault $Name
    $lockFile = $vault.FullPathName -replace $vault.Extension,".lock"

    return Test-Path -Path $lockFile

}

<# 
.Synopsis
Wait for a vault to be unlocked.
.Description
Waits until the vault lock is released.
.Parameter Name
The name of the vault.
.Outputs
None
#>
function global:Wait-VaultUnlocked {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name
    )

    $vault = Get-Vault $Name
    # $lockFile = $vault.FullPathName -replace $vault.Extension,".lock"

    $lockRetryAttempts = 0
    while (Test-IsVaultLocked $vault.FileNameWithoutExtension) {
        if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
            $message = "Timeout waiting for lock to be released."
            $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
            Write-Log -Action "WaitVault" -Target $vault.FileNameWithoutExtension -Status "Timeout" -Message $message -Data $lockMeta -EntryType "Warning"
            throw "($message -replace ".","") on $($vault.FileNameWithoutExtension)."
        }
        $lockRetryAttempts++
        Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
    }

    if ($lockRetryAttempts -gt 1) {
        $message = "Lock released."
        $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "WaitVault" -Target $vault.FileNameWithoutExtension -Status "VaultAvailable" -Message $message -Data $lockMeta -Force
    }

    return

}

<# 
.Synopsis
Adds an object to a vault.
.Description
Adds an object to a vault.
.Parameter Vault
The name of the vault.
.Parameter Name
The name of the secret.
.Parameter Secret
The secret (an object).
#>
function global:Add-ToVault {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault,
        [Parameter(Mandatory=$true,Position=1)][string]$Name,
        [Parameter(Mandatory=$true)][Alias("Key","Secret")][object]$InputObject
    )

    $Name = $Name.ToLower()
    
    $vaultContent = Read-Vault $Vault

    if ($vaultContent.$Name) {$vaultContent.Remove($Name)}
    $vaultContent += @{$Name=$InputObject}
    $vaultContent | Write-Vault $Vault

}

function global:Add-ToKeyVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$true)][Alias("Key","Secret")][object]$InputObject
    )
    Add-ToVault -Vault $global:Vault.Key.Name -Name $Name -InputObject $InputObject
}
Set-Alias -Name Save-EncryptionKey -Value Add-ToKeyVault -Scope Global

function global:Add-ToSecretVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$true)][Alias("Key","Secret")][object]$InputObject
    )
    Add-ToVault -Vault $global:Vault.Secret.Name -Name $Name -InputObject $InputObject
}
Set-Alias -Name Save-Secret -Value Add-ToSecretVault -Scope Global

<# 
.Synopsis
Gets an encryption key from the keyvault.
.Description
Gets an encryption key from the keyvault.
.Outputs
An encryption key.
#>
function global:Get-FromVault {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )

    $Name = $Name.ToLower()

    $vaultContent = Read-Vault $Vault
    # if (!$vaultContent -or !$vaultContent.$Name) {
    #     throw "Item $Name was not found in the vault."
    # }
    
    return $vaultContent.$Name

}
function global:Get-FromKeyVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )
    Get-FromVault -Vault $global:Vault.Key.Name -Name $Name
}
Set-Alias -Name Get-EncryptionKey -Value Get-FromKeyVault -Scope Global
function global:Get-FromSecretVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )
    Get-FromVault -Vault $global:Vault.Secret.Name -Name $Name
}
Set-Alias -Name Get-Secret -Value Get-FromSecretVault -Scope Global

<# 
.Synopsis
Removes an encryption key from the keyvault.
.Description
Removes an encryption key from the keyvault.
#>
function global:Remove-FromVault {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Vault,
        [Parameter(Mandatory=$true,Position=1)][string]$Name
    )  

    $Name = $Name.ToLower()
    
    $vaultContent = Read-Vault $Vault
    if (!$vaultContent -or !$vaultContent.$Name) {
        throw "Item $Name was not found in the vault."
    }
    
    $vaultContent.Remove($Name)
    $vaultContent | Write-Vault $Vault

}
function global:Remove-FromKeyVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )
    Remove-FromVault -Vault $global:Vault.Key.Name -Name $Name
}
Set-Alias -Name Remove-EncryptionKey -Value Remove-FromKeyVault -Scope Global
function global:Remove-FromSecretVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name
    )
    Remove-FromVault -Vault $global:Vault.Secret.Name -Name $Name
}
Set-Alias -Name Remove-Secret -Value Remove-FromSecretVault -Scope Global