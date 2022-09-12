param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "AzureADSyncTS"
$Name = $product.Name 
$Publisher = $product.Publisher

if (!$NoNewLine) {
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
}

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

foreach ($node in (pt nodes -k)) {
    $remotedirectory = "\\$node\$(($global:AzureAD.Data).Replace(":","$"))"
    if (!(Test-Path $remotedirectory)) { 
        New-Item -ItemType Directory -Path $remotedirectory -Force | Out-Null
    }
}

$productTask = Get-PlatformTask -Id "AzureADSyncTS"
if (!$productTask) {
    Register-PlatformTask -Id "AzureADSyncTS" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AzureADSyncTS").ps1" -WorkingDirectory $global:Location.Scripts `
        -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
        -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable
    $productTask = Get-PlatformTask -Id "AzureADSyncTS"
}

$message = "$($emptyString.PadLeft(28,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")