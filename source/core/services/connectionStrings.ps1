function global:Set-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false,ValueFromPipeline)][string]$ConnectionString,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    
    $Name = $Name.ToLower()
    $Key = New-EncryptionKey $Name
    $encryptedConnectionString = $connectionString | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $key
    Add-ToVault -Vault ConnectionStrings -Name $Name -InputObject @{ "connectionString" = $encryptedConnectionString } -ComputerName $ComputerName

    return

}

function global:Get-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Key,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Name = $Name.ToLower()
    $Key = $Key ?? (Get-FromVault -Vault Key -Name $Name -ComputerName $ComputerName)
    $connectionString =  (Get-FromVault -Vault ConnectionStrings -Name $Name -ComputerName $ComputerName).connectionString | ConvertTo-SecureString -Key $Key | ConvertFrom-SecureString -AsPlainText

    return $connectionString

}

function global:Remove-ConnectionString {

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    if($PSCmdlet.ShouldProcess($Name)) {
        Remove-FromVault -Vault Key -Name $Name -ComputerName $ComputerName
        Remove-FromVault -Vault ConnectionStrings -Name $Name -ComputerName $ComputerName
    }

}

function global:Copy-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Source,
        [Parameter(Mandatory=$true,Position=1)][string]$Target
    )

    $connectionString = Get-ConnectionString $Source
    Set-ConnectionString $Target -ConnectionString $connectionString

}
