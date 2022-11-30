<# 
.Synopsis
Creates a 256-bit AES encryption key.
.Description
Creates a 256-bit AES encryption key for use with credential files.
.Outputs
256-bit AES encryption key.
#>
function global:New-EncryptionKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Name = $Name.ToLower()
    
    $key = New-Object Byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($key)
    
    Add-ToVault -Vault Key -Name $Name -InputObject $key -ComputerName $ComputerName

    return $key

}

<# 
.Synopsis
Replaces encryption keys.
.Description
Replaces encryption keys for the specified credential or for all credentials.
.Parameter Name
Credential name.
#>
function global:Replace-EncryptionKey {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name
    )

    $credentialNames = ![string]::IsNullOrEmpty($Name) ? $Name : (Get-VaultKeys)
    foreach ($credentialName in $credentialNames) {
        Get-Credentials $credentialName | Set-Credentials $credentialName
    }

    return

}