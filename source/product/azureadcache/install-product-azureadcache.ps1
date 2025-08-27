param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "AzureADCache"
$_product | Out-Null

foreach ($node in (pt nodes -k)) {
    $remotedirectory = "\\$node\$(($global:Azure.Location.Data).Replace(":","$"))"
    if (!(Test-Path $remotedirectory)) { 
        New-Item -ItemType Directory -Path $remotedirectory -Force | Out-Null
    }
}

$productTask = Get-PlatformTask -Id "AzureADCache"
if (!$productTask) {
    Register-PlatformTask -Id "AzureADCache" -execute $pwsh -Argument "$($global:Location.Scripts)\AzureADCache.ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(15) -RepetitionInterval $(New-TimeSpan -Minutes 15) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "AzureADCache"
}