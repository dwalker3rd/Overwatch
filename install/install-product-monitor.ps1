$product = Get-Product "Monitor"
$Name = $product.Name 
$Vendor = $product.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\templates\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if ($(Get-PlatformTask -Id "Monitor")) {
    Unregister-PlatformTask -Id "Monitor"
}

$subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='eventlog' or @Name='Microsoft-Windows-Eventlog' or @Name='User32'] and (EventID=1074 or EventID=1075 or EventID=6006)]]</Select></Query></QueryList>"        
Register-PlatformTask -Id "Monitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Monitor").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 5) -RepetitionDuration ([timespan]::MaxValue) `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest `
    -Subscription $subscription -Disable

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkRed
