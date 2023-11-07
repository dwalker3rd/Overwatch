$script:lockRetryDelay = New-Timespan -Seconds 1
$script:lockRetryMaxAttempts = 5

function global:New-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    @{} | Write-Vault -Vault $Vault -ComputerName $ComputerName
    @{} | Write-Vault -Vault "$($Vault)Keys" -ComputerName $ComputerName
    
    return

}

function global:Get-Vaults {

    param (
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    $_vaults = @()
    foreach ($_vault in (Get-Files $global:Location.Data -Filter *.vault -ComputerName $ComputerName).FileNameWithoutExtension) {
        $_vaults += Get-Vault -Vault $_vault -ComputerName $ComputerName
    }

    return $_vaults

}
Set-Alias -Name List-Vaults -Value Get-Vaults -Scope Global

function global:Get-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    $path = "$($global:Location.Data)\$($Vault).vault"
    $_vault = [VaultObject]::new($path, $ComputerName)

    return $_vault

}

function global:Remove-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    $_vault = Get-Vault -Vault $Vault -ComputerName $ComputerName 
    Remove-Item -Path $_vault.Path
    
    return

}
function Get-VaultKeys {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    return (Read-Vault $Vault -ComputerName $ComputerName).Keys

}

function Read-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    $_vault = Get-Vault $Vault -ComputerName $ComputerName
    if ($_vault.Exists) {
        $lock = Lock-Vault $Vault -ComputerName $ComputerName -Share "Read"
        if ($lock) {
            $outputObject = $null
            try {
                $outputObject = Import-Clixml $_vault.Path
            }
            catch {}
            finally {
                Unlock-Vault $lock
            }
            return $outputObject
        }
        else {
            throw "Unable to acquire lock on vault $Vault"
        }
    }
    else {
        return $null
    }

}

function Write-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$true,ValueFromPipeline)][Object]$InputObject,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    begin {
        $_vault = Get-Vault $Vault -ComputerName $ComputerName
        $outputObject = @()
    }
    process {
        $outputObject += $InputObject
    }
    end {
        $lock = Lock-Vault $Vault -ComputerName $ComputerName -Share "None" 
        if ($lock) {
            $outputObject  | Export-Clixml $_vault.Path
            # $outputobject | ConvertTo-Json | Set-Content $_vault.Path
            Unlock-Vault $lock
        }
        else {
            throw "Unable to acquire lock on vault $Vault"
        }
    }

}

function Lock-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][ValidateSet("Read","None")][String]$Share = "Read"
    )

    $_vault = Get-Vault $Vault -ComputerName $ComputerName
    $lockFile = $_vault.FullName -replace $_vault.Extension,".lock"
    
    $lockRetryAttempts = 0
    $FileStream = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', $Share)
    while (!$FileStream.CanWrite) {
        # if (!(Test-Path -Path $lockFile)) {
        #     Set-Content -Path $lockFile -Value (Get-Date -AsUTC)
        # }
        try {
            if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
                $message = "Unable to acquire lock after $($lockRetryAttempts) attempts"
                # $lockMeta = @{retryDelay = $script:lockRetryDelay; retryMaxAttempts = $script:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
                Write-Log -Action "LockVault" -Target $_vault.FileNameWithoutExtension -Status "Error" -Message $message -EntryType "Error" # -Data $lockMeta 
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
        # this is only here b/c after this many times, something is probably wrong and we need to figure out what and why
        $message = "Lock acquired after $($lockRetryAttempts) attempts"
        # $lockMeta = @{retryDelay = $script:lockRetryDelay; retryMaxAttempts = $script:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "LockVault" -Target $_vault.FileNameWithoutExtension -Status "Success" -Message $message -Force # -Data $lockMeta
    }

    return $FileStream
}

function Unlock-Vault {

    param (
        [Parameter(Mandatory=$true,Position=0)][object]$Lock
    )

    $Lock.Close()
    $Lock.Dispose()
    Remove-Item -Path $Lock.Name -Force

}

function Test-IsVaultLocked {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $_vault = Get-Vault $Vault -ComputerName $ComputerName
    $lockFile = $_vault.FullName -replace $_vault.Extension,".lock"

    return Test-Path -Path $lockFile

}

function Wait-VaultUnlocked {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $_vault = Get-Vault $Vault -ComputerName $ComputerName
    # $lockFile = $_vault.FullName -replace $_vault.Extension,".lock"

    $lockRetryAttempts = 0
    while (Test-IsVaultLocked $_vault.FileNameWithoutExtension) {
        if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
            $message = "Timeout waiting for lock to be released"
            # $lockMeta = @{retryDelay = $script:lockRetryDelay; retryMaxAttempts = $script:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
            Write-Log -Action "WaitVault" -Target $_vault.FileNameWithoutExtension -Status "Timeout" -Message $message -EntryType "Warning" # -Data $lockMeta
            throw "($message -replace "","") on $($_vault.FileNameWithoutExtension)"
        }
        $lockRetryAttempts++
        Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
    }

    if ($lockRetryAttempts -gt 1) {
        $message = "Lock released"
        # $lockMeta = @{retryDelay = $script:lockRetryDelay; retryMaxAttempts = $script:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "WaitVault" -Target $_vault.FileNameWithoutExtension -Status "VaultAvailable" -Message $message -Force  # -Data $lockMeta
    }

    return

}

function global:New-VaultItem {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding(DefaultParameterSetName="Login")]
    param (

        [Parameter(Mandatory=$false)][ValidateSet("Login","SSH Key","Database")][string]$Category = "Login",
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$false)][Alias("Name")][string]$Title,
        [Parameter(Mandatory=$false)][string]$Tags,
        [Parameter(Mandatory=$false)][string]$Url,
        [Parameter(Mandatory=$false)][string]$Notes,
        
        [Parameter(Mandatory=$false,ParameterSetName="Database")]
        [Parameter(Mandatory=$true,ParameterSetName="Login")][Alias("Uid")][string]$UserName,
        [Parameter(Mandatory=$false,ParameterSetName="Database")]
        [Parameter(Mandatory=$false,ParameterSetName="Login")][Alias("Pwd")][string]$Password,
        [Parameter(Mandatory=$false,ParameterSetName="Login")][switch]$GeneratePassword,
        [Parameter(Mandatory=$false,ParameterSetName="Login")][string]$GeneratePasswordRecipe = "letters,digits,symbols,32",

        [Parameter(Mandatory=$true,ParameterSetName="SSH Key")][string]$SshKey,
        [Parameter(Mandatory=$false,ParameterSetName="SSH Key")][ValidateSet("ed25519","rsa","rsa2048", "rsa3072","rsa4096")][string]$SshGenerateKey = "ed25519",

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$DatabaseType,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Driver,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$DriverType,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][Alias("HostName")][string]$Server,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Port,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Database,
        # [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Uid,
        # [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Pwd,

        [Parameter(Mandatory=$false,ParameterSetName="Database")]
        [ValidateSet("disable","allow","prefer","require","verify-ca","verify-full")]
        [AllowNull()]
        [string]$SslMode = $null,

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Sid,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Alias,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Options,

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$ConnectionString,

        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME

    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-Host+ "Vault '$Vault' not found" -ForegroundColor Red
        return
    }

    $item = Get-VaultItem $Id -Vault $Vault -ComputerName $ComputerName
    if ($item) {
        Write-Host+ "Item '$Id' already exists" -ForegroundColor Red
        return
    }
    $encryptionKey = Get-VaultKey $Id -Vault $Vault -ComputerName $ComputerName
    if ($encryptionKey) {
        Write-Host+ "Key '$Id' already exists" -ForegroundColor Red
        return
    }

    $encryptionKey = New-VaultKey -Id $Id -Vault $Vault -ComputerName $ComputerName

    $item = @{ Category = $Category }
    switch ($Category) {
        "Login" {
            if ($GeneratePassword -and [string]::IsNullOrEmpty($Password)) {
                $Password = New-RandomPassword
            }
            $item += @{ 
                UserName = $UserName
                Password = $Password | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $encryptionKey
            }
        }
        "SSH Key" {}
        "Database" {
            $item.DatabaseType = $DatabaseType
            if ([string]::IsNullOrEmpty($ConnectionString)) {
                $item.DriverType = $DriverType
                $item.Driver = $Driver
                $item.Server = $Server
                $item.Port = $Port
                $item.Database = $Database
                $item.UserName = $UserName
                $item.Password = $Password | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $encryptionKey
                $item.SslMode = $SslMode
                $item.Sid = $Sid
                $item.Alias = $Alias
                $item.Options = $Options
                $item.ConnectionString = Invoke-Expression "ConvertTo-$($DriverType)ConnectionString -InputObject `$item"
            }
            else {    
                $item += Invoke-Expression "ConvertFrom-$($DriverType)ConnectionString -ConnectionString `$ConnectionString"
                $item.Password = $item.Password | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $encryptionKey
                $item.ConnectionString = Invoke-Expression "ConvertTo-$($DriverType)ConnectionString -InputObject `$item"
            }          
        }
    }

    if ($Title) { $item.Title = $Title }
    if ($Tags) { $item += @{ Tags = $Tags } }
    if (![string]::IsNullOrEmpty($Url)) { $item += @{ Url = $Url } }
    if ($Notes) { $item += @{ Notes = $Notes } }
    
    $vaultItems = Read-Vault $Vault -ComputerName $ComputerName
    $vaultItems += @{$($Id.ToLower())=$item}
    $vaultItems | Write-Vault $Vault -ComputerName $ComputerName

}
Set-Alias -Name Add-VaultItem -Value New-VaultItem -Scope Global

function global:Update-VaultItem {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding(DefaultParameterSetName="Login")]
    param (

        [Parameter(Mandatory=$false)][ValidateSet("Login","SSH Key","Database")][string]$Category = "Login",
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$false)][Alias("Name")][string]$Title,
        [Parameter(Mandatory=$false)][string]$Tags,
        [Parameter(Mandatory=$false)][string]$Url,
        [Parameter(Mandatory=$false)][string]$Notes,
        
        [Parameter(Mandatory=$false,ParameterSetName="Database")]
        [Parameter(Mandatory=$true,ParameterSetName="Login")][Alias("Uid")][string]$UserName,
        [Parameter(Mandatory=$false,ParameterSetName="Database")]
        [Parameter(Mandatory=$false,ParameterSetName="Login")][Alias("Pwd")][string]$Password,
        [Parameter(Mandatory=$false,ParameterSetName="Login")][switch]$GeneratePassword,
        [Parameter(Mandatory=$false,ParameterSetName="Login")][string]$GeneratePasswordRecipe = "letters,digits,symbols,32",

        [Parameter(Mandatory=$true,ParameterSetName="SSH Key")][string]$SshKey,
        [Parameter(Mandatory=$false,ParameterSetName="SSH Key")][ValidateSet("ed25519","rsa","rsa2048", "rsa3072","rsa4096")][string]$SshGenerateKey = "ed25519",

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$DatabaseType,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Driver,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$DriverType,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][Alias("HostName")][string]$Server,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Port,
        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Database,
        # [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Uid,
        # [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$Pwd,

        [Parameter(Mandatory=$false,ParameterSetName="Database")]
        [ValidateSet("disable","allow","prefer","require","verify-ca","verify-full")]
        [AllowNull()]
        [string]$SslMode = $null,

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$ConnectionString,

        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME

    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-Host+ "Vault '$Vault' not found" -ForegroundColor Red
        return
    }

    $item = Get-VaultItem $Id -Vault $Vault -ComputerName $ComputerName
    if (!$item) {
        Write-Host+ "Item '$Id' not found" -ForegroundColor Red
        return
    }

    $encryptionKey = Get-VaultKey -Vault $Vault -Id $Id -ComputerName $ComputerName
    if (!$encryptionKey) {
        Write-Host+ "Key '$Id' not found" -ForegroundColor Red
        return
    }

    if ($item.Category -ne $Category) {
        Write-Host+ "Unable to update item '$Id' from category '$($item.Category)' to $Category" -ForegroundColor Red
        return
    }

    switch ($item.Category) {
        "Login" {
            if ($UserName) { $item.UserName = $UserName }
            if ($Password) { $item.Password = $Password | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $encryptionKey }
            if ($GeneratePassword -and [string]::IsNullOrEmpty($Password)) {
                $item.Password = New-RandomPassword  | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $encryptionKey
            }
        }
        "SSH Key" {}
        "Database" {
            $item.DatabaseType = $DatabaseType ?? $item.DatabaseType
            $item.Driver = $Driver ?? $item.Driver
            $item.Server = $Server ?? $item.Server
            $item.Port = $Port ?? $item.Port
            $item.Database = $Database ?? $item.Database
            $item.UserName = $UserName ?? $item.UserName
            $item.Password = $Password ?? $item.Password | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $encryptionKey
            $item.SslMode = $SslMode ?? $item.SslMode
            $item.ConnectionString = $ConnectionString ?? $item.ConnectionString
        }
    }

    if ($Title) { $item.Title = $Title }
    if ($Tags) { $item.Tags = $Tags }
    if (![string]::IsNullOrEmpty($Url)) { $item.Url = $Url }
    if ($Notes) { $item.Notes = $Notes }

    Remove-VaultItem -Vault $Vault -Id $Id -ComputerName $ComputerName

    $vaultItems = Read-Vault $Vault -ComputerName $ComputerName
    $vaultItems += @{$($Id.ToLower())=$item}
    $vaultItems | Write-Vault $Vault -ComputerName $ComputerName

}
Set-Alias -Name Edit-VaultItem -Value Update-VaultItem -Scope Global

function global:Get-VaultItems {

    param (
        [Parameter(Mandatory=$false)][string]$Categories,
        [Parameter(Mandatory=$false)][string]$Tags,
        [Parameter(Mandatory=$true,Position=0)][String]$Vault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    return Read-Vault -Vault $Vault -ComputerName $ComputerName

}

function global:Get-VaultItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][Alias("Name")][string]$Id,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-Host+ "Vault '$Vault' not found" -ForegroundColor Red
        return
    }

    $vaultItem = (Read-Vault $Vault -ComputerName $ComputerName).$Id
    if (!$vaultItem) { return }

    $encryptionKey = Get-VaultKey -Id $Id -Vault $Vault -ComputerName $ComputerName
    if (!$encryptionKey) {
        throw "The Key '$Id' not found"
        return
    }
    
    switch ($vaultItem.Category) {
        "Login" {
            $vaultItem.Password = $vaultItem.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
        }
        "SSH Key" {}
        "Database" {
            $_pwdEncrypted = $vaultItem.Password
            $vaultItem.Password = $vaultItem.Password | ConvertTo-SecureString -Key $encryptionKey | ConvertFrom-SecureString -AsPlainText
            $vaultItem.ConnectionString = $vaultItem.ConnectionString.Replace($_pwdEncrypted,$vaultItem.Password)
        }
    }
    
    return $vaultItem

}

function global:Remove-VaultItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][Alias("Name")][string]$Id,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    
    $vaultItems = Read-Vault $Vault -ComputerName $ComputerName
    if (!$vaultItems -or !$vaultItems.$Id) {
        Write-Host+ "Item '$Id' not found" -ForegroundColor DarkYellow
    }
    
    $vaultItems.Remove($Id)
    $vaultItems | Write-Vault $Vault -ComputerName $ComputerName

    # Remove-VaultKey -Id $Id -Vault $Vault -ComputerName $ComputerName

    return

}

function New-VaultKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Vault += "Keys"

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-Host+ "Vault '$Vault' not found" -ForegroundColor Red
        return
    }

    $vaultKey = New-EncryptionKey

    $vaultKeys = Read-Vault $Vault -ComputerName $ComputerName
    $vaultKeys += @{$($Id.ToLower())=$vaultKey}
    $vaultKeys | Write-Vault $Vault -ComputerName $ComputerName

    return $vaultKey

}

function Update-VaultKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Vault += "Keys"

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-Host+ "Vault '$Vault' not found" -ForegroundColor Red
        return
    }

    Remove-VaultKey -Id $Id -Vault $Vault -ComputerName $ComputerName
    $vaultKey = New-VaultKey -Id $Id -Vault $Vault -ComputerName $ComputerName

    return $vaultKey

}

function Get-VaultKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Vault += "Keys"

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-Host+ "Vault '$Vault' not found" -ForegroundColor Red
        return
    }

    $vaultKey = (Read-Vault $Vault -ComputerName $ComputerName).$Id
    if (!$vaultKey) { return }
    
    return $vaultKey

}

function Remove-VaultKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Vault += "Keys"
    
    $vaultKeys = Read-Vault $Vault -ComputerName $ComputerName
    if (!$vaultKeys -or !$vaultKeys.$Id) {
        Write-Host+ "Key '$Id' not found" -ForegroundColor DarkYellow
    }
    
    $vaultKeys.Remove($Id)
    $vaultKeys | Write-Vault $Vault -ComputerName $ComputerName

    return

}