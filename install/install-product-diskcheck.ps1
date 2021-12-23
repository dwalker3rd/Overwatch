$product = Get-Product "DiskCheck"
$Name = $product.Name 
$Vendor = $product.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\templates\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if ($(Get-PlatformTask -Id "DiskCheck")) {
    Unregister-PlatformTask -Id "DiskCheck"
}

Register-PlatformTask -Id "DiskCheck" -execute $pwsh -Argument "$($global:Location.Scripts)\$("DiskCheck").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(60) -RepetitionInterval $(New-TimeSpan -Minutes 60) -RepetitionDuration ([timespan]::MaxValue) `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","READY"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkGreen