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

    # result is a vault object
    $_vault = $result | ConvertFrom-Json

    $onePasswordVaults = @{}
    if ((Get-Cache onePasswordVaults).Exists) {
        $onePasswordVaults = Read-Cache onePasswordVaults
    }
    $onePasswordVaults += @{ $_vault.name = $_vault.id }
    $onePasswordVaults | Write-Cache onePasswordVaults
    
    return $_vault

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

    # result is an array of vault objects
    $_vaults = $result | ConvertFrom-Json

    $onePasswordVaults = @{}
    if ((Get-Cache onePasswordVaults).Exists) {
        $onePasswordVaults = Read-Cache onePasswordVaults
    }
    foreach ($_vault in $_vaults) {
        if (!$onePasswordVaults.$($_vault.name)) {
            $onePasswordVaults += @{ $_vault.name = $_vault.id }
        }
    }
    $onePasswordVaults | Write-Cache onePasswordVaults
    
    return $_vaults

}

Set-Alias -Name List-Vaults -Value Get-Vaults -Scope Global

function global:Get-Vault {

    # $Vault can be the vault name or id
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault
    )

    # $vaultId defaults to $Vault even if $Vault is the vault name
    $vaultId = $Vault

    $onePasswordVaults = @{}
    if ((Get-Cache onePasswordVaults).Exists) {
        $onePasswordVaults = Read-Cache onePasswordVaults
        if ($onePasswordVaults.$Vault) {
            $vaultId = $onePasswordVaults.$Vault
        }
    }

    $op = "op vault get $vaultId"
    $op += " 2>&1"

    $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }

    # result is a vault object
    $_vault = $result | ConvertFrom-Json

    if (!$onePasswordVaults.$($_vault.name)) {
        $onePasswordVaults += @{ $_vault.name = $_vault.id }
        $onePasswordVaults | Write-Cache onePasswordVaults
    }
    
    return $_vault

}

function global:Remove-Vault {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault
    ) 

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $op = "op vault delete $($_vault.id)"
    $op += " 2>&1"

    $result = Invoke-Expression $op
    if ($result -and $result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }

    $onePasswordVaults = @{}
    if ((Get-Cache onePasswordVaults).Exists) {
        $onePasswordVaults = Read-Cache onePasswordVaults
        if ($onePasswordVaults.$($_vault.name)) {
            $onePasswordVaults.Remove($_vault.name)
            $onePasswordVaults | Write-Cache onePasswordVaults
        }
    }
    
    return

}

function global:Grant-VaultAccess {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Vault,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][ValidateSet("allow_viewing","allow_editing","allow_managing")][string[]]$Permissions
    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $op = "op vault user grant --user $User --vault $($_vault.id) --permissions $($Permissions -join ",")"
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

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $op = "op vault user revoke --user $User --vault $$($_vault.id)"
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

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $op = "op user list --vault $($_vault.id)"
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
        # [Parameter(Mandatory=$true,Position=0)][string]$Id,
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

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$ConnectionString

    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $op = "op item create --category $Category --title $Title --vault $($_vault.id)"

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

    # result is an item object
    $_item = $result | ConvertFrom-Json

    $onePasswordItems = @{}
    if ((Get-Cache onePasswordItems).Exists) {
        $onePasswordItems = Read-Cache onePasswordItems
        if (!$onePasswordItems.$($_item.title)) {
            $onePasswordItems += @{ $_item.title = $_item.id }
            $onePasswordItems | Write-Cache onePasswordItems
        }        
    }

    return $_item

}

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

        [Parameter(Mandatory=$false,ParameterSetName="Database")][string]$ConnectionString
        
    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $_item = Get-VaultItem -Id $Id -Vault $($_vault.id)
    if (!$_item) { return }

    if ($_item.Category -ne $Category) {
        Write-Host+ "Unable to update item '$Id' from category '$($_item.Category)' to $Category" -ForegroundColor Red
        return
    }

    $op = "op item edit $($_item.id) --vault $($_vault.id)"

    switch ($_item.Category) {
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

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $op = "op item list --vault $($_vault.id)"
    if ($Categories) { $op += " --categories $Categories" }
    if ($Tags) { $op += " --tags $Tags" }
    $op += " | op item get -"
    $op += " 2>&1"

    $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }

    # result is an array of item objects
    # the results from this expression are not valid JSON
    # step1 injects a comma between json objects
    # step2 wraps the json with []
    $result = $result -join "`n" -replace "\}`n\{","},`n{"
    if ($result[0] -ne "[") {
        $result = "[$result]"
    }

    $_items = $result | ConvertFrom-Json

    $_customItems = @()
    foreach ($_item in $_items) {
        $_customItem = [ordered]@{
            id = $_item.Id
            name = $_item.title
            title = $_item.title
            category = $_item.category
        }
        foreach ($field in $_item.fields) {
            if (![string]::IsNullOrEmpty($field.value)) {
                $_key = $field.label
                switch ($_item.category) {
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
                $_customItem += @{ $_key = $_value }
            }
        }
        $_customItems += $_customItem
    }

    $onePasswordItems = @{}
    if ((Get-Cache onePasswordItems).Exists) {
        $onePasswordItems = Read-Cache onePasswordItems
    }
    foreach ($_customItem in $_customItems) {
        if (!$onePasswordItems.$($_customItem.name)) {
            $onePasswordItems += @{ $_customItem.name = $_customItem.id }
        }
    }
    $onePasswordItems | Write-Cache onePasswordItems

    return $_customItems

}
Set-Alias -Name List-VaultItems -Value Get-VaultItems -Scope Global

function global:Get-VaultItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][Alias("Name")][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault,
        [Parameter(Mandatory=$false)][string]$Fields
    )

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $itemId = $Id

    $onePasswordItems = @{}
    if ((Get-Cache onePasswordItems).Exists) {
        $onePasswordItems = Read-Cache onePasswordItems
        if ($onePasswordItems.$Id) {
            $itemId = $onePasswordItems.$Id
        }        
    }

    $op = "op item get $itemId --vault $($_vault.id)"
    if ($Fields) { $op += " --fields $Fields" }
    $op += " 2>&1"

    $result = Invoke-Expression $op
    if (!$result) { return }
    
    if ($result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }
    
    # result is an item object
    $_item = $result | ConvertFrom-Json

    $_customItem = @{
        id = $_item.Id
        name = $_item.title
        title = $_item.title
        category = $_item.category
    }
    foreach ($field in $_item.fields) {
        if (![string]::IsNullOrEmpty($field.value)) {
            $_key = $field.label
            switch ($_item.category) {
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
            $_customItem += @{ $_key = $_value }
        }
    }
    $_customItem = $_customItem

    if (!$onePasswordItems.$($_customItem.name)) {
        $onePasswordItems += @{ $_customItem.name = $_customItem.id }
        $onePasswordItems | Write-Cache onePasswordItems
    }

    return $_customItem

}

function global:Remove-VaultItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][Alias("Name")][string]$Id,
        [Parameter(Mandatory=$true)][string]$Vault
    ) 

    $_vault = Get-Vault -Vault $Vault
    if (!$_vault) {
        Write-host+ -NoTrace "'$($Vault)' isn't a vault in this account. Specify the vault with its ID or name." -ForegroundColor Red
        return
    }

    $_item = Get-VaultItem -Vault $($_vault.id) -Id $Id
    if (!$_item) {
        Write-Host+ "'$Id' isn't an item in the '$($_vault.name)' vault. Specify the item with its UUID, name, or domain." -ForegroundColor Red
        return
    }

    $op = "op item delete $Id --vault $($_vault.id)"
    $op += " 2>&1"

    $result = Invoke-Expression $op 
    if ($result -and $result.GetType().Name -eq "ErrorRecord") {
        Write-OpError $result
        return
    }

    $onePasswordItems = @{}
    if ((Get-Cache onePasswordItems).Exists) {
        $onePasswordItems = Read-Cache onePasswordItems
        if ($onePasswordItems.$($_item.name)) {
            $onePasswordItems.Remove($_item.name)
            $onePasswordItems | Write-Cache onePasswordItems
        }
    }
    
    return

}

#endregion ITEM