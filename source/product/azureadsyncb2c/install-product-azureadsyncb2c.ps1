param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureADSyncB2C"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.Id.ToLower()).ps1 -Quiet

foreach ($node in (pt nodes -k)) {
    $remotedirectory = "\\$node\$(($global:AzureAD.Data).Replace(":","$"))"
    if (!(Test-Path $remotedirectory)) { 
        New-Item -ItemType Directory -Path $remotedirectory -Force | Out-Null
    }
}

$productTask = Get-PlatformTask -Id "AzureADSyncB2C"
if (!$productTask) {
    Register-PlatformTask -Id "AzureADSyncB2C" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AzureADSyncB2C").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "AzureADSyncB2C"
}

$message = "$($emptyString.PadLeft(27,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(7-$productTask.Status.Length -gt 0 ? 7-$productTask.Status.Length : 0," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
