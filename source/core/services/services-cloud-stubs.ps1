function global:Start-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$NoWait
    )

    Write-Host+ "$($MyInvocation.MyCommand) is a STUB" -ForegroundColor DarkYellow
    return

}

function global:Stop-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
        [switch]$NoWait
    )

    Write-Host+ "$($MyInvocation.MyCommand) is a STUB" -ForegroundColor DarkYellow
    return

}

function global:Show-CloudStatus {

    [CmdletBinding()]
    param()

    Write-Host+ "$($MyInvocation.MyCommand) is a STUB" -ForegroundColor DarkYellow
    return

}