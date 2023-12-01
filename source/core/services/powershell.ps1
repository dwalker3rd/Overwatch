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

    $_psSession = @()
    if ($global:UseCredssp) { 
        foreach ($node in $ComputerName) {
            $owt = Get-OverwatchTopology nodes.$node
            $creds = Get-Credentials "localadmin-$($owt.Environ)" -ComputerName $owt.Controller -LocalMachine
            $_psSession += New-PSSession -ComputerName $node -ConfigurationName $ConfigurationName -Credential $creds -Authentication Credssp -ErrorAction SilentlyContinue
        }
    }
    else {
        $_psSession += New-PSSession -ComputerName $ComputerName -ConfigurationName $ConfigurationName -ErrorAction SilentlyContinue
    } 

    # if $_psSession is null, verify that the WinRM service is running
    # if the WinRM service is NOT running, start it and call New-PSSession+ again
    if (!$_psSession -and !$winRMRetry) {
        $winRM = Get-Service+ WinRM
        if ($winRM.Status -ne "Running") { 
            Start-Service+ WinRM
            $isRunning = Wait-Service WinRM -WaitTimeInSeconds 5 -TimeOutInSeconds 15
            if ($isRunning) { 
                $winRMRetry = $true
                $_psSession += New-PSSession -ComputerName $ComputerName -ConfigurationName $ConfigurationName -ErrorAction SilentlyContinue
            }
        }
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
        Write-Host+ -NoTrace -NoTimestamp "Use the ConfigurationName parameter to remove other PSSession configurations." -ForegroundColor DarkYellow
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
        Write-Host+ -NoTrace -NoTimestamp "Use the ConfigurationName parameter to remove other PSSession configurations." -ForegroundColor DarkYellow
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

function global:ConvertTo-PSCustomObject {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,ValueFromPipeline)][object]$InputObject
    )
    begin { 
        $outputObject = @() 
    }
    process { 
        $outputObject += [PSCustomObject]$InputObject 
    }
    end { 
        return $outputObject 
    }

}

function global:Get-PSBoundParameters {

    # Gets the bound parameters of the PREVIOUS command on the callstack
    # This is a convenience cmdlet for the caller

    [CmdletBinding()]
    param ()

    $callStack = Get-PSCallStack
    $invocationInfo = $callStack[1].InvocationInfo

    $boundParameters = @{}
    foreach ($key in $invocationInfo.BoundParameters.Keys) {
        $boundParameters += @{ $key = $invocationInfo.BoundParameters.$key }
    }
    return $boundParameters | ConvertTo-PSCustomObject

}

#region PSRESOURCEGET FALLBACK SUPPORT

    if ($PSVersionTable.PSVersion -lt "7.4.0") {

        function global:Get-PSResourceRepository {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false,Position=0)][string]$Name
            )

            $repository = @()
            if ([string]::IsNullOrEmpty($Name)) {
                $repository = Get-PackageSource
            }
            else {
                $repository = Get-PackageSource -Name $Name
            }

            return $repository

        }

        function global:Register-PSResourceRepository {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][Uri]$Uri,
                [switch]$PSGallery,
                [switch]$Trusted
            )

            if ([string]::IsNullOrEmpty($Name) -and $PSGallery) {
                $Name = "PSGallery"
            }
            $ProviderName = $Name

            if ((Get-PackageSource -ProviderName $ProviderName)) { return }

            $params = @{}
            $params += @{
                Name = $Name
                Trusted = $Trusted.IsPresent
                ProviderName = $ProviderName
            }
            if ($Uri) { $params += @{ Location = $Uri }}

            return Register-PackageSource @params

        }

        function global:Find-PSResource {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Repository,
                [Parameter(Mandatory=$false)][string]$Version,
                [switch]$IncludeDependencies
            )

            $params = @{}
            $params += @{
                Name = $Name
            }
            if ($Repository) { $params += @{ Repository = $Repository }}
            if ($IncludeDependencies) { $params += @{ IncludeDependencies = $IncludeDependencies }}

            $nugetVersionRange = [Regex]::Matches($Version,$global:RegexPattern.NuGet.VersionRange)

            $bracketLeft = $nugetVersionRange[0].Groups['bracketLeft'].Value
            $versionRangeMinimum = ![string]::IsNullOrEmpty($nugetVersionRange[0].Groups['versionRangeMinimum'].Value) ? [version]($nugetVersionRange[0].Groups['versionRangeMinimum'].Value) : $null
            $comma = $nugetVersionRange[0].Groups['comma'].Value
            $versionRangeMaximum = ![string]::IsNullOrEmpty($nugetVersionRange[0].Groups['versionRangeMaximum'].Value) ? [version]($nugetVersionRange[0].Groups['versionRangeMaximum'].Value) : $null
            $bracketRight = $nugetVersionRange[0].Groups['bracketRight'].Value

            if ([string]::IsNullOrEmpty($bracketLeft) -and [string]::IsNullOrEmpty($bracketLeft) -or 
            (![string]::IsNullOrEmpty($bracketLeft) -and $bracketLeft -eq "[" -and ![string]::IsNullOrEmpty($bracketRight) -and $bracketRight -eq "]" -and [string]::IsNullOrEmpty($comma))) {
                $params += @{ RequiredVersion = $versionRangeMinimum }
                return Find-Module @params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null
            }
            else {
                $params += @{ AllVersions = $true }
            }

            $repositoryModule = Find-Module @params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null

            if (![string]::IsNullOrEmpty($versionRangeMinimum)) {
                if (![string]::IsNullOrEmpty($bracketLeft) -and $bracketLeft -eq "[") {
                    $repositoryModule = $repositoryModule | Where-Object {[version]($_.Version) -ge $versionRangeMinimum}
                }
                else {
                    $repositoryModule = $repositoryModule | Where-Object {[version]($_.Version) -gt $versionRangeMinimum}
                }
            }
            if (![string]::IsNullOrEmpty($versionRangeMaximum)) {
                if (![string]::IsNullOrEmpty($bracketRight) -and $bracketRight -eq "]") {
                    $repositoryModule = $repositoryModule | Where-Object {[version]($_.Version) -le $versionRangeMaximum}
                }
                else {
                    $repositoryModule = $repositoryModule | Where-Object {[version]($_.Version) -lt $versionRangeMaximum}
                }
            }

            return $repositoryModule

        }

        function global:Get-InstalledPSResource {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Version
            )

            $params = @{}
            $params += @{
                Name = $Name
            }

            $nugetVersionRange = [Regex]::Matches($Version,$global:RegexPattern.NuGet.VersionRange)

            $bracketLeft = $nugetVersionRange[0].Groups['bracketLeft'].Value
            $versionRangeMinimum = ![string]::IsNullOrEmpty($nugetVersionRange[0].Groups['versionRangeMinimum'].Value) ? [version]($nugetVersionRange[0].Groups['versionRangeMinimum'].Value) : $null
            $comma = $nugetVersionRange[0].Groups['comma'].Value
            $versionRangeMaximum = ![string]::IsNullOrEmpty($nugetVersionRange[0].Groups['versionRangeMaximum'].Value) ? [version]($nugetVersionRange[0].Groups['versionRangeMaximum'].Value) : $null
            $bracketRight = $nugetVersionRange[0].Groups['bracketRight'].Value

            if ([string]::IsNullOrEmpty($bracketLeft) -and [string]::IsNullOrEmpty($bracketLeft) -or 
            (![string]::IsNullOrEmpty($bracketLeft) -and $bracketLeft -eq "[" -and ![string]::IsNullOrEmpty($bracketRight) -and $bracketRight -eq "]" -and [string]::IsNullOrEmpty($comma))) {
                if (![string]::IsNullOrEmpty($versionRangeMinimum)) { $params += @{ RequiredVersion = $versionRangeMinimum } }
                $installedModule = Get-InstalledModule @params  -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null
                return $installedModule
            }
            else {
                $params += @{ AllVersions = $true }
            }

            $installedModule = Get-InstalledModule @params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null

            if (![string]::IsNullOrEmpty($versionRangeMinimum)) {
                if (![string]::IsNullOrEmpty($bracketLeft) -and $bracketLeft -eq "[") {
                    $installedModule = $installedModule | Where-Object {[version]($_.Version) -ge $versionRangeMinimum}
                }
                else {
                    $installedModule = $installedModule | Where-Object {[version]($_.Version) -gt $versionRangeMinimum}
                }
            }
            if (![string]::IsNullOrEmpty($versionRangeMaximum)) {
                if (![string]::IsNullOrEmpty($bracketRight) -and $bracketRight -eq "]") {
                    $installedModule = $installedModule | Where-Object {[version]($_.Version) -le $versionRangeMaximum}
                }
                else {
                    $installedModule = $installedModule | Where-Object {[version]($_.Version) -lt $versionRangeMaximum}
                }
            }

            return $installedModule | Sort-Object -Property Version -Descending

        }

        function global:Install-PSResource {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Repository,
                [Parameter(Mandatory=$false)][string]$Version,
                [switch]$Reinstall
            )

            $params = @{}
            $params += @{
                Name = $Name
                RequiredVersion = $null
                AcceptLicense = $true
            }
            if ($Repository) { $params += @{ Repository = $Repository }}
            if ($Reinstall) { $params += @{ Reinstall = $Reinstall }}

            $installedModule = @()
            $repositoryModule = Find-PSResource -Name $Name -Repository $Repository -Version $Version
            $repositoryModule | Foreach-Object {
                $params.RequiredVersion = $_.Version
                $global:InformationPreference = "SilentlyContinue"
                Install-Module @params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null | Out-Null
                $global:InformationPreference = "Continue"
                $installedModule += Get-InstalledPSResource -Name $_.Name -Version $_.Version
            }

            return $installedModule | Sort-Object -Property Version -Descending 

        }

        function global:Uninstall-PSResource {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Version
            )

            $params = @{}
            $params += @{
                Name = $Name
            }
            if ($Version) { $params += @{ Version = $Version }}

            $uninstalledModule = @()
            $installedModule = Get-InstalledPSResource @params | Sort-Object -Property Version -Descending

            $params = @{}
            $params += @{
                Name = $Name
                RequiredVersion = $null
            }

            $installedModule | Foreach-Object {
                $params.RequiredVersion = $_.Version
                $global:InformationPreference = "SilentlyContinue"
                Uninstall-Module @params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null | Out-Null
                $global:InformationPreference = "Continue"
                $uninstalledModule += Get-InstalledPSResource -Name $_.Name -Version $_.Version
            }

            return

        }

    }

#endregion PSRESOURCEGET FALLBACK SUPPORT