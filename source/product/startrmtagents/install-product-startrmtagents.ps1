if ($global:Platform.Id -ne "TableauRMT") {
    Write-Host+ -NoTrace -NoTimestamp "The product, `"StartRMTAgents`", is only valid for the TableauRMT platform." -ForegroundColor Red
    return
}

$product = Get-Product "StartRMTAgents"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\source\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

if ($(Get-PlatformTask -Id "StartRMTAgents")) {
    Unregister-PlatformTask -Id "StartRMTAgents"
}

Register-PlatformTask -Id "StartRMTAgents" -execute $pwsh -Argument "$($global:Location.Scripts)\$("StartRMTAgents").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(60) -ExecutionTimeLimit $(New-TimeSpan -Minutes 120) -RunLevel Highest -Disable

$message = "$($emptyString.PadLeft(34,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","DISABLED"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen, DarkRed