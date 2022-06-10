$product = Get-Product "Backup"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if (!(Test-Path -Path $Backup.Path)) {New-Item -ItemType Directory -Path $Backup.Path}

if ($(Get-PlatformTask -Id "Backup")) {
    Unregister-PlatformTask -Id "Backup"
}

# scheduled time as UTC
$at = get-date -date "6:00Z"

Register-PlatformTask -Id "Backup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Backup").ps1" -WorkingDirectory $global:Location.Scripts `
    -Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 60) -RunLevel Highest -SyncAcrossTimeZones

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkRed