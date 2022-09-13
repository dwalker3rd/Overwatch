function global:Set-PSPreferenceVariables {

    [CmdletBinding()]
    param (
        [switch]$xi,
        [switch]$v,
        [switch]$d,
        [switch]$xw,
        [switch]$p,
        [switch]$xpref,
        [switch]$xpostf,
        [switch]$xwhp,
        [Parameter(Mandatory=$false)][Alias("q")][switch]$Quiet
    )

    
    $global:InformationPreference = $xi ? "SilentlyContinue" : "Continue"
    $global:VerbosePreference = $v ? "Continue" : "SilentlyContinue"
    $global:DebugPreference = $d ? "Continue" : "SilentlyContinue"
    $global:WarningPreference = $xw ? "SilentlyContinue" : "Continue"
    $global:ProgressPreference = $p ? "Continue" : "SilentlyContinue"
    $global:PreflightPreference =  $xpref ? "SilentlyContinue" : "Continue"
    $global:PostflightPreference =  $xpostf ? "SilentlyContinue" : "Continue"
    $global:WriteHostPlusPreference =  $xwhp ? "SilentlyContinue" : "Continue"

    Write-Host+ -Iff $(!$Quiet)
    $message = "InformationPreference = |$global:InformationPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,$($global:InformationPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "VerbosePreference = |$global:VerbosePreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:VerbosePreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "DebugPreference = |$global:DebugPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,$($global:DebugPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "WarningPreference = |$global:WarningPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:WarningPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "ProgressPreference = |$global:ProgressPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:ProgressPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "PreflightPreference = |$global:PreflightPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:PreflightPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "PostflightPreference = |$global:PostflightPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:PreflightPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    $message = "WriteHostPlusPreference = |$global:WriteHostPlusPreference"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimeStamp -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor Gray,($global:PreflightPreference -eq "SilentlyContinue" ? "DarkGray" : "DarkYellow") -Prefix "PSPREF: "
    Write-Host+ -Iff $(!$Quiet)

}
Set-Alias -Name psPref -Value Set-PSPreferenceVariables -Scope Global

function global:Format-Leader {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][int32]$Length,
        [Parameter(Mandatory=$false,Position=1)][int32]$Adjust=0,
        [Parameter(Mandatory=$false,Position=2)][char]$Character=".",
        [switch]$NoIndent
    )

    if ($global:WriteHostPlusEndOfLine -and !$NoIndent) {
        $Length -= $global:WriteHostPlusIndentGlobal
    }

    $leaderCount = $Length - $Adjust

    $leader = ""
    for ($i = 0; $i -lt $leaderCount; $i++) {
        $leader += $Character
    }
    return $leader

}

function global:Write-Host+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][object[]]$Object="",
        [Parameter(Mandatory=$false)][int]$Indent = $global:WriteHostPlusIndentGlobal,
        [Parameter(Mandatory=$false)][object]$Separator = " ",
        [Parameter(Mandatory=$false)][System.ConsoleColor[]]$ForegroundColor,
        [Parameter(Mandatory=$false)][System.ConsoleColor[]]$DefaultForegroundColor = @("DarkGray","Gray"),
        [Parameter(Mandatory=$false)][string]$Prefix,
        [Parameter(Mandatory=$false)][bool]$Iff = $true,
        [Parameter(Mandatory=$false)][int]$MaxBlankLines,
        [Parameter(Mandatory=$false)][int]$ReverseLineFeed,
        [switch]$NoTimestamp,
        [switch]$NoTrace,
        [switch]$NoNewLine,
        [switch]$NoSeparator,
        [switch]$Clear,
        [switch]$IfVerbose,
        [switch]$IfDebug,
        [switch]$IfInformation,
        [switch]$SetIndentGlobal,
        [switch]$ResetIndentGlobal,
        [switch]$NoIndent,
        [switch]$ResetMaxBlankLines,
        [switch]$ResetAll,
        [switch]$Parse

    )

    if ($ResetAll) {
        $global:WriteHostPlusBlankLineCount = 0
        $global:WriteHostPlusIndentGlobal = 0
        return
    }

    if ($ResetMaxBlankLines) { $global:WriteHostPlusBlankLineCount = 0; return }
    if ($global:WriteHostPlusPreference -and $global:WriteHostPlusPreference -ne "Continue") {return}
    if (!$Iff) {return}
    if ($IfVerbose -and !$VerbosePreference) {return}
    if ($IfDebug -and !$DebugPreference) {return}
    if ($IfInformation -and !$InformationPreference) {return}
    if ($Clear) { Clear-Host; return }
    if ($ResetIndentGlobal) { $global:WriteHostPlusIndentGlobal = 0; return }
    if ($SetIndentGlobal) { $global:WriteHostPlusIndentGlobal += $Indent; return }

    if ($Parse -and $NoSeparator) {
        throw "The `"NoSeparator`" switch cannot be used with the `"Parse`" switch"
    }


    if ($NoIndent -or !$global:WriteHostPlusEndOfLine) {$Indent = 0}

    if ([string]::IsNullOrEmpty($Object)) {
        if ($MaxBlankLines -and $MaxBlankLines -le $global:WriteHostPlusBlankLineCount) { return }
        Write-Host ""
        $global:WriteHostPlusBlankLineCount++
        return
    }
    else {
        $global:WriteHostPlusBlankLineCount = 0
    }

    $callStack = Get-PSCallStack
    $caller = $callstack[1] ? ($callstack[1].FunctionName -eq "<ScriptBlock>" ? "" : "$($callstack[1].FunctionName.replace('global:','')): ") : ""

    if ($Object -ne "") {
        Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($Prefix ? $Prefix : "")
        Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($NoTimestamp ? "" : "[$([datetime]::Now.ToString('u'))] ")
        Write-Host -NoNewLine -ForegroundColor $DefaultForeGroundColor[0] ($NoTrace ? "" : "$($caller)")
        Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($Indent ? $emptyString.PadLeft($Indent," ") : "")

        #+++
        # Object Parser
        #
        #   Currently, only parses object for split messages with leader (see example below)
        #   Format (regex): "^<(.*?)\s<(.)>(\d*)>\s(.*)$" (See $global:RegexPattern.WriteHostPlus.Parse)
        #   Example: Write-Host+ -NoTrace -NoTimestamp -Parse "<Download <.>20> PENDING"
        #   Output : "Download .......... PENDING"

        if ($Parse -and $Object.Count -eq 1) {
            if ($Object[0] -match $global:RegexPattern.WriteHostPlus.Parse) {
                $Object = @($matches[1], (Format-Leader -Character $matches[2] -Length $matches[3] -Adjust ($matches[1].Length+2)), $matches[4])
            }
            else {
                Write-Error "Invalid format for object parser."
                return
            }
        }

    }

    for ($i = 0; $i -lt $ReverseLineFeed; $i++) {
        Write-Host -NoNewline "`eM"
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

    $global:WriteHostPlusEndOfLine = !$NoNewLine

    return
}