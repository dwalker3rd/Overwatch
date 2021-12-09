# $global:Product = @{Id = "DiskCheck"}
# . $PSScriptRoot\definitions.ps1

# New-Log -Name "DiskCheck"

if ($(Get-PlatformTask -Id "DiskCheck")) {
    Unregister-PlatformTask -Id "DiskCheck"
}

Register-PlatformTask -Id "DiskCheck" -execute $pwsh -Argument "$($global:Location.Scripts)\$("DiskCheck").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(60) -RepetitionInterval $(New-TimeSpan -Minutes 60) -RepetitionDuration ([timespan]::MaxValue) `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest