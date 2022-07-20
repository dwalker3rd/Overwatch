$Provider = Get-Provider -Id 'Postgres'
$Name = $Provider.Name 
$Publisher = $Provider.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

if (!(Test-Log -Name $Provider.Id.ToLower())) {
    New-Log -Name $Provider.Id.ToLower() | Out-Null
}

$message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen