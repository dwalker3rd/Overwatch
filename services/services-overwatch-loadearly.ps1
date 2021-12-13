    function global:Set-PSPreferenceVariables {

        [CmdletBinding()]
        param (
            [switch]$xi,
            [switch]$v,
            [switch]$d,
            [switch]$xw,
            [switch]$xprog,
            [switch]$xprefl,
            [switch]$xpostfl,
            [switch]$xwh,
            [switch]$q
        )
    
        
        $global:InformationPreference = $xi ? "SilentlyContinue" : "Continue"
        $global:VerbosePreference = $v ? "Continue" : "SilentlyContinue"
        $global:DebugPreference = $d ? "Continue" : "SilentlyContinue"
        $global:WarningPreference = $xw ? "SilentlyContinue" : "Continue"
        $global:ProgressPreference = $xprog ? "SilentlyContinue" : "Continue"
        $global:PreflightPreference =  $xprefl ? "SilentlyContinue" : "Continue"
        $global:PostFlightPreference =  $xpostfl ? "SilentlyContinue" : "Continue"
        $global:WriteHostPlusPreference =  $xwh ? "SilentlyContinue" : "Continue"
    
        if (!$q) {
            Write-Host+
            $message = "InformationPreference = |$global:InformationPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,$($global:InformationPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "VerbosePreference = |$global:VerbosePreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:VerbosePreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "DebugPreference = |$global:DebugPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,$($global:DebugPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "WarningPreference = |$global:WarningPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:WarningPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "ProgressPreference = |$global:ProgressPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:ProgressPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "PreflightPreference = |$global:PreflightPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:PreflightPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "PostFlightPreference = |$global:PostFlightPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:PostFlightPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            $message = "WriteHostPlusPreference = |$global:WriteHostPlusPreference"
            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:WriteHostPlusPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
            Write-Host+
        }
    
    }
    Set-Alias -Name psPref -Value Set-PSPreferenceVariables -Scope Global

    function global:Write-Dots {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][int32]$Length,
            [Parameter(Mandatory=$false,Position=1)][int32]$Adjust=0,
            [Parameter(Mandatory=$false,Position=2)][char]$Character="."
        )

        $dots = ""
        for ($i = 0; $i -lt $Length+$Adjust; $i++) {
            $dots += $Character
        }
        return $dots

    }

    function global:Write-Host+ {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][object[]]$Object="",
            [Parameter(Mandatory=$false)][object]$Separator=" ",
            [Parameter(Mandatory=$false)][System.ConsoleColor[]]$ForegroundColor,
            [Parameter(Mandatory=$false)][System.ConsoleColor[]]$DefaultForegroundColor=@("DarkGray","Gray"),
            [Parameter(Mandatory=$false)][string]$Prefix,
            [Parameter(Mandatory=$false)][bool]$Iff=$true,
            [switch]$NoTimestamp,
            [switch]$NoTrace,
            [switch]$NoNewLine,
            [switch]$NoSeparator,
            [switch]$Clear,
            [switch]$IfVerbose,
            [switch]$IfDebug,
            [switch]$IfInformation
        )

        if ($global:WriteHostPlusPreference -and $global:WriteHostPlusPreference -ne "Continue") {return}
        if (!$Iff) {return}

        if ($IfVerbose -and !$VerbosePreference) {return}
        if ($IfDebug -and !$DebugPreference) {return}
        if ($IfInformation -and !$InformationPreference) {return}

        if ($Clear) {
            Clear-Host
            return
        }

        $callStack = Get-PSCallStack
        $caller = $callstack[1] ? ($callstack[1].FunctionName -eq "<ScriptBlock>" ? "" : "$($callstack[1].FunctionName.replace('global:','')): ") : ""

        if ($Object -ne "") {
            Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($Prefix ? $Prefix : "")
            Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($NoTimestamp ? "" : "[$([datetime]::Now.ToString('u'))] ")
            Write-Host -NoNewLine -ForegroundColor $DefaultForeGroundColor[0] ($NoTrace ? "" : "$($caller)")
        }

        $i = 0
        foreach ($obj in $Object) {
            $foregroundColor_ = $ForegroundColor ? ($i -lt $ForegroundColor.Length-1 ? $ForegroundColor[$i] : $ForegroundColor[$ForegroundColor.Length-1]) : $DefaultForegroundColor[1]
            Write-Host -NoNewLine -ForegroundColor $foregroundColor_ $obj
            if ($i -lt $Object.Length-1) {
                if (!$NoSeparator) {
                    Write-Host  -NoNewLine -ForegroundColor $foregroundColor_ $Separator
                }
            }
            $i++
        }

        if (!$NoNewLine) {
            Write-Host ""
        }

        return
    }