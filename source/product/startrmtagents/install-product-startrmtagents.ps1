param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

if ($global:Platform.Id -ne "TableauRMT") {
    Write-Host+ -NoTrace -NoTimestamp "The product, `"StartRMTAgents`", is only valid for the TableauRMT platform." -ForegroundColor Red
    return
}

$product = Get-Product "StartRMTAgents"
$Name = $product.Name 
$Publisher = $product.Publisher

if (!$NoNewLine) {
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

$productTask = Get-PlatformTask -Id "StartRMTAgents"
if (!$productTask) {
    Register-PlatformTask -Id "StartRMTAgents" -execute $pwsh -Argument "$($global:Location.Scripts)\$("StartRMTAgents").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(60) -ExecutionTimeLimit $(New-TimeSpan -Minutes 120) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "StartRMTAgents"
}

$message = "$($emptyString.PadLeft(28,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")