param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$Product = Get-Product -Id 'Command'
$Name = $product.Name 

if (!$NoNewLine) {
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}

#region PRODUCT-SPECIFIC INSTALLATION
#endregion PRODUCT-SPECIFIC INSTALLATION

$message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))READY$($emptyString.PadLeft(15," "))"
Write-Host+ -NoTrace -NoTimeStamp -NoSeparator -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen,DarkGreen