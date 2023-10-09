param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "SSOMonitor"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "SSOMonitor"
if (!$productTask) {
    Register-PlatformTask -Id "SSOMonitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("SSOMonitor").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddSeconds(5) `
        -ExecutionTimeLimit $(New-TimeSpan -Seconds 0) -RunLevel Highest -Start
    $productTask = Get-PlatformTask -Id "SSOMonitor"
}