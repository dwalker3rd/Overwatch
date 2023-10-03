﻿<# 
.Synopsis
Credential service for Overwatch
.Description
This script provides credential management for Overwatch services, tasks and providers.  Credentials are 
stored in .secure files in the Overwatch data directory.
#>

<# 
.Synopsis
Request credentials from a user.
.Description
Prompts user for username and password and returns a Powershell credential object to the caller.
.Parameter Title
Optional title for the credential request.
.Parameter Message
Optional message for the credential request.
.Parameter Prompt1
Optional prompt for a user or account name.
.Parameter Prompt2
Optional prompt for a password or token
.Outputs
System.Management.Automation.PSCredential object.
#>
function global:Request-Credentials {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$UserName,
        [Parameter(Mandatory=$false)][string]$Password,
        [Parameter(Mandatory=$false)][string]$Title,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Prompt1 = "User",
        [Parameter(Mandatory=$false)][string]$Prompt2 = "Password"
    )

    if ($Title) {Write-Host+ -NoTimestamp -NoTrace $Title}
    if ($Message) {Write-Host+ -NoTimestamp -NoTrace $Message}
    $UserName = $UserName ? $UserName : (Read-Host -Prompt $Prompt1)
    $PasswordSecure = $Password ? (ConvertTo-SecureString $Password -AsPlainText -Force) : (Read-Host -Prompt $Prompt2 -AsSecureString)

    return New-Object System.Management.Automation.PSCredential($UserName,$PasswordSecure)

}

<# 
.Synopsis
Stores credentials in an Overwatch credential object/file.
.Description
Stores specified credentials in an Overwatch .secure file.  Credentials may be specified with the 
PSCredential parameter or, optionally, with the userName and password parameters.
.Parameter Name
Name of the credential object.
.Parameter Credentials
A System.Management.Automation.PSCredential object.
.Parameter UserName
Optional user or account name.
.Parameter Password
Optional password or token
.Parameter Key
If an encryption key is specified:
    - ConvertFrom-SecureString uses the AES encryption algorithm to encrypt the credentials.
    - The encryption key must have a length of 128, 192, or 256 bits.
    - The credentials can be encrypted locally or remotely.
If no encryption key is specified:
    - ConvertFrom-SecureString uses the Windows Data Protection API (DPAPI) to encrypt the credentials.
    - The credentials can only be encrypted on the local machine.
#>
function global:Set-Credentials {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$id,
        [Parameter(Mandatory=$false,ValueFromPipeline)][System.Management.Automation.PsCredential]$Credentials,
        [Parameter(Mandatory=$false)][Alias("Id")][string]$UserName,
        [Parameter(Mandatory=$false)][Alias("Token")][string]$Password,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Credentials = $Credentials ?? (Request-Credentials -UserName $UserName -Password $Password)

    if (!(Get-Credentials -Id $id -Vault $Vault -ComputerName $ComputerName)) {
        if ((Get-Command New-VaultItem).Parameters.Keys -contains "ComputerName") { $ComputerNameParam = @{ ComputerName = $ComputerName }}
        New-VaultItem -Category Login -Id $id -UserName $Credentials.UserName -Password $Credentials.GetNetworkCredential().Password -Vault $Vault @ComputerNameParam
    }
    else {
        if ((Get-Command Update-VaultItem).Parameters.Keys -contains "ComputerName") { $ComputerNameParam = @{ ComputerName = $ComputerName }}
        Update-VaultItem -Id $id -UserName $Credentials.UserName -Password $Credentials.GetNetworkCredential().Password -Vault $Vault @ComputerNameParam
    }

    return

}

<# 
.Synopsis
Gets/retrieves credentials from an Overwatch credential object/file.
.Description
Get the credentials, specified by NAME, from the Overwatch .secure file. 
.Parameter Name
Name of the credential file.
.Parameter Key
If an encryption key is specified:
    - ConvertTo-SecureString uses the AES encryption algorithm to decrypt the credentials.
    - The encryption key must have a length of 128, 192, or 256 bits.
    - The credentials can be decrypted locally or remotely.
If no encryption key is specified:
    - ConvertTo-SecureString uses the Windows Data Protection API (DPAPI) to decrypt the credentials.
    - The credentials can only be decrypted on the local machine.
.Outputs
System.Management.Automation.PSCredential object.
#>
function global:Get-Credentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [switch]$LocalMachine,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $ComputerNameParam = (Get-Command Get-VaultItem).Parameters.Keys -contains "ComputerName" ? @{ ComputerName = $ComputerName } : @{}
    $item = Get-VaultItem -Vault $Vault -Id $id @ComputerNameParam
    if (!$item) {return}

    $UserName = $item.UserName
    $Password = $item.Password | ConvertTo-SecureString -AsPlainText

    if ($LocalMachine) {
        if ($global:PrincipalContextType -eq [System.DirectoryServices.AccountManagement.ContextType]::Machine) { 
            if ($creds.UserName -notlike ".\*" -and $creds.UserName -notlike "$($env:COMPUTERNAME)\*") {
                $UserName = ".\$UserName"
            }
        }
        if ($global:PrincipalContextType -eq [System.DirectoryServices.AccountManagement.ContextType]::Domain) {
            if ($creds.UserName -notlike "$($global:Platform.Domain)\*") {
                $UserName = "$($global:Platform.Domain)\$UserName"
            }
        }
    }

    return New-Object System.Management.Automation.PSCredential($UserName, $Password)

}

function global:Remove-Credentials {

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    if($PSCmdlet.ShouldProcess($id)) {
        if ((Get-Command Remove-VaultItem).Parameters.Keys -contains "ComputerName") { $ComputerNameParam = @{ ComputerName = $ComputerName }}
        Remove-VaultItem -Vault $Vault -Id $id @ComputerNameParam
        if ((Get-Command Remove-VaultKey).Parameters.Keys -contains "ComputerName") { $ComputerNameParam = @{ ComputerName = $ComputerName }}
        Remove-VaultKey -Id $id -Vault $Vault @ComputerNameParam
    }

}

function global:Copy-Credentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Source,
        [Parameter(Mandatory=$true)][string]$SourceVault,
        [Parameter(Mandatory=$false)][string]$SourceComputerName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory=$false,Position=1)][string]$Destination = $Source,
        [Parameter(Mandatory=$false)][string]$DestinationVault = $SourceVault,
        [Parameter(Mandatory=$false)][string]$DestinationComputerName = $SourceComputerName
    )

    $creds = Get-Credentials $Source -Vault $SourceVault -ComputerName (Get-OverwatchController $SourceComputerName)
    Set-Credentials $Destination -Credentials $creds -Vault $DestinationVault -ComputerName (Get-OverwatchController $DestinationComputerName)

}

<# 
.Synopsis
Validates credentials.
.Description
Validates the specified credentials.  Note that this only applies to Windows authentication against
local machines or domains.
.Parameter Name
Name of the credential object.
.Outputs
True or False
#>
function global:Test-Credentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [switch]$NoValidate,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    
    $Credentials = Get-Credentials -Id $id -Vault $Vault -ComputerName $ComputerName
    if (!$Credentials) {return $false}

    if ($NoValidate) {return $Credentials ? $true : $false}

    $UserName = $Credentials.UserName
    $Password = $Credentials.GetNetworkCredential().Password

    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($PrincipalContextType, $PrincipalContextName)
    $validated = $principalContext.ValidateCredentials($UserName, $Password)

    Write-Host+ -NoTrace -NoTimeStamp -IfVerbose "Credentials are $($validated ? "valid" : "invalid") for $($PrincipalContextType.ToString().ToLower()) $PrincipalContextName" -ForegroundColor ($validated ? "DarkGreen" : "DarkRed")
    Write-Host+ -IfVerbose

    return $validated

}

<# 
.Synopsis
Generates a new random password.
.Description
Generates a new random password.
.Parameter Length
The length of the password.
.Parameter MinimumSpecialCharacters
The number of special characters to include in the password.
.Parameter MinimumNumberCharacters
The number of numeric digits to include in the password.
.Parameter MinimumUpperCaseCharacters
The number of special characters to include in the password.
.Parameter ExcludeSpecialCharacters
Exclude special characters.
.Parameter ExcludeNumberCharacters
Exclude numeric digits.
.Parameter ExcludeUpperCaseCharacters
Exclude upper case characters.
.Outputs
A password
#>
function global:New-RandomPassword {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][ValidateRange(12,20)][int]$Length = ((16..20) | Get-Random),
        [Parameter(Mandatory=$false)][ValidateRange(0,4)][int]$MinimumSpecialCharacters = ((1..4) | Get-Random),
        [Parameter(Mandatory=$false)][ValidateRange(0,4)][int]$MinimumNumberCharacters = ((1..4) | Get-Random),
        [Parameter(Mandatory=$false)][ValidateRange(0,4)][int]$MinimumUpperCaseCharacters = ((1..4) | Get-Random),
        [switch]$ExcludeSpecialCharacters,
        [switch]$ExcludeNumberCharacters,
        [switch]$ExcludeUpperCaseCharacters
    )

    $numberCharacters = (48..57)
    $upperCaseCharacters = (65..90)
    $lowercaseCharacters = (97..122)
    $specialCharacters = @((33,35) + (36..38) + (42..44) + (61,63,64) + (91,93,94))

    $MinimumSpecialCharacters = $ExcludeSpecialCharacters ? 0 : $MinimumSpecialCharacters
    $MinimumNumberCharacters = $ExcludeNumberCharacters ? 0 : $MinimumNumberCharacters
    $MinimumUpperCaseCharacters = $ExcludeUpperCaseCharacters ? 0 : $MinimumUpperCaseCharacters

    $minimumLowerCaseCharacters = $Length - $MinimumSpecialCharacters - $MinimumNumberCharacters - $MinimumUpperCaseCharacters

    Write-Host+ -NoTrace -IfDebug "Length: $Length"
    Write-Host+ -NoTrace -IfDebug "MinimumSpecial Characters: $MinimumSpecialCharacters"
    Write-Host+ -NoTrace -IfDebug "MinimumNumberCharacters: $MinimumNumberCharacters"
    Write-Host+ -NoTrace -IfDebug "MinimumUpperCaseCharacters: $MinimumUpperCaseCharacters"
    Write-Host+ -NoTrace -IfDebug "minimumLowerCaseCharacters: $minimumLowerCaseCharacters"

    $passwordCharacters = @()
    if ($MinimumSpecialCharacters -gt 0) {$passwordCharacters += $specialCharacters | Get-Random -Count $MinimumSpecialCharacters}
    if ($MinimumNumberCharacters -gt 0) {$passwordCharacters += $numberCharacters | Get-Random -Count $MinimumNumberCharacters}
    if ($MinimumUpperCaseCharacters -gt 0) {$passwordCharacters += $upperCaseCharacters | Get-Random -Count $MinimumUpperCaseCharacters}
    $passwordCharacters += $lowercaseCharacters | Get-Random -Count $minimumLowerCaseCharacters
    $password = -join ($passwordCharacters | Get-Random -Count $Length | ForEach-Object {[char]$_})

    return $password

}