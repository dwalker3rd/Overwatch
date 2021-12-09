   
function global:Get-ServerInfo {
        
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    ) 

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Confirm-ServerStatus {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
        # [Parameter(Mandatory=$false)][object]$serverInfo = $(Get-serverInfo)
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Register-GroupPolicyScript {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet("Shutdown","Startup")][string]$Type,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [switch]$AllowDuplicates
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Get-Disk {

    [CmdletBinding()] 
    param(
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Confirm-ServiceLogonCredentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$StartName,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Set-ServiceLogonCredentials {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$StartName,
        [Parameter(Mandatory=$true)][string]$StartPassword,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Confirm-LogOnAsAService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Policy,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Grant-LogOnAsAService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Revoke-LogOnAsAService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Get-ServiceSecurity {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function global:Set-ServiceSecurity {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}

function Get-PlatformInstallProperties
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    Param
    (
        [Parameter(Mandatory=$true, Position=0)][SupportsWildcards()][string]$ProgramName
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return
}