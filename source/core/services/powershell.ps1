function global:Get-PSSession+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string]$ConfigurationName = $global:PSSessionConfigurationName,
        [switch]$All
    )

    $_psSessions = Get-PSSession
    if ($ComputerName) { $_psSession = $_psSession | Where-Object {$_.ComputerName -in $ComputerName} }

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

    $params = @()
    if ($global:UseCredssp) { 
        $params += @{ 
            Credential = Get-Credentials "localadmin-$($Platform.Instance)" -Credssp
            Authentication = Credssp
        }
    }

    $_psSession = New-PSSession @params -ComputerName $ComputerName -ConfigurationName $ConfigurationName -ErrorAction SilentlyContinue 

    return $_psSession

}    

function global:Use-PSSession+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string]$ConfigurationName = $global:PSSessionConfigurationName
    )

    $_psSession = Get-PSSession+
    if ($ComputerName) { $_psSession = $_psSession | Where-Object {$_.ComputerName -in $ComputerName} }

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
    $_psSessionNodesMissing = $_psSessionAvailable ? (Compare-Object -PassThru $_psSessionAvailable.ComputerName (pt nodes -k)) : (pt nodes -k)

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
        $_psSession = Use-PSSession+
        if ($Id) { $_psSession = $_psSession | Where-Object {$_.Id -in $Id} }
        if ($ComputerName) { $_psSession = $_psSession | Where-Object {$_.ComputerName -in $ComputerName} }
    }

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

    if ($_psSession.Name -contains "WinPSCompatSession") {
        Write-Host+ -NoTrace -NoTimestamp "Remove-PSSession+ can only remove sessions using the $($global:PSSessionConfigurationName) session configuration." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoTimestamp "Use the ConfigurationName parameter to remove other PSSession configurations." ForegroundColor DarkYellow
    }

    # Ensure that the WinPSCompatSession is NEVER removed
    $_psSession = $_psSession | 
        Where-Object { $_.Name -ne "WinPSCompatSession" } 
    
    Remove-PSSession $_psSession
    return ($_psSession | Where-Object {$_.State -notin ("Closed")})

}