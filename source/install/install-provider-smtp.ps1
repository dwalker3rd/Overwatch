$Provider = Get-Provider -Id 'SMTP'
$Name = $Provider.Name 
$Publisher = $Provider.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

if (!(Test-Log -Name smtp)) {
    New-Log -Name "smtp" | Out-Null
}

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$interaction = $false
$overwatchRoot = $PSScriptRoot -replace "\\install",""
if (Get-Content -Path $overwatchRoot\definitions\definitions-provider-smtp.ps1 | Select-String "<server>" -Quiet) {

    $interaction = $true

    Write-Host+; Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "      SMTP Configuration"
    Write-Host+ -NoTrace -NoTimestamp "      -----------------"
    $server = Read-Host "      Server"
    $port = Read-Host "      Port"
    $useSsl = (Read-Host "      Use SSL? (Y/N)") -eq "Y" ? "`$true" : "`$false"


    $smtpDefinitionsFile = Get-Content -Path $overwatchRoot\definitions\definitions-provider-smtp.ps1
    $smtpDefinitionsFile = $smtpDefinitionsFile -replace "<server>", $server
    $smtpDefinitionsFile = $smtpDefinitionsFile -replace "<port>", $port
    $smtpDefinitionsFile = $smtpDefinitionsFile -replace '"<useSsl>"', $useSsl
    $smtpDefinitionsFile | Set-Content -Path $overwatchRoot\definitions\definitions-provider-smtp.ps1

}

if (!$(Test-Credentials $Provider.Id -NoValidate)) {
    if(!$interaction) {
        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "      SMTP Configuration"
        Write-Host+ -NoTrace -NoTimestamp "      -----------------"
    }
    $interaction = $true
    Request-Credentials -Prompt1 "      Account" -Prompt2 "      Password" | Set-Credentials $Provider.Id
}

if ($interaction) {
    Write-Host+
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGreen
}
else {
    $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen
}

[console]::CursorVisible = $cursorVisible