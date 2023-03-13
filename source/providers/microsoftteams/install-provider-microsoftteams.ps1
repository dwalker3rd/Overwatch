param (
    [switch]$UseDefaultResponses
)

$Provider = Get-Provider -Id 'MicrosoftTeams'
$Id = $Provider.Id 

$cursorVisible = [console]::CursorVisible
Set-CursorVisible

$interaction = $false

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

#region PRODUCT-SPECIFIC INSTALLATION
#endregion PRODUCT-SPECIFIC INSTALLATION

if ($interaction) {
    Write-Host+
    $message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGreen
}
else {
    $message = "$($emptyString.PadLeft(7,"`b"))INSTALLED"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen
}

[console]::CursorVisible = $cursorVisible