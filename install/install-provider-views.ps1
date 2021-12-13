$Provider = Get-Provider -Id 'Views'
$Name = $Provider.Name 
$Vendor = $Provider.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

$message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen