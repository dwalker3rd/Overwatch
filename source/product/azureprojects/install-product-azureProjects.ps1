param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureProjects"
$Name = $product.Name 
$Publisher = $product.Publisher

if (!$NoNewLine) {
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}

if (!(Test-Path -Path "$($global:Location.Data)\azure")) {
    New-Item -Path "$($global:Location.Data)" -Name "azure" -ItemType "directory" | Out-Null
}

Copy-File "$($global:Location.Root)\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1" "$($global:Location.Root)\definitions\definitions-product-$($product.Id.ToLower()).ps1" -Quiet

# Azure Deployment Code/Data
Expand-Archive "$($global:Location.Root)\source\product\$($product.id.tolower())\deployment.zip" "$($global:Location.Root)\data\azure" -Force

$message = "$($emptyString.PadLeft(27,"`b"))INSTALLED$($emptyString.PadLeft(11," "))READY   "
Write-Host+ -NoTrace -NoTimeStamp -NoSeparator -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, DarkGreen