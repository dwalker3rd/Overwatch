param (
    [switch]$UseDefaultResponses
)

$_product = Get-Product "SSOMonitor"
$_product | Out-Null

$productTask = Get-PlatformTask -Id "SSOMonitor"
if (!$productTask) {
    $subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='eventlog' or @Name='Microsoft-Windows-Eventlog' or @Name='User32'] and (EventID=6005)]]</Select></Query></QueryList>"  
    Register-PlatformTask -Id "SSOMonitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("SSOMonitor").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddSeconds(5) `
        -Subscription $subscription `
        -ExecutionTimeLimit $(New-TimeSpan -Seconds 0) -RunLevel Highest -Start
    $productTask = Get-PlatformTask -Id "SSOMonitor"
}