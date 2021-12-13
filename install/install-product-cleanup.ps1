$product = Get-Product "Cleanup"
$Name = $product.Name 
$Vendor = $product.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\templates\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if ($(Get-PlatformTask -Id "Cleanup")) {
    Unregister-PlatformTask -Id "Cleanup"
}

# scheduled time as UTC
$at = get-date -date "5:45Z"

Register-PlatformTask -Id "Cleanup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Cleanup").ps1" -WorkingDirectory $global:Location.Scripts `
-Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -SyncAcrossTimeZones

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkGreen, DarkRed