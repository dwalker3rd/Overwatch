# function Get-SupportedDriverTypes {
#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory=$false)][string]$DriverType
#     )
#     Get-Catalog
# }

function global:New-ConnectionString {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultConnectionStringsVault,
        [Parameter(Mandatory=$true)][string]$DatabaseType,
        
        [Parameter(Mandatory=$true,ParameterSetName="Default")]
        [Parameter(Mandatory=$true,ParameterSetName="Credentials")]
        [string]$Driver,

        [Parameter(Mandatory=$true)][string]$DriverType,
        
        [Parameter(Mandatory=$true,ParameterSetName="Default")]
        [Parameter(Mandatory=$true,ParameterSetName="Credentials")]
        [Alias("HostName")][string]$Server,
        
        [Parameter(Mandatory=$true,ParameterSetName="Default")]
        [Parameter(Mandatory=$true,ParameterSetName="Credentials")]
        [string]$Port,
        
        [Parameter(Mandatory=$true,ParameterSetName="Default")]
        [Parameter(Mandatory=$true,ParameterSetName="Credentials")]
        [string]$Database,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Alias("Uid")][string]$UserName,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Alias("Pwd")][string]$Password,        
        
        [Parameter(Mandatory=$true,ParameterSetName="Credentials")]
        [System.Management.Automation.PsCredential]$Credentials,

        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Parameter(Mandatory=$false,ParameterSetName="Credentials")]
        [ValidateSet("disable","allow","prefer","require","verify-ca","verify-full")]
        [AllowNull()]
        [string]$SslMode = $null,

        [Parameter(Mandatory=$true,ParameterSetName="ConnectionString")][string]
        $ConnectionString,
        
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME

    )

    $vaultItem = Get-ConnectionString -Id $Id -Vault $Vault -ComputerName $ComputerName
    if ($vaultItem) {
        Write-Host+ "Item '$Id' already exists" -ForegroundColor Red
        return
    }

    $vaultItem = @{ 
        DatabaseType = $DatabaseType
        DriverType = $DriverType
        Category = "Database"
    }

    if ([string]::IsNullOrEmpty($ConnectionString)) {
        $vaultItem += @{
            Driver = $Driver
            Server = $Server
            Port = $Port
            Database = $Database
            UserName = $Credentials ? $Credentials.UserName : $UserName
            Password = $Credentials ? $Credentials.GetNetworkCredential().Password : $Password
        }
        if ($SslMode) { $vaultItem += @{ SslMode = $SslMode } }
        $vaultItem.ConnectionString = Invoke-Expression "ConvertTo-$($DriverType)ConnectionString -InputObject `$vaultItem"
    }
    else {
        $vaultItem = Invoke-Expression "ConvertFrom-$($DriverType)ConnectionString -ConnectionString `"$ConnectionString`""
        $vaultItem.ConnectionString = $ConnectionString
    }

    $installedDrivers = (Invoke-Expression "Get-$($DriverType)InstalledDrivers -Name `"$Driver`" -ComputerName $ComputerName")
    if (!$installedDrivers) {
        throw "$DriverType driver '$Driver' is not installed on $($ComputerName.ToUpper())"
    }
    
    $ComputerNameParam = ((Get-Command New-VaultItem).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
    New-VaultItem -Id $Id @vaultItem -Vault $Vault @ComputerNameParam

    return

}

function global:Update-ConnectionString {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultConnectionStringsVault,
        [Parameter(Mandatory=$false)][string]$DatabaseType,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Parameter(Mandatory=$false,ParameterSetName="Credentials")]
        [string]$Driver,

        [Parameter(Mandatory=$false)][string]$DriverType,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Parameter(Mandatory=$false,ParameterSetName="Credentials")]
        [Alias("HostName")][string]$Server,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Parameter(Mandatory=$false,ParameterSetName="Credentials")]
        [string]$Port,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Parameter(Mandatory=$false,ParameterSetName="Credentials")]
        [string]$Database,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Alias("Uid")][string]$UserName,
        
        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Alias("Pwd")][string]$Password,        
        
        [Parameter(Mandatory=$true,ParameterSetName="Credentials")]
        [System.Management.Automation.PsCredential]$Credentials,

        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [Parameter(Mandatory=$false,ParameterSetName="Credentials")]
        [ValidateSet("disable","allow","prefer","require","verify-ca","verify-full")]
        [AllowNull()]
        [string]$SslMode = $null,

        [Parameter(Mandatory=$true,ParameterSetName="ConnectionString")][string]
        $ConnectionString,
        
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME

    )

    $vaultItem = Get-ConnectionString -Id $Id -Vault $Vault -ComputerName $ComputerName
    if (!$vaultItem) {
        Write-Host+ "Item '$Id' not found" -ForegroundColor Red
        return
    }

    $vaultItem.DatabaseType = $DatabaseType ?? $vaultItem.DatabaseType
    $vaultItem.DriverType = $DriverType ?? $vaultItem.DriverType

    if ([string]::IsNullOrEmpty($ConnectionString)) {
        $vaultItem.Driver = $Driver ?? $vaultItem.Driver
        $vaultItem.Server = $Server ?? $vaultItem.Server
        $vaultItem.Port = $Port ?? $vaultItem.Port
        $vaultItem.Database = $Database ?? $vaultItem.Database
        $vaultItem.UserName = $Credentials ? $Credentials.UserName : $UserName ?? $vaultItem.UserName
        $vaultItem.Password = $Credentials ? $Credentials.GetNetworkCredential().Password : $Password ?? $vaultItem.Password
        $vaultItem.SslMode = $SslMode ?? $vaultItem.SslMode
        $vaultItem.ConnectionString = Invoke-Expression "ConvertTo-$($DriverType)ConnectionString -InputObject `$vaultItem"
    }
    else {
        $vaultItem = Invoke-Expression "ConvertFrom-$($DriverType)ConnectionString -ConnectionString `"$ConnectionString`""
        $vaultItem.ConnectionString = $ConnectionString
    }

    $installedDrivers = (Invoke-Expression "Get-$($DriverType)InstalledDrivers -Name `"$Driver`" -ComputerName $ComputerName")
    if (!$installedDrivers) {
        throw "$DriverType driver '$Driver' is not installed on $($ComputerName.ToUpper())"
    }

    $vaultItem.Remove("Name")
    $vaultItem.Remove("timestamp")

    $ComputerNameParam = ((Get-Command Update-VaultItem).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
    Update-VaultItem -Id $Id @vaultItem -Vault $Vault @ComputerNameParam

    return

}

function global:Get-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultConnectionStringsVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $ComputerNameParam = (Get-Command Get-VaultItem).Parameters.Keys -contains "ComputerName" ? @{ ComputerName = $ComputerName } : @{}
    $vaultItem = Get-VaultItem -Id $Id -Vault $Vault @ComputerNameParam
    return $vaultItem

}

function global:Remove-ConnectionString {

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultConnectionStringsVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    if($PSCmdlet.ShouldProcess($Id)) {
        $ComputerNameParam = ((Get-Command Remove-VaultItem).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
        Remove-VaultItem -Id $Id -Vault $Vault @ComputerNameParam
    }

}

function global:Copy-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Source,
        [Parameter(Mandatory=$false,Position=0)][string]$SourceVault = $global:DefaultConnectionStringsVault,
        [Parameter(Mandatory=$false)][string]$SourceComputerName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory=$false,Position=1)][string]$Destination = $Source,
        [Parameter(Mandatory=$false,Position=0)][string]$DestinationVault = $SourceVault,
        [Parameter(Mandatory=$false)][string]$DestinationComputerName = $SourceComputerName
    )

    $connectionString = Get-ConnectionString $Source -Vault $SourceVault -ComputerName $SourceComputerName
    New-ConnectionString $Destination -ConnectionString $connectionString -Vault $DestinationVault -ComputerName $DestinationComputerName

}
