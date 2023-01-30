param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "Backup"
$Id = $product.Id 

$interaction = $false

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

#region PRODUCT-SPECIFIC INSTALLATION

    if ($global:Platform.Id -eq "TableauServer") {
        $backuparchivelocation = . tsm configuration get -k basefilepath.backuprestore
    }

    $backupSettings = "$PSScriptRoot\data\backupInstallSettings.ps1"
    if (Test-Path -Path $backupSettings) {
        . $backupSettings
    }

    $overwatchRoot = $PSScriptRoot -replace "\\install",""
    if (Get-Content -Path $overwatchRoot\definitions\definitions-product-backup.ps1 | Select-String "<backuparchivelocation>" -Quiet) {

        $interaction = $true

        Write-Host+; Write-Host+

        do {
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "    Backup Archive Location ", "$($backuparchivelocation ? "[$backuparchivelocation] " : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $backuparchivelocationResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $backuparchivelocation = ![string]::IsNullOrEmpty($backuparchivelocationResponse) ? $backuparchivelocationResponse : $backuparchivelocation
            if ([string]::IsNullOrEmpty($backuparchivelocation)) {
                Write-Host+ -NoTrace -NoTimestamp "NULL: Backup archive location is required" -ForegroundColor Red
                $backuparchivelocation = $null
            }
        } until ($backuparchivelocation)
        if (!(Test-Path -Path $backuparchivelocation)) {New-Item -ItemType Directory -Path $backuparchivelocation}

        $backupDefinitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-product-backup.ps1
        $backupDefinitionsFile = $backupDefinitionsFile -replace "<backuparchivelocation>", $backuparchivelocation
        $backupDefinitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-product-backup.ps1

        #region SAVE SETTINGS

            if (Test-Path $backupSettings) {Clear-Content -Path $backupSettings}
            '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $backupSettings
            "Param()" | Add-Content -Path $backupSettings
            "`$backuparchivelocation = `"$backuparchivelocation`"" | Add-Content -Path $backupSettings

        #endregion SAVE SETTINGS

    }

#endregion PRODUCT-SPECIFIC INSTALLATION

$productTask = Get-PlatformTask -Id "Backup"
if (!$productTask) {
    $at = get-date -date "6:00Z"
    Register-PlatformTask -Id "Backup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Backup").ps1" -WorkingDirectory $global:Location.Scripts `
        -Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 60) -RunLevel Highest -SyncAcrossTimeZones `
        -Subscription $subscription -Disable
    $productTask = Get-PlatformTask -Id "Backup"
}

if ($interaction) {
    Write-Host+
    $message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}
else {
    $message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
}

[console]::CursorVisible = $cursorVisible
