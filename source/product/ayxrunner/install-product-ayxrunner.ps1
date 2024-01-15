param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "AyxRunner"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "AyxRunner"
if (!$productTask) {
    Register-PlatformTask -Id "AyxRunner" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AyxRunner").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 5) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest `
        -Subscription $subscription -Disable
    $productTask = Get-PlatformTask -Id "AyxRunner"
}