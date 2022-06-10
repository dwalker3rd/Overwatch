$product = Get-Product "AzureADSyncB2C"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

foreach ($node in (pt nodes -k)) {
    $remotedirectory = "\\$node\$(($global:AzureAD.Data).Replace(":","$"))"
    if (!(Test-Path $remotedirectory)) { 
        New-Item -ItemType Directory -Path $remotedirectory -Force | Out-Null
        Write-Host+ -NoTrace -NoTimeStamp $remotedirectory -ForegroundColor DarkGray
    }
}

if ($(Get-PlatformTask -Id "AzureADSyncB2C")) {
    Unregister-PlatformTask -Id "AzureADSyncB2C"
}

Register-PlatformTask -Id "AzureADSyncB2C" -execute $pwsh -Argument "$($global:Location.Scripts)\$("AzureADSyncB2C").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkRed