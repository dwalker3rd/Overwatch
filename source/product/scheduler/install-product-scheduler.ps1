param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "Scheduler"
$_product | Out-Null

$productTask = Get-PlatformTask "Scheduler"
if (!$productTask) {
    $subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='eventlog' or @Name='Microsoft-Windows-Eventlog' or @Name='User32'] and (EventID=1074 or EventID=1075 or EventID=6006)]]</Select></Query></QueryList>"        
    Register-PlatformTask -Id "Scheduler" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Scheduler").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 5) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest `
        -Subscription $subscription -Disable
    $productTask = Get-PlatformTask "Scheduler"
}