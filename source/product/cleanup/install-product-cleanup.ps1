param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "Cleanup"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "Cleanup"
if (!$productTask) {
    $at = get-date -date "5:45Z"
    Register-PlatformTask -Id "Cleanup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Cleanup").ps1" -WorkingDirectory $global:Location.Scripts `
        -Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "Cleanup"
}