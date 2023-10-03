param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "DiskCheck"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "DiskCheck"
if (!$productTask) {
    Register-PlatformTask -Id "DiskCheck" -execute $pwsh -Argument "$($global:Location.Scripts)\$("DiskCheck").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(60) -RepetitionInterval $(New-TimeSpan -Minutes 60) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "DiskCheck"
}
