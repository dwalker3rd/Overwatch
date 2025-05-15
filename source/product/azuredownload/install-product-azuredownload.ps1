param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "AzureDownload"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "AzureDownload"
if (!$productTask) {
    Register-PlatformTask -Id "AzureDownload" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AzureDownload").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(60) -RepetitionInterval $(New-TimeSpan -Minutes 60) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "AzureDownload"
}