
if ($(Get-PlatformTask -Id "AzureADSync")) {
    Unregister-PlatformTask -Id "AzureADSync"
}

Register-PlatformTask -Id "AzureADSync" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AzureADSync").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest