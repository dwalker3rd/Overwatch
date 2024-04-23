function global:HasPostflight {

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

    $hasPostflight = $false
    foreach ($_target in $Target) {

        switch ($_target) {
            "PlatformInstance" {
                $id = $global:Platform.Instance
            }
            default {
                $id = Invoke-Expression "`$global:$($_target).Id"
            }
        }

        $postflightPath = switch ($_target) {
            "Overwatch" {
                "$($global:Location.Postflight)\postflight$($Action.ToLower())s-$($_target.ToLower()).ps1"
            }
            default {
                "$($global:Location.Postflight)\postflight$($Action.ToLower())s-$($_target.ToLower())-$($id.ToLower()).ps1"
            }
        }

        $hasPostflight = $hasPostflight -or (Test-Path -Path ([FileObject]::new($postflightPath,$ComputerName).Path))
        if ($hasPostflight) { continue }
    }

    return $hasPostflight

}

function global:HasPostflightCheck {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$false,Position=0)]
        [ValidateSet("Overwatch","Cloud","OS","Platform","PlatformInstance")]
        [string[]]$Target = @("Overwatch","Cloud","OS","Platform","PlatformInstance"),

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName = $env:COMPUTERNAME

    )

    return HasPostflight -Action "Check" -Target $Target -ComputerName $ComputerName

}

function global:HasPostflightUpdate {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory=$false,Position=0)]
        [ValidateSet("Overwatch","Cloud","OS","Platform","PlatformInstance")]
        [string[]]$Target = @("Overwatch","Cloud","OS","Platform","PlatformInstance"),

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$ComputerName = $env:COMPUTERNAME

    )

    return HasPostflight -Action "Update" -Target $Target -ComputerName $ComputerName

}

function global:Invoke-Postflight {

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

    $noun = "Postflight"

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

    $postflightPath = switch ($Target) {
        "Overwatch" {
            "$($global:Location.Postflight)\postflight$($Action.ToLower())s-$($Target.ToLower()).ps1"
        }
        default {
            "$($global:Location.Postflight)\postflight$($Action.ToLower())s-$($Target.ToLower())-$($id.ToLower()).ps1"
        }
    }

    $postflightPathExists = (Test-Path -Path ([FileObject]::new($postflightPath,$ComputerName)).Path)
    if ($postflightPathExists) {
        
        # $actionPresentParticiple = 
        # switch ($Action) {
        #     "Update" { "Updating" }
        #     default { "$($Action)ing"}
        # }
        # $message = "< $name $noun <.>48> $actionPresentParticiple"
        # Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -NoSeparator " $noun $Action", " [", "$name", "] ", (Format-Leader -Length 48 -Adjust (" $noun $Action [$name]  ").Length), " PENDING" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,DarkGray,DarkGray

        Write-Log -Action $noun $Action -Target $id
        
        $fail = $false
        $exceptionMessage = $null
        try{
            $command = $postflightPath
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
        Write-Host+ -Iff $(!$Quiet.IsPresent) -NoTrace -NoSeparator " $noun $Action", " [", "$name", "] ", (Format-Leader -Length 48 -Adjust (" $noun $Action [$name]  ").Length), " $($fail ? "FAIL" : "PASS")" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,($fail ? "Red" : "Green")

        Write-Log -verb "$noun $Action" -Target $id -Status ($fail ? "FAIL" : "PASS") -EntryType ($fail ? "Error" : "Information")

        if ($Throw -and ![string]::IsNullOrEmpty($exceptionMessage)) { throw $exceptionMessage }

        return

    }

}


function global:Confirm-Postflight {

    param(
        [switch]$Force,
        [switch]$Quiet
    )

    if ($global:PostflightPreference -ne "Continue" -and !$Force -and $global:PreflightChecksCompleted) {
        return
    }

    Invoke-Postflight -Action Check -Target Overwatch -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Check -Target Cloud -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Check -Target OS -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Check -Target Platform -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Check -Target PlatformInstance -Quiet:$Quiet.IsPresent

    return

}
Set-Alias -Name Check-Postflight -Value Confirm-Postflight -Scope Global

function global:Update-Postflight {

    param(
        [switch]$Force,
        [switch]$Quiet
    )

    if ($global:PostflightPreference -ne "Continue" -and !$Force -and $global:PreflightChecksCompleted) {
        return
    }

    Invoke-Postflight -Action Update -Target Overwatch -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Update -Target Cloud -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Update -Target OS -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Update -Target Platform -Quiet:$Quiet.IsPresent
    Invoke-Postflight -Action Update -Target PlatformInstance -Quiet:$Quiet.IsPresent

    return

}