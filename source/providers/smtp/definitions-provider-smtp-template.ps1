#region PROVIDER DEFINITIONS

param(
    [switch]$MinimumDefinitions
)

if ($MinimumDefinitions) {
    $root = $PSScriptRoot -replace "\\definitions",""
    Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
}
else {
    . $PSScriptRoot\classes.ps1
}

$Provider = $null
$Provider = $global:Catalog.Provider.SMTP

#region PREREQUISITES

    # test initialization prerequisites
    $prerequisiteTestResults = Test-Prerequisites -Type Provider -Id SMTP -PrerequisiteType Initialization -Quiet
    if (!$prerequisiteTestResults.Pass) {
        foreach ($package in $prerequisiteTestResults.Prerequisites.Tests.PowerShell.Packages) {
            if ($package.Status -ne "Installed") {
                throw $package.Reason
            }
        }
    }

    # add types to session
    foreach ($package in $prerequisiteTestResults.Prerequisites.Tests.PowerShell.Packages) {
        $dotNetDirectories = Get-Files -Path "C:\Program Files\PackageManagement\NuGet\Packages\$($package.Name).$($package.$($package.VersionToInstall))\lib" -Recurse -Depth 0
        $dotNetDirectoryName = (($dotNetDirectories | Where-Object {[regex]::IsMatch($_.Name,"net[\d\.]+")}).Name | Sort-Object -Descending)[0]
        try {
            Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\$($package.Name).$($package.$($package.VersionToInstall))\lib\$dotNetDirectoryName\$($package.Name).dll"
        }
        catch {
            Write-Log -Exception $_.Exception
            Write-Host+ -NoTrace -NoTimestamp $_.Exception.Message -ForegroundColor DarkRed
            Write-Host+ -NoTrace -NoTimestamp "The $($package.Name) class has been updated." -ForegroundColor DarkRed
            Write-Host+ -NoTrace -NoTimestamp "Exit the current PowerShell session and restart to load the updated class." -ForegroundColor DarkRed
        }
    }

#endregion PREREQUISITES

$SmtpConfig = 
    @{
        Server = "<server>"
        Port = "<port>"
        UseSsl = "<useSsl>"
        MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear,$PlatformMessageType.Intervention)
        From = $null # deferred to provider
        To = @()
        Throttle = New-TimeSpan -Minutes 15
    }

$Provider.Config = $SmtpConfig

return $Provider

#endregion PROVIDER DEFINITIONS
