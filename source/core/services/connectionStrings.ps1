function global:Set-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false,ValueFromPipeline)][string]$ConnectionString
    )
    
    $Name = $Name.ToLower()
    $Key = New-EncryptionKey $Name
    $encryptedConnectionString = $connectionString | ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString -Key $key
    Add-ToVault -Vault ConnectionStrings -Name $Name -InputObject @{ "connectionString" = $encryptedConnectionString }

    return

}

function global:Get-ConnectionString {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][object]$Key
    )

    $Name = $Name.ToLower()
    $Key = $Key ?? (Get-FromVault -Vault Key -Name $Name)
    $connectionString =  (Get-FromVault -Vault ConnectionStrings -Name $Name).connectionString | ConvertTo-SecureString -Key $Key | ConvertFrom-SecureString -AsPlainText

    return $connectionString

}

function global:Remove-ConnectionString {

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name
    )

    if($PSCmdlet.ShouldProcess($Name)) {
        Remove-FromVault -Vault Key -Name $Name
        Remove-FromVault -Vault ConnectionStrings -Name $Name
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
