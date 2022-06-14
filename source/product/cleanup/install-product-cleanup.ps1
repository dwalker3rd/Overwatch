$product = Get-Product "Cleanup"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if ($(Get-PlatformTask -Id "Cleanup")) {
    Unregister-PlatformTask -Id "Cleanup"
}

# scheduled time as UTC
$at = get-date -date "5:45Z"

Register-PlatformTask -Id "Cleanup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Cleanup").ps1" -WorkingDirectory $global:Location.Scripts `
-Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -SyncAcrossTimeZones -Disable

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkRed