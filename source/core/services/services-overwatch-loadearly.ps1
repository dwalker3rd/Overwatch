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

function ConvertTo-PSCommand {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$false)][AllowNull()][string]$Arguments
    )

    if ($Command.EndsWith(".ps1")) { $Command = "./" + $Command }

    $psCommandString = "$Command"
    if ($Arguments) { $psCommandString += " " }
    foreach ($argument in $Arguments.replace("{","").replace("}","").replace(", ",",").split(",")) {
        if ([string]::IsNullOrEmpty($argument)) { continue }
        $keyValuePair = $argument.split("=")
        $key = $keyValuePair[0]
        $value = ![string]::IsNullOrEmpty($keyValuePair[1]) ? " `"$($keyValuePair[1])`"" : ":`$false"
        $psCommandString += "-$key$value "
    }

    return $psCommandString

}

function global:Write-Host+ {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

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
        [Parameter(Mandatory=$false)][ValidateSet("NoArguments","NoCommand","NoScriptName","NoLineNumber")][string[]]$TraceFormat,
        [switch]$NoNewLine,
        [switch]$NoSeparator,
        [switch]$Clear,
        [switch]$IfVerbose,
        [switch]$IfDebug,
        [switch]$IfInformation,
        [Parameter(Mandatory=$false)][string]$SetIndentGlobal,
        [switch]$ResetIndentGlobal,
        [switch]$NoIndent,
        [switch]$ResetMaxBlankLines,
        [switch]$ResetAll,
        [switch]$Parse,
        [Parameter(Mandatory=$false)][ValidateSet("Ignore","Include","Exclude")][string]$SetTimestampGlobal,
        [switch]$ResetTimestampGlobal,
        [Parameter(Mandatory=$false)][ValidateSet("Ignore","Include","Exclude")][string]$SetTraceGlobal,
        [switch]$ResetTraceGlobal
    )

    $global:WriteHostPlusEndOfLine = $NoNewLine

    if ($ResetAll) {
        $global:WriteHostPlusBlankLineCount = 0
        $global:WriteHostPlusIndentGlobal = 0
        $global:WriteHostPlusTimestampGlobal = "Ignore"
        $global:WriteHostPlusTraceGlobal = "Ignore"
        return
    }

    $returnAfterSettings = $false
    if ($ResetMaxBlankLines) { $global:WriteHostPlusBlankLineCount = 0; $returnAfterSettings = $true }
    if ($global:WriteHostPlusPreference -and $global:WriteHostPlusPreference -ne "Continue") { $returnAfterSettings = $true }
    if ($IfVerbose -and !$VerbosePreference) { $returnAfterSettings = $true }
    if ($IfDebug -and !$DebugPreference) { $returnAfterSettings = $true }
    if ($IfInformation -and !$InformationPreference) { $returnAfterSettings = $true }
    if ($ResetIndentGlobal) { $global:WriteHostPlusIndentGlobal = 0; $returnAfterSettings = $true }
    if ($SetIndentGlobal) { 
        if ($SetIndentGlobal -match $global:RegexPattern.SignedInteger) {
            if ($null -eq $matches.sign) {
                $global:WriteHostPlusIndentGlobal = [int]$SetIndentGlobal
            }
            else {
                $global:WriteHostPlusIndentGlobal += [int]$SetIndentGlobal
            }
            $returnAfterSettings = $true
        }
    }
    if ($ResetTimestampGlobal) { $global:WriteHostPlusTimestampGlobal = "Ignore"; $returnAfterSettings = $true }
    if ($SetTimestampGlobal) { $global:WriteHostPlusTimestampGlobal = $SetTimestampGlobal; $returnAfterSettings = $true }
    if ($ResetTraceGlobal) { $global:WriteHostPlusTraceGlobal = "Ignore"; $returnAfterSettings = $true }
    if ($SetTraceGlobal) { $global:WriteHostPlusTraceGlobal = $SetTraceGlobal; $returnAfterSettings = $true }
    if ($returnAfterSettings) { return }

    if (!$Iff) {return}

    if ($global:WriteHostPlusTimestampGlobal) { 
        switch ($global:WriteHostPlusTimestampGlobal) {
            "Include" { $NoTimestamp = $false }
            "Exclude" { $NoTimestamp = $true }
        }
    }

    if ($global:WriteHostPlusTraceGlobal) { 
        switch ($global:WriteHostPlusTraceGlobal) {
            "Include" { $NoTrace = $false }
            "Exclude" { $NoTrace = $true }
        }
    }

    if ($Parse -and $NoSeparator) {
        throw "The `"NoSeparator`" switch cannot be used with the `"Parse`" switch"
    }

    if ($NoIndent) {$Indent = 0}
    if (!$global:WriteHostPlusEndOfLine) {$Indent = 0}

    # i don't know why, but ...
    # the extra Write-Host is necessary when using ReverseLineFeed to return to the first line
    if ($Clear) { Clear-Host; Write-Host }

    if ($ReverseLineFeed -gt 0) { 
        Write-Host -NoNewline "`e[$($ReverseLineFeed)F" 
    }

    if ([string]::IsNullOrEmpty($Object)) {
        if ($MaxBlankLines -and $MaxBlankLines -le $global:WriteHostPlusBlankLineCount) {
            if ($MaxBlankLines -lt $global:WriteHostPlusBlankLineCount) {
                Write-Host "`e[$($global:WriteHostPlusBlankLineCount - $MaxBlankLines)F" 
                $global:WriteHostPlusBlankLineCount = 0
            }
            elseif ($MaxBlankLines -eq $global:WriteHostPlusBlankLineCount) {
                # do nothing
            }
        }
        else {
            Write-Host ""
            $global:WriteHostPlusBlankLineCount++
        }
        return
    }
    else {
        $global:WriteHostPlusBlankLineCount = 0
    }

    if (!$NoTrace) {

        $traceCommand = $TraceFormat -notcontains "NoCommand"
        $traceArguments = $TraceFormat -notcontains "NoArguments" -and $TraceFormat -notcontains "NoArgs"
        $traceScriptName = $TraceFormat -notcontains "NoScriptName"
        $traceScriptLineNumber = $TraceFormat -notcontains "NoScriptLineNumber"

        $callStack = Get-PSCallStack
        $callStackMaxDepth = 5 # TODO: convert to a definition
        $callStackStart = [math]::Min($callStack.Count-2,$callStackMaxDepth)
        $leadingSpaces = 0
        if ($Object[0] -match "^(\s*)") {
            $leadingSpaces = $matches[1].Length
        }
        $callStackPrefix = "$($emptyString.PadLeft($Indent+$leadingSpaces," "))$($callStack.Count - 2 -gt $callStackMaxDepth ? "... > " : $null)"
        for ($i = $callstackStart; $i -ge 1; $i--) { # decrement to display trace in the order that the calls occurred
            if ($traceCommand) {
                $psCommandString = ConvertTo-PSCommand -Command $callstack[$i].Command -Arguments ($traceArguments ? $callStack[$i].Arguments : $null)
            }
            $callStackScriptName = $traceScriptName ? $callstack[$i].ScriptName : $null
            $callStackScriptLineNumber = $traceScriptLineNumber ? $callStack[$i].ScriptLineNumber : $null
            Write-Host "[$([datetime]::Now.ToString('u'))] $callStackPrefix$($callStackScriptName): $(![string]::IsNullOrEmpty($callStackScriptLineNumber) ? "line: " : $null)$($callStackScriptLineNumber), $psCommandString " -ForegroundColor DarkGray
        }
        $NoTrace = $true
    }

    if ($Object -ne "") {
        Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($NoTimestamp ? "" : "[$([datetime]::Now.ToString('u'))] ")
        Write-Host -NoNewLine -ForegroundColor $DefaultForeGroundColor[0] ($NoTrace ? "" : "$($caller)")
        Write-Host -NoNewLine -ForegroundColor $DefaultForegroundColor[0] ($Indent ? $emptyString.PadLeft($Indent," ") : "")
        If (![string]::IsNullOrEmpty($Prefix)) {
            $_foregroundColor = $ForegroundColor ? $ForegroundColor[0] : $DefaultForegroundColor[0]
            Write-Host -NoNewLine -ForegroundColor $_foregroundColor ($Prefix ? $Prefix : "")
        }

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
                Write-Error "Invalid format for object parser." -ForegroundColor DarkRed
                return
            }
        }

    }

    $i = 0
    foreach ($obj in $Object) {
        $_foregroundColor = $ForegroundColor ? ($i -lt $ForegroundColor.Length-1 ? $ForegroundColor[$i] : $ForegroundColor[$ForegroundColor.Length-1]) : $DefaultForegroundColor[1]
        Write-Host -NoNewLine -ForegroundColor $_foregroundColor $obj
        if ($i -lt $Object.Length-1) {
            if (!$NoSeparator) {
                Write-Host  -NoNewLine -ForegroundColor $_foregroundColor $Separator
            }
        }
        $i++
    }

    if (!$NoNewLine) {
        Write-Host ""
    }

    # $global:WriteHostPlusEndOfLine = !$NoNewLine

    return
}