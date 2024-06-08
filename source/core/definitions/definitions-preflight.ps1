$global:PreflightChecksCompleted = $true

function global:HasPreflight {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$true,Position=0)]
        [ValidateSet("Check","Update")]
        [string]$Action,

        [Parameter(Mandatory=$false,Position=1)]
        [ValidateSet("Overwatch","Cloud","OS","Platform","PlatformInstance")]
        [string[]]$Target = @("Overwatch","Cloud","OS","Platform","PlatformInstance"),

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName = $env:COMPUTERNAME

    )

    $hasPreflight = $false
    foreach ($_target in $Target) {

        switch ($_target) {
            "PlatformInstance" {
                $id = $global:Platform.Instance
            }
            default {
                $id = Invoke-Expression "`$global:$($_target).Id"
            }
        }

        $preflightPath = switch ($_target) {
            "Overwatch" {
                "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($_target.ToLower()).ps1"
            }
            default {
                "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($_target.ToLower())-$($id.ToLower()).ps1"
            }
        }

        $hasPreflight = $hasPreflight -or (Test-Path -Path ([FileObject]::new($preflightPath,$ComputerName).Path))
        if ($hasPreflight) { continue }
    }

    return $hasPreflight

}

function global:HasPreflightCheck {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$false,Position=0)]
        [ValidateSet("Overwatch","Cloud","OS","Platform","PlatformInstance")]
        [string[]]$Target = @("Overwatch","Cloud","OS","Platform","PlatformInstance"),

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName = $env:COMPUTERNAME

    )

    return HasPreflight -Action "Check" -Target $Target -ComputerName $ComputerName

}

function global:HasPreflightUpdate {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$false,Position=0)]
        [ValidateSet("Overwatch","Cloud","OS","Platform","PlatformInstance")]
        [string[]]$Target = @("Overwatch","Cloud","OS","Platform","PlatformInstance"),

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName = $env:COMPUTERNAME

    )

    return HasPreflight -Action "Update" -Target $Target -ComputerName $ComputerName

}

function global:Invoke-Preflight {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$true,Position=0)]
        [ValidateSet("Check","Update")]
        [string]$Action,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateSet("Overwatch","Cloud","OS","Platform","PlatformInstance")]
        [string]$Target,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName,

        [switch]$Quiet,
        [switch]$Throw

    )

    $noun = "Preflight"

    $id = $null
    $name = $null
    switch ($Target) {
        "PlatformInstance" {
            $id = $global:Platform.Instance
            $name = ![string]::IsNullOrEmpty($ComputerName) ? $ComputerName : $global:Platform.Instance
        }
        default {
            $id = Invoke-Expression "`$global:$($Target).Id"
            $name = Invoke-Expression "`$global:$($Target).Name"
        }
    }

    if ($null -eq $id) {
        return $false
    }

    $preflightPath = switch ($Target) {
        "Overwatch" {
            "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower()).ps1"
        }
        default {
            "$($global:Location.PreFlight)\preflight$($Action.ToLower())s-$($Target.ToLower())-$($id.ToLower()).ps1"
        }
    }

    $preflightPathExists = (Test-Path -Path ([FileObject]::new($preflightPath,$ComputerName)).Path)
    if ($preflightPathExists) {

        Write-Host+ -Iff $(!$Quiet.IsPresent)
        
        # $actionPresentParticiple = 
        #     switch ($Action) {
        #         "Update" { "Updating" }
        #         default { "$($Action)ing"}
        #     }
        # $message = "<$name $noun <.>48> $actionPresentParticiple"
        # Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -NoSeparator "$noun $Action", " [", "$name", "] ", (Format-Leader -Length 49 -Adjust (" $noun $Action [$name]  ").Length), " PENDING" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,DarkGray,DarkGray

        Write-Log -Action "$name $noun $actionPresentParticiple" -Target $id

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

        # $actionPastTense = 
        #     switch ($Action) {
        #         "Update" { "Updated" }
        #         default { "$($Action)ed"}
        #     }
        # $message = "<$name $noun <.>48> $($fail ? "FAIL" : $actionPastTense)" 
        # Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -NoSeparator "$noun $Action", " [", "$name", "] ", (Format-Leader -Length 49 -Adjust (" $noun $Action [$name]  ").Length), " $($fail ? "FAIL" : "PASS")" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,($fail ? "Red" : "Green")

        Write-Log -verb "$name $noun $Action" -Target $id -Status ($fail ? "FAIL" : "PASS") -EntryType ($fail ? "Error" : "Information")

        if ($Throw -and ![string]::IsNullOrEmpty($exceptionMessage)) { throw $exceptionMessage }

        return

    }

}

function global:Confirm-Preflight {

    param(
        [switch]$Force,
        [switch]$Quiet
    )

    if ($global:PreflightPreference -ne "Continue" -and !$Force) {
        return
    }

    Invoke-Preflight -Action Check -Target Overwatch -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Check -Target Cloud -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Check -Target OS -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Check -Target Platform -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Check -Target PlatformInstance -Quiet:$Quiet.IsPresent

    return

}
Set-Alias -Name Check-Preflight -Value Confirm-Preflight -Scope Global

function global:Update-Preflight {

    param(
        [switch]$Force,
        [switch]$Quiet
    )

    if ($global:PreflightPreference -ne "Continue" -and !$Force) {
        return
    }

    Invoke-Preflight -Action Update -Target Overwatch -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Update -Target Cloud -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Update -Target OS -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Update -Target Platform -Quiet:$Quiet.IsPresent
    Invoke-Preflight -Action Update -Target PlatformInstance -Quiet:$Quiet.IsPresent

    return

}