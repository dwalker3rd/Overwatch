$global:PreflightChecksCompleted = $true

function global:Invoke-Preflight {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$true,Position=0)]
        [ValidateSet("Check","Update")]
        [string]$Action,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateSet("OS","Platform","PlatformInstance")]
        [string]$Target
    )

    $noun = "Preflight"

    switch ($Target) {
        "PlatformInstance" {
            $Id = $global:Platform.Instance
            $Name = $global:Platform.Instance
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
            . "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower())-$($Id.ToLower()).ps1"    
        }
        catch {
            $fail = $true
        }

        $message = "<$Name $noun $Action <.>48> $($fail ? "FAIL" : "PASS")"
        Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($fail ? "Red" : "Green")
        Write-Host+

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