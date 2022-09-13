param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "Monitor"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

$productTask = Get-PlatformTask "Monitor"
if (!$productTask) {
    $subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='eventlog' or @Name='Microsoft-Windows-Eventlog' or @Name='User32'] and (EventID=1074 or EventID=1075 or EventID=6006)]]</Select></Query></QueryList>"        
    Register-PlatformTask -Id "Monitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Monitor").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 5) -RepetitionDuration ([timespan]::MaxValue) `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest `
        -Subscription $subscription -Disable
    $productTask = Get-PlatformTask "Monitor"
}

$message = "$($emptyString.PadLeft(27,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(7-$productTask.Status.Length -gt 0 ? 7-$productTask.Status.Length : 0," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
