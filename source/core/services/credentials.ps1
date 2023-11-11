function global:Request-Credentials {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][Alias("Account")][string]$UserName,
        [Parameter(Mandatory=$false)][Alias("Token")][string]$Password,
        [Parameter(Mandatory=$false)][string]$Title,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Prompt1 = "User",
        [Parameter(Mandatory=$false)][string]$Prompt2 = "Password"
    )

    if ($Title) {Write-Host+ -NoTimestamp -NoTrace $Title}
    if ($Message) {Write-Host+ -NoTimestamp -NoTrace $Message}
    $Prompt1 = $emptyString.PadLeft($global:WriteHostPlusIndentGlobal," ") + $Prompt1
    $Prompt2 = $emptyString.PadLeft($global:WriteHostPlusIndentGlobal," ") + $Prompt2
    $UserName = $UserName ? $UserName : (Read-Host -Prompt $Prompt1)
    $PasswordSecure = $Password ? (ConvertTo-SecureString $Password -AsPlainText -Force) : (Read-Host -Prompt $Prompt2 -AsSecureString)

    return New-Object System.Management.Automation.PSCredential($UserName,$PasswordSecure)

}

function global:Set-Credentials {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false,ValueFromPipeline)][System.Management.Automation.PsCredential]$Credentials,
        [Parameter(Mandatory=$false)][Alias("Account")][string]$UserName,
        [Parameter(Mandatory=$false)][Alias("Token")][string]$Password,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Credentials = $Credentials ?? (Request-Credentials -UserName $UserName -Password $Password)

    if (!(Get-Credentials -Id $Id -Vault $Vault -ComputerName $ComputerName)) {
        $ComputerNameParam = ((Get-Command New-VaultItem).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
        New-VaultItem -Category Login -Id $Id -UserName $Credentials.UserName -Password $Credentials.GetNetworkCredential().Password -Vault $Vault @ComputerNameParam
    }
    else {
        $ComputerNameParam = ((Get-Command Update-VaultItem).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
        Update-VaultItem -Id $Id -UserName $Credentials.UserName -Password $Credentials.GetNetworkCredential().Password -Vault $Vault @ComputerNameParam
    }

    return

}

function global:Get-Credentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [switch]$LocalMachine,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $ComputerNameParam = (Get-Command Get-VaultItem).Parameters.Keys -contains "ComputerName" ? @{ ComputerName = $ComputerName } : @{}
    $item = Get-VaultItem -Vault $Vault -Id $Id @ComputerNameParam
    if (!$item) {return}

    $UserName = $item.UserName
    $Password = $item.Password 

    if ($Password.GetType().Name -ne "SecureString") {
        $Password = $Password | ConvertTo-SecureString -AsPlainText
    }

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
        [Parameter(Mandatory=$false,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    if($PSCmdlet.ShouldProcess($Id)) {
        $ComputerNameParam = ((Get-Command Remove-VaultItem).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
        Remove-VaultItem -Vault $Vault -Id $Id @ComputerNameParam
        $ComputerNameParam = ((Get-Command Remove-VaultKey).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
        Remove-VaultKey -Id $Id -Vault $Vault @ComputerNameParam
    }

}

function global:Copy-Credentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][Alias("Id")][string]$SourceId,
        [Parameter(Mandatory=$true)][Alias("Vault")][string]$SourceVault,
        [Parameter(Mandatory=$false)][Alias("ComputerName")][string]$SourceComputerName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory=$false,Position=1)][string]$DestinationId = $SourceId,
        [Parameter(Mandatory=$false)][string]$DestinationVault = $SourceVault,
        [Parameter(Mandatory=$false)][string]$DestinationComputerName = $SourceComputerName
    )

    $creds = Get-Credentials $SourceId -Vault $SourceVault -ComputerName (Get-OverwatchController $SourceComputerName)
    Set-Credentials $DestinationId -Credentials $creds -Vault $DestinationVault -ComputerName (Get-OverwatchController $DestinationComputerName)

}

function global:Test-Credentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Vault = $global:DefaultCredentialsVault,
        [switch]$NoValidate,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    
    $Credentials = Get-Credentials -Id $Id -Vault $Vault -ComputerName $ComputerName
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