param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "Backup"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

Copy-File "$($global:Location.Root)\source\product\$($product.Id.ToLower())\definitions-product-$($product.Id.ToLower())-template.ps1" "$($global:Location.Root)\definitions\definitions-product-$($product.Id.ToLower()).ps1" -Quiet

$backupPath = . tsm configuration get -k basefilepath.backuprestore
if (!(Test-Path -Path $backupPath)) {New-Item -ItemType Directory -Path $backupPath}

$productTask = Get-PlatformTask -Id "Backup"
if (!$productTask) {
    $at = get-date -date "6:00Z"
    Register-PlatformTask -Id "Backup" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Backup").ps1" -WorkingDirectory $global:Location.Scripts `
        -Daily -At $at -ExecutionTimeLimit $(New-TimeSpan -Minutes 60) -RunLevel Highest -SyncAcrossTimeZones `
        -Subscription $subscription -Disable
    $productTask = Get-PlatformTask -Id "Backup"
}

$message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "DarkRed")
