param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "SSOMonitor"
$Id = $product.Id 

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

Copy-File "$($global:Location.Root)\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1" "$($global:Location.Root)\definitions\definitions-product-$($product.Id.ToLower()).ps1" -Quiet

$productTask = Get-PlatformTask -Id "SSOMonitor"
if (!$productTask) {
    Register-PlatformTask -Id "SSOMonitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("SSOMonitor").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddSeconds(5) -RepetitionInterval $(New-TimeSpan -Seconds 60) -RepetitionDuration ([timespan]::MaxValue) `
        -ExecutionTimeLimit $(New-TimeSpan -Seconds 60) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "SSOMonitor"
}

$message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
