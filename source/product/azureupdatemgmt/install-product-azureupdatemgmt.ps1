param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureUpdateMgmt"
$Id = $product.Id 

if (!$NoNewLine) {
    $message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}

Copy-File "$($global:Location.Root)\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1" "$($global:Location.Root)\definitions\definitions-product-$($product.Id.ToLower()).ps1" -Quiet

$message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))READY$($emptyString.PadLeft(15," "))"
Write-Host+ -NoTrace -NoTimeStamp -NoSeparator -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, DarkGreen