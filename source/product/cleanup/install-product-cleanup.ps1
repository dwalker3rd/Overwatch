param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "Cleanup"
$Id = $product.Id 

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

Copy-File "$($global:Location.Root)\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1" "$($global:Location.Root)\definitions\definitions-product-$($product.Id.ToLower()).ps1" -Quiet

$productTask = Get-PlatformTask -Id "Cleanup"
if (!$productTask) {
    $at = get-date -date "5:45Z"
    Register-PlatformTask -Id "Cleanup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Cleanup").ps1" -WorkingDirectory $global:Location.Scripts `
        -Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "Cleanup"
}

$message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")

