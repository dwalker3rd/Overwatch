param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureProjects"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.Id.ToLower()).ps1 -Quiet

# Azure Deployment Code/Data
Expand-Archive "$PSScriptRoot\source\product\$($product.id.tolower())\deployment.zip" "$($global:Location.Data)\azure"

$message = "$($emptyString.PadLeft(27,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(7-$productTask.Status.Length -gt 0 ? 7-$productTask.Status.Length : 0," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")