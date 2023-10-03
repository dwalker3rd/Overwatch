param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "SSOMonitor"
$Id = $product.Id 

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

$productTask = Get-PlatformTask -Id "SSOMonitor"
if (!$productTask) {
    $subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='eventlog' or @Name='Microsoft-Windows-Eventlog' or @Name='User32'] and (EventID=6005)]]</Select></Query></QueryList>"  
    Register-PlatformTask -Id "SSOMonitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("SSOMonitor").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddSeconds(5) `
        -Subscription $subscription `
        -ExecutionTimeLimit $(New-TimeSpan -Seconds 0) -RunLevel Highest -Start
    $productTask = Get-PlatformTask -Id "SSOMonitor"
}

$message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
