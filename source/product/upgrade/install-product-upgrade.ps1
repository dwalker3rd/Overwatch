param (
    [switch]$UseDefaultResponses
)

$at = [datetime]::today.AddHours(3)

$productTask = Get-PlatformTask "Upgrade"
if (!$productTask) { 
    Register-PlatformTask -Id "Upgrade" -execute $pwsh -Argument "$($global:Location.Scripts)\upgrade.ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 240) -RunLevel Highest
    $productTask = Get-PlatformTask "Upgrade"
}