param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "MailMerge"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "MailMerge"
# if (!$productTask) {
#     Register-PlatformTask -Id "MailMerge" -execute $pwsh -Argument "$($global:Location.Scripts)\$("MailMerge").ps1" -WorkingDirectory $global:Location.Scripts `
#         -Once -At $(Get-Date).AddMinutes(60) -RepetitionInterval $(New-TimeSpan -Minutes 60) `
#         -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
#     $productTask = Get-PlatformTask -Id "MailMerge"
# }