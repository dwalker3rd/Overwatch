
param (
    [switch]$UseDefaultResponses
)

$Provider = Get-Provider -Id 'SMTP'
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

    $interaction = $false

    $smtpSettings = "$PSScriptRoot\data\smtpInstallSettings.ps1"
    if (Test-Path -Path $smtpSettings) {
        . $smtpSettings
    }

    $overwatchRoot = $PSScriptRoot -replace "\\install",""
    if (Get-Content -Path $overwatchRoot\definitions\definitions-provider-smtp.ps1 | Select-String "<server>" -Quiet) {

        $interaction = $true

        if (!$global:WriteHostPlusEndOfLine) { Write-Host+ } # close any pending newline

        Write-Host+

        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "  Server ", "$($server ? "[$server] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $serverResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $server = ![string]::IsNullOrEmpty($serverResponse) ? $serverResponse : $server
            if ([string]::IsNullOrEmpty($server)) {
                Write-Host+ -NoTrace -NoTimestamp "  NULL: SMTP server is required" -ForegroundColor Red
                $server = $null
            }
        } until ($server)
        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "  Port ", "$($port ? "[$port] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $portResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $port = ![string]::IsNullOrEmpty($portResponse) ? $portResponse : $port
            if ([string]::IsNullOrEmpty($port)) {
                Write-Host+ -NoTrace -NoTimestamp "  NULL: SMTP port is required" -ForegroundColor Red
                $port = $null
            }
        } until ($port)
        $useSslDefault = "Y"
        $useSslChar = $useSsl ? "Y" : "N"
        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "  Use SSL? (Y/N) ", "$($useSslChar ? "[$useSslChar] " : $useSslDefault)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $useSslResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $useSslChar = ![string]::IsNullOrEmpty($useSslResponse) ? $useSslResponse : $useSslChar
            if ([string]::IsNullOrEmpty($useSslChar)) {
                $useSslChar = $useSslDefault
            }
            if ($useSslChar -notmatch "^(Y|N)$") {
                Write-Host+ -NoTrace -NoTimestamp "  INVALID: Response must be `"Y`" or `"N`"" -ForegroundColor Red
                $useSslChar = $null
            }
        } until ($useSslChar -match "^(Y|N)$")
        $useSsl = $useSslChar -eq "Y" ? "`$true" : "`$false"

        $smtpDefinitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-provider-smtp.ps1
        $smtpDefinitionsFile = $smtpDefinitionsFile -replace "<server>", $server
        $smtpDefinitionsFile = $smtpDefinitionsFile -replace "<port>", $port
        $smtpDefinitionsFile = $smtpDefinitionsFile -replace '"<useSsl>"', $useSsl
        $smtpDefinitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-provider-smtp.ps1

        #region SAVE SETTINGS

            if (Test-Path $smtpSettings) {Clear-Content -Path $smtpSettings}
            '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $smtpSettings
            "Param()" | Add-Content -Path $smtpSettings
            "`$server = `"$server`"" | Add-Content -Path $smtpSettings
            "`$port = `"$port`"" | Add-Content -Path $smtpSettings
            "`$useSSL = $useSSL" | Add-Content -Path $smtpSettings

        #endregion SAVE SETTINGS

    }

    if (!$(Test-Credentials $Provider.Id -NoValidate)) {
        if (!$global:WriteHostPlusEndOfLine) { Write-Host+ } # close any pending newline
        Write-Host+
        $interaction = $true
        Request-Credentials -Title "  SMTP Account Credentials" -Prompt1 "  Account" -Prompt2 "  Password" | Set-Credentials $Provider.Id
    }

    if ($interaction) {
        Write-Host+
    }
    
    return

#endregion PROVIDER-SPECIFIC INSTALLATION