param (
    [switch]$UseDefaultResponses
)

$Provider = Get-Provider -Id 'TableauServerTabCmd'
$Name = $Provider.Name 

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$interaction = $false

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

#region PRODUCT-SPECIFIC INSTALLATION
#endregion PRODUCT-SPECIFIC INSTALLATION

if ($interaction) {
    Write-Host+
    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGreen
}
else {
    $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen
}

[console]::CursorVisible = $cursorVisible