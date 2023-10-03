param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "StartRMTAgents"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "StartRMTAgents"
if (!$productTask) {
    Register-PlatformTask -Id "StartRMTAgents" -execute $pwsh -Argument "$($global:Location.Scripts)\$("StartRMTAgents").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(60) -ExecutionTimeLimit $(New-TimeSpan -Minutes 120) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "StartRMTAgents"
}