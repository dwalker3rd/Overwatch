$Provider = Get-Provider -Id 'MicrosoftTeams'
$Name = $Provider.Name 
$Vendor = $Provider.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING*"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkYellow

if (!(Test-Log -Name "microsoftteams")) {
    New-Log -Name "microsoftteams" | Out-Null
}

Write-Host+
$message = "    * Manually add your webhooks to `$global:MicrosoftTeamsConfig.Connector in "
Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
$message = "        $($PSScriptRoot)\definitions\definitions-platforminstance-$($global:Environ.Instance).ps1"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
Write-Host+