$product = Get-Product "AzureADCache"
$Name = $product.Name 
$Vendor = $product.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\templates\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if ($(Get-PlatformTask -Id "AzureADCache")) {
    Unregister-PlatformTask -Id "AzureADCache"
}

Register-PlatformTask -Id "AzureADCache" -execute $pwsh -Argument "$($global:Location.Scripts)\AzureADCache.ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(15) -RepetitionInterval $(New-TimeSpan -Minutes 15) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 30) -RunLevel Highest -Disable

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkRed