
if ($(Get-PlatformTask -Id "AzureADCache")) {
    Unregister-PlatformTask -Id "AzureADCache"
}

Register-PlatformTask -Id "AzureADCache" -execute $pwsh -Argument "$($global:Location.Scripts)\AzureADCache.ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(15) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest