$script:OnePassword = Get-Provider "OnePassword"

function Write-OpError {

    param (
        [Parameter(Mandatory=$true,Position=0)][object]$ErrorRecord
    )

    $errorMessageType = "Error"
    $errorMessageText = $ErrorRecord.Exception.Message

    if ($errorMessageText -match $OnePassword.Config.RegexPattern.ErrorMessage) {
        $errorMessageType = (Get-Culture).TextInfo.ToTitleCase($matches[1])
        $errorMessageText = $matches[3].Replace('"',"'")
    }

    $_callStack = Get-PSCallStack
    $_caller = $_callStack[1]
    $_args = ([regex]::Matches($_caller.Arguments,"^\{?(.*?)\}?$").Groups[1].Value).Replace(",","`n") | ConvertFrom-StringData 

    $target = ""
    if ($_args.Vault) { $target += $_args.Vault}
    if ($_args.Id -or $_args.User) { 
        $target += "\"
        $target += $_args.Id ?? $_args.User
    }

    Write-Log -Name $OnePassword.Log -EntryType Error -Action $_caller.Command -Target $target -Status $errorMessageType -Message $errorMessageText -Force
    Write-Host+ -NoTrace $errorMessageText -ForegroundColor Red

    return

}

function global:New-Vault {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault
    ) 

    if ($Vault -in (Get-Vaults).name) {
        Write-Host+ -NoTrace "The vault '$Vault' already exists" -ForegroundColor Red
        return
    }

    $op = "op vault create $Vault"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

function global:Get-Vaults {

    [CmdletBinding()]
    param () 

    $op = "op vault list"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

Set-Alias -Name List-Vaults -Value Get-Vaults -Scope Global

function global:Get-Vault {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault
    )

    $op = "op vault get $Vault"
    $op += " 2>&1"

    $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

function global:Remove-Vault {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault
    ) 

    # if ($Vault -notin (Get-Vaults).name) {
    #     Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
    #     return
    # }
    # $_vault = Get-Vault -Vault $Vault
    # $Vault = $_vault.Name

    $op = "op vault delete $Vault"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

function global:Grant-VaultAccess {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][ValidateSet("allow_viewing","allow_editing","allow_managing")][string[]]$Permissions
    )

    # if ($Vault -notin (Get-Vaults).name) {
    #     Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
    #     return
    # }
    # $_vault = Get-Vault -Vault $Vault
    # $Vault = $_vault.Name

    $op = "op vault user grant --user $User --vault $Vault --permissions $($Permissions -join ",")"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

function global:Revoke-VaultAccess {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$false)][ValidateSet("allow_viewing","allow_editing","allow_managing")][string[]]$Permissions
    ) 

    # if ($Vault -notin (Get-Vaults).name) {
    #     Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
    #     return
    # }
    # $_vault = Get-Vault -Vault $Vault
    # $Vault = $_vault.Name

    $op = "op vault user revoke --user $User --vault $Vault"
    if ($Permissions) { $op += " --permissions $($Permissions -join ",")"}
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

function global:Get-VaultUsers {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Vault
    ) 

    # if ($Vault -notin (Get-Vaults).name) {
    #     Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
    #     return
    # }
    # $_vault = Get-Vault -Vault $Vault
    # $Vault = $_vault.Name

    $op = "op user list --vault $Vault"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}
Set-Alias -Name List-Users -Value Get-Users -Scope Global

#endregion VAULT
#region USER

function global:Get-OpUser {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$User
    ) 
    $op = "op user get $User"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json
}

function global:Get-OpCurrentUser {

    [CmdletBinding()]
    param () 
    $op = "op user get --me"
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json
}

#endregion USER
#region ITEM

function global:New-VaultItem {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding(DefaultParameterSetName="Login")]
    param (

        [Parameter(Mandatory=$false)][ValidateSet("Login","SSH Key","Database")][string]$Category = "Login",
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$false)][string]$Title,
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

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$ConnectionString

    )

    # if ($Vault -notin (Get-Vaults).name) {
    #     Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
    #     return
    # }
    # $_vault = Get-Vault -Vault $Vault
    # $Vault = $_vault.Name

    # $_vaultItems = Get-VaultItems -Vault $Vault

    # if ($Title -in ($_vaultItems).name) {
    #     Write-Host+ "Item '$Title' already exists" -ForegroundColor Red
    #     return
    # }

    $op = "op item create --category $Category --title $Title --vault $Vault"

    switch ($Category) {
        "Login" {
            if ($Username) { $op += " username[text]=`"$UserName`"" }
            if ($Password) { $op += " password=`"$Password`"" }
            if ($GeneratePassword -and !$Password) { $op += " --generate-password=$GeneratePasswordRecipe" }
        }
        "SSH Key" {
            if ($SshKey) { $op += " private_key=`"$SshKey`"" }
            if ($SshGenerateKey -and !$SshKey) { $op += " --ssh-generate-key $SshGenerateKeyAlgorithm" }
        }
        "Database" {
            $item = @{
                DatabaseType = $DatabaseType
                DriverType = $DriverType
            }
            if ([string]::IsNullOrEmpty($ConnectionString)) {
                $item += @{
                    Driver = $Driver
                    Server = $Server
                    Port = $Port
                    Database = $Database
                    UserName = $UserName
                    Password = $Password
                    SslMode = $SslMode
                    Sid = $Sid
                    Alias = $Alias
                    Options = $Options
                }
                $ConnectionString = Invoke-Expression "ConvertTo-$($DriverType)ConnectionString -InputObject `$item"
            }
            else {
                $item += Invoke-Expression "ConvertFrom-$($DriverType)ConnectionString -ConnectionString `$ConnectionString"
                $item.ConnectionString = Invoke-Expression "ConvertTo-$($DriverType)ConnectionString -InputObject `$item" 
            }
            if ($item.Server) { $op += " hostname[text]=`"$($item.Server)`"" }
            if ($item.Port) { $op += " port[text]=`"$($item.Port)`"" }
            if ($item.Database) { $op += " database[text]=`"$($item.Database)`"" }
            if ($item.UserName) { $op += " username[text]=`"$($item.UserName)`"" }
            if ($item.Password) { $op += " password=`"$($item.Password)`"" }
            if ($item.Sid) { $op += " sid[text]=`"$($item.Sid)`"" }
            if ($item.Alias) { $op += " alias[text]=`"$($item.Alias)`"" }
            if ($item.Options) { $op += " options[text]=`"$($item.Options)`"" }
            if ($item.Driver) { $op += " driver[text]=`"$($item.Driver)`"" }
            if ($item.SslMode) { $op += " sslmode[text]=`"$($item.SslMode)`"" }
            if ($item.DatabaseType) { $op += " database_type[text]=`"$($item.DatabaseType)`"" }
            if ($item.DriverType) { $op += " driver_type[text]=`"$($item.DriverType)`"" }
            if ($item.ConnectionString) { $op += " connectionstring[text]=`"$($item.ConnectionString)`"" }
        }
    }

    if ($Tags) { $op += " --tags $Tags" }
    if (![string]::IsNullOrEmpty($Url)) { $op += " --url $Url" }
    if ($Notes) { $op += " notesPlain[text]=`"$Notes`"" }
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

function global:Update-VaultItem {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding(DefaultParameterSetName="Login")]
    param (

        [Parameter(Mandatory=$false)][ValidateSet("Login","SSH Key","Database")][string]$Category = "Login",
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$false)][string]$Title,
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

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$ConnectionString
        
    )

    # if ($Vault -notin (Get-Vaults).name) {
    #     Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
    #     return
    # }
    # # $_vault = Get-Vault -Vault $Vault
    # # $Vault = $_vault.Name

    # $_vaultItems = Get-VaultItems -Vault $Vault

    # if ($Id -notin ($_vaultItems).id -and $Id -notin ($_vaultItems).title) {
    #     Write-Host+ "Item '$Id' not found" -ForegroundColor Red
    #     return
    # }

    $item = Get-VaultItem -Id $Id -Vault $Vault
    if (!$item) { return }

    if ($item.Category -ne $Category) {
        Write-Host+ "Unable to update item '$Id' from category '$($item.Category)' to $Category" -ForegroundColor Red
        return
    }

    $op = "op item edit $($item.id) --vault $Vault"

    switch ($item.Category) {
        "Login" {
            if ($Username) { $op += " username[text]=`"$UserName`"" }
            if ($Password) { $op += " password=`"$Password`"" }
            if ($GeneratePassword -and !$Password) { $op += " --generate-password=$GeneratePasswordRecipe" }
        }
        "SSH Key" {
            if ($SshKey) { $op += " private_key=`"$SshKey`"" }
            if ($SshGenerateKey -and !$SshKey) { $op += " --ssh-generate-key $SshGenerateKeyAlgorithm" }
        }
        "Database" {
            if ($Server) { $op += " hostname[text]=`"$Server`"" }
            if ($Port) { $op += " port[text]=`"$Port`"" }
            if ($Database) { $op += " database[text]=`"$Database`"" }
            if ($UserName) { $op += " username[text]=`"$UserName`"" }
            if ($Password) { $op += " password=`"$Password`"" }
            if ($Sid) { $op += " sid[text]=`"$Sid`"" }
            if ($Alias) { $op += " alias[text]=`"$Alias`"" }
            if ($Options) { $op += " options[text]=`"$Options`"" }
            if ($Driver) { $op += " driver[text]=`"$Driver`"" }
            if ($SslMode) { $op += " sslmode[text]=`"$SslMode`"" }
            if ($ConnectionString) { $op += " connectionstring[text]=`"$ConnectionString`"" }
            if ($DatabaseType) { $op += " database_type[text]=`"$DatabaseType`"" }
            if ($DriverType) { $op += " driver_type[text]=`"$DriverType`"" }
        }
    }

    if ($Title) { $op += " --title $Title" }
    if ($Tags) { $op += " --tags $Tags" }
    if (![string]::IsNullOrEmpty($Url)) { $op += " --url $Url" }
    if ($Notes) { $op += " notesPlain[text]=`"$Notes`"" }
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}
Set-Alias -Name Edit-VaultItem -Value Update-VaultItem -Scope Global

function global:Get-VaultItems {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Categories,
        [Parameter(Mandatory=$false)][string]$Tags,
        [Parameter(Mandatory=$true)][string]$Vault
    ) 

    $op = "op item list --vault $Vault"
    if ($Categories) { $op += " --categories $Categories" }
    if ($Tags) { $op += " --tags $Tags" }
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}
Set-Alias -Name List-VaultItems -Value Get-VaultItems -Scope Global

function global:Get-VaultItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$false)][string]$Fields
    ) 

    $op = "op item get $Id --vault $Vault"
    if ($Fields) { $op += " --fields $Fields" }
    $op += " 2>&1"

   $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    $result = $result | ConvertFrom-Json

    $item = @{
        id = $result.Id
        title = $result.title
        category = $result.category
    }
    foreach ($field in $result.fields) {
        if (![string]::IsNullOrEmpty($field.value)) {
            $_key = $field.label
            switch ($result.category) {
                "Database" {
                    switch ($_key) {
                        "Type" { $_key = "databasetype" }
                        "Driver_Type" { $_key = "drivertype" }
                        # "UserName" { $_key = "uid" }
                        # "Password" { $_key = "pwd" }
                    }
                }
            }
            $_value = $field.value
            $item += @{
                $_key = $_value
            }
        }
    }

    return $item

}

function global:Remove-VaultItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault
    ) 

    if ($Vault -notin (Get-Vaults).name) {
        Write-Host+ -NoTrace "The vault '$Vault' was not found" -ForegroundColor Red
        return
    }
    # $_vault = Get-Vault -Vault $Vault
    # $Vault = $_vault.Name

    $_vaultItems = Get-VaultItems -Vault $Vault

    if ($Id -notin $_vaultItems.id -and $Id -notin $_vaultItems.title) {
        Write-Host+ "Item '$Id' not found" -ForegroundColor Red
        return
    }

    $op = "op item delete $Id --vault $Vault"
    $op += " 2>&1"

    $result = Invoke-Expression $op 
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    return $result | ConvertFrom-Json

}

#endregion ITEM