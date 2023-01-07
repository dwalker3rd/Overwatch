function global:Get-PSSession+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$ConfigurationName = $global:PSSessionConfigurationName,
        [switch]$All
    )

    $_psSessions = Get-PSSession
    if ($ComputerName) { $_psSessions = $_psSessions | Where-Object {$_.ComputerName -in $ComputerName} }

    if ($All) {
       return $_psSessions
    }

    # Only list PSSessions using $global:PSSessionConfigurationName as set by Overwatch 
    # $global:PSSessinConfigurationName is set by Overwatch to "PowerShell.$($PSVersionTable.PSVersion.Major)"
    if (![string]::IsNullOrEmpty($ConfigurationName)) {
        $_psSessions = $_psSessions |
            Where-Object { $_.ConfigurationName -eq $ConfigurationName}
    }

    # Ensure that, at a minimum, the WinPSCompatSession is not listed
    $_psSessions = $_psSessions | 
        Where-Object { $_.Name -ne "WinPSCompatSession" } 
    
    # Sort by State and Availability so that the best PSSessions are at the top of the list
    $_psSessions = $_psSessions |
        Sort-Object -Property @{Expression = "State"; Descending = $true}, @{Expression = "Availability"; Descending = $false}  

    return $_psSessions

}

function global:New-PSSession+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string]$ConfigurationName = $global:PSSessionConfigurationName
    )

    $_psSession = $null
    if ($global:UseCredssp) { 
        $creds = Get-Credentials "localadmin-$($Platform.Instance)" -Credssp
        $_psSession = New-PSSession -ComputerName $ComputerName -ConfigurationName $ConfigurationName -Credential $creds -Authentication Credssp -ErrorAction SilentlyContinue
    }
    else {
        $_psSession = New-PSSession -ComputerName $ComputerName -ConfigurationName $ConfigurationName -ErrorAction SilentlyContinue
    } 

    return $_psSession

}    

function global:Use-PSSession+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string]$ConfigurationName = $global:PSSessionConfigurationName
    )

    $_psSession = Get-PSSession+ -ComputerName $ComputerName
    # if ($ComputerName) { $_psSession = $_psSession | Where-Object {$_.ComputerName -in $ComputerName} }

    # Only reuse PsSession using $global:PSSessionConfigurationName as set by Overwatch 
    # $global:PSSessinConfigurationName is set by Overwatch to "PowerShell.$($PSVersionTable.PSVersion.Major)"
    if (![string]::IsNullOrEmpty($ConfigurationName)) {
        $_psSession = $_psSession |
            Where-Object { $_.ConfigurationName -eq $ConfigurationName}
    }

    # Ensure that, at a minimum, the WinPSCompatSession is NEVER reused
    $_psSession = $_psSession | 
        Where-Object { $_.Name -ne "WinPSCompatSession" } 
        
    # Only resuse PSSession with RunspaceAvailability = "Available"
    $_psSession = $_psSession | 
        Where-Object { $_.Availability -eq [System.Management.Automation.Runspaces.RunspaceAvailability]::Available } 
    
    # Sort by State and Availability so that the best PsSession are at the top of the list
    $_psSession = $_psSession |
        Sort-Object -Property @{Expression = "State"; Descending = $true}, @{Expression = "Availability"; Descending = $false}  

    $_psSessionAvailable = @()
    $_psSessionAvailable += $_psSession | Sort-Object -Property ComputerName -Unique
    $_psSessionNodesMissing = $_psSessionAvailable ? (Compare-Object -PassThru $_psSessionAvailable.ComputerName $ComputerName) : $ComputerName

    $_psSession = @()
    $_psSession += $_psSessionAvailable
    if (![string]::IsNullOrEmpty($_psSessionNodesMissing)) { 
        $_psSession += New-PSSession+ -ComputerName $_psSessionNodesMissing -ConfigurationName $ConfigurationName
    }

    return $_psSession

}   

function global:Remove-PSSession+ {

    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [Parameter(Mandatory=$true,ParameterSetName="BySession")]
        [object[]]$Session,

        [Parameter(Mandatory=$true,ParameterSetName="ById")]
        [int32[]]$Id,

        [Parameter(Mandatory=$false,ParameterSetName="Default")]
        [string[]]$ComputerName,

        [Parameter(Mandatory=$false)][string]$ConfigurationName = $global:PSSessionConfigurationName
    )

    $_psSession = $Session
    if (!$_psSession) {
        $_psSession = Get-PSSession+ -All
        if ($Id) { $_psSession = $_psSession | Where-Object {$_.Id -in $Id} }
        if ($ComputerName) { $_psSession = $_psSession | Where-Object {$_.ComputerName -in $ComputerName} }
    }

    if (!$_psSession) { return }

    if (Compare-Object ($_psSession.ConfigurationName | Sort-Object -Unique) $ConfigurationName) {
        Write-Host+ -NoTrace -NoTimestamp "Remove-PSSession+ can only remove sessions using the $($global:PSSessionConfigurationName) session configuration." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoTimestamp "Use the ConfigurationName parameter to remove other PSSession configurations." ForegroundColor DarkYellow
    }

    # Only remove PSSessions using $global:PSSessionConfigurationName as set by Overwatch 
    # $global:PSSessionConfigurationName is set by Overwatch to "PowerShell.$($PSVersionTable.PSVersion.Major)"
    if (![string]::IsNullOrEmpty($ConfigurationName)) {
        $_psSession = $_psSession |
            Where-Object { $_.ConfigurationName -eq $ConfigurationName}
    }

    if (!$_psSession) { return }

    if ($_psSession.Name -contains "WinPSCompatSession") {
        Write-Host+ -NoTrace -NoTimestamp "Remove-PSSession+ can only remove sessions using the $($global:PSSessionConfigurationName) session configuration." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoTimestamp "Use the ConfigurationName parameter to remove other PSSession configurations." ForegroundColor DarkYellow
    }

    # Ensure that the WinPSCompatSession is NEVER removed
    $_psSession = $_psSession | 
        Where-Object { $_.Name -ne "WinPSCompatSession" } 

    if (!$_psSession) { return }
    
    Remove-PSSession $_psSession
    return 
}

function global:Get-WSManTrustedHosts {

    [CmdletBinding()]
    param ()

    return Get-Item WSMan:\localhost\Client\TrustedHosts

}

function global:Add-WSManTrustedHosts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $trustedHosts = Get-WSManTrustedHosts
    if ($trustedHosts.Value -notcontains "*") {
        foreach ($node in $ComputerName) {
            if ($node -notin $trustedHosts.Value) {
                $ignoreOutput = Set-Item WSMan:\localhost\Client\TrustedHosts -Value $node -Concatenate -Force
                $ignoreOutput | Out-Null
            }
        }
    }

    return Get-WSManTrustedHosts

}

function global:Remove-WSManTrustedHosts {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $trustedHosts = Get-WSManTrustedHosts
    if ($trustedHosts.Value -notcontains "*") {
        $newTrustedHosts = $trustedHosts.Value -split "," | Where-Object {$_ -notin $ComputerName}
        $ignoreOutput = Set-Item WSMan:\localhost\Client\TrustedHosts -Value ($newTrustedHosts -join ",") -Force
        $ignoreOutput | Out-Null
    }

    return Get-WSManTrustedHosts

}