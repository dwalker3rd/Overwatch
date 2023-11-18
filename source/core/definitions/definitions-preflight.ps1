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
        [string]$ComputerName
    )

    $noun = "Preflight"

    switch ($Target) {
        "PlatformInstance" {
            $Id = $global:Platform.Instance
            $Name = $global:Platform.Instance + (![string]::IsNullOrEmpty($ComputerName) ? " ($ComputerName)" : "")
        }
        default {
            $Id = Invoke-Expression "`$global:$($Target).Id"
            $Name = Invoke-Expression "`$global:$($Target).Name"
        }
    }
    
    if (Test-Path -Path "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower())-$($Id.ToLower()).ps1") {
        
        Write-Host+ 
        $message = "<$Name $noun $Action <.>48> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray 

        Write-Log -Action $noun $Action -Target $Id

        
        $fail = $false
        try{
            $command = "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower())-$($Id.ToLower()).ps1"
            $ComputerNameParam = ((Get-Command $command).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
            . $command @ComputerNameParam
        }
        catch {
            $fail = $true
        }

        $message = "<$Name $noun $Action <.>48> $($fail ? "FAIL" : "PASS")"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($fail ? "Red" : "Green")
        # Write-Host+

        Write-Log -verb "$noun $Action" -Target $Id -Status ($fail ? "FAIL" : "PASS") -EntryType ($fail ? "Error" : "Information")

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

    Invoke-Preflight -Action Update -Target OS
    Invoke-Preflight -Action Update -Target Platform
    Invoke-Preflight -Action Update -Target PlatformInstance

    return

}