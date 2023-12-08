function global:Start-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$NoWait
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return

}

function global:Stop-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$NoWait
    )

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return

}

function global:Show-CloudStatus {

    [CmdletBinding()]
    param()

    throw ("$($MyInvocation.MyCommand) is a STUB")
    return

}