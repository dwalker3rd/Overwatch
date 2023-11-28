$global:PreflightChecksCompleted = $true

function global:Invoke-Preflight {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$true,Position=0)]
        [ValidateSet("Check","Update")]
        [string]$Action,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateSet("OS","Platform","PlatformInstance")]
        [string]$Target,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName,

        [switch]$Quiet,
        [switch]$Throw

    )

    $noun = "Preflight"

    switch ($Target) {
        "PlatformInstance" {
            $Id = $global:Platform.Instance
            $Name = ![string]::IsNullOrEmpty($ComputerName) ? $ComputerName : $global:Platform.Instance
        }
        default {
            $Id = Invoke-Expression "`$global:$($Target).Id"
            $Name = Invoke-Expression "`$global:$($Target).Name"
        }
    }

    $preflightPath = switch ($Target) {
        "Overwatch" {
            "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower()).ps1"
        }
        default {
            "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower())-$($Id.ToLower()).ps1"
        }
    }
    
    if (Test-Path -Path $preflightPath) {
        
        Write-Host+ -Iff $(!$Quiet.IsPresent) 
        $message = "<$Name $noun $Action <.>48> PENDING"
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray 

        Write-Log -Action $noun $Action -Target $Id

        $fail = $false
        $exceptionMessage = $null
        try{
            $command = $preflightPath
            $ComputerNameParam = ((Get-Command $command).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
            . $command @ComputerNameParam
        }
        catch {
            $exceptionMessage = $Error[0].Exception.Message
            $fail = $true
        }

        $message = "<$Name $noun $Action <.>48> $($fail ? "FAIL" : "PASS")"
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($fail ? "Red" : "Green")
        # Write-Host+ -Iff $(!$Quiet.IsPresent)

        Write-Log -verb "$noun $Action" -Target $Id -Status ($fail ? "FAIL" : "PASS") -EntryType ($fail ? "Error" : "Information")

        if ($Throw -and ![string]::IsNullOrEmpty($exceptionMessage)) { throw $exceptionMessage }

        return

    }

}


function global:Confirm-Preflight {

    param(
        [switch]$Force
    )

    if ($global:PreflightPreference -ne "Continue" -and !$Force) {
        return
    }

    Invoke-Preflight -Action Check -Target Overwatch
    Invoke-Preflight -Action Check -Target OS
    Invoke-Preflight -Action Check -Target Platform
    Invoke-Preflight -Action Check -Target PlatformInstance

    return

}
Set-Alias -Name Check-Preflight -Value Confirm-Preflight -Scope Global

function global:Update-Preflight {

    param(
        [switch]$Force
    )

    if ($global:PreflightPreference -ne "Continue" -and !$Force) {
        return
    }

    Invoke-Preflight -Action Update -Target Overwatch
    Invoke-Preflight -Action Update -Target OS
    Invoke-Preflight -Action Update -Target Platform
    Invoke-Preflight -Action Update -Target PlatformInstance

    return

}