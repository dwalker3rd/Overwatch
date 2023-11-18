function global:Invoke-Postflight {

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

    $noun = "Postflight"

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
    
    if (Test-Path -Path "$($global:Location.PostFligh)\postflight$($Action.ToLower())s-$($Target.ToLower())-$($Id.ToLower()).ps1") {
        
        Write-Host+ 
        $message = "<$Name $noun $Action <.>48> PENDING"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray 

        Write-Log -Action $noun $Action -Target $Id
        
        $fail = $false
        try{
            $command = "$($global:Location.PostFlight)\postflight$($Action.ToLower())s-$($Target.ToLower())-$($Id.ToLower()).ps1"
            $ComputerNameParam = ((Get-Command $command).Parameters.Keys -contains "ComputerName") ? @{ ComputerName = $ComputerName } : @{}
            . $command @ComputerNameParam
        }
        catch {
            $fail = $true
        }

        $message = "<$Name $noun $Action <.>48> $($fail ? "FAIL" : "PASS")"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($fail ? "Red" : "Green")

        Write-Log -verb "$noun $Action" -Target $Id -Status ($fail ? "FAIL" : "PASS") -EntryType ($fail ? "Error" : "Information")

        return

    }

}


function global:Confirm-Postflight {

    param(
        [switch]$Force
    )

    if ($global:PostflightPreference -ne "Continue" -and !$Force -and $global:PreflightChecksCompleted) {
        return
    }

    Invoke-Postflight -Action Check -Target OS
    Invoke-Postflight -Action Check -Target Platform
    Invoke-Postflight -Action Check -Target PlatformInstance

    return

}
Set-Alias -Name Check-Postflight -Value Confirm-Postflight -Scope Global

function global:Update-Postflight {

    param(
        [switch]$Force
    )

    if ($global:PostflightPreference -ne "Continue" -and !$Force -and $global:PreflightChecksCompleted) {
        return
    }

    Invoke-Postflight -Action Update -Target OS
    Invoke-Postflight -Action Update -Target Platform
    Invoke-Postflight -Action Update -Target PlatformInstance

    return

}