param (
    [switch]$UseDefaultResponses
)

$Provider = Get-Provider -Id 'TableauServerWC'
$Id = $Provider.Id 

$interaction = $false

$cursorVisible = [console]::CursorVisible
[console]::CursorVisible = $true

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray


#region PRODUCT-SPECIFIC INSTALLATION

    Set-Credentials -Name "tblwgadmin-$($Platform.Instance)" -Username "tblwgadmin" -Password (. tsm configuration get -k pgsql.adminpassword)
    Set-Credentials -Name "readonly-$($Platform.Instance)" -Username "readonly" -Password (. tsm configuration get -k pgsql.readonly_password)

    Set-PostgresConnectionString -Name "workgroup-admin-$($Platform.Instance)" -Driver "PostgreSQL Unicode(x64)" -Server (pt initialnode) -Port "8060" -Database "workgroup" -Credentials "tblwgadmin-$($Platform.Instance)" -SslMode require
    Set-PostgresConnectionString -Name "workgroup-readonly-$($Platform.Instance)" -Driver "PostgreSQL Unicode(x64)" -Server (pt initialnode) -Port "8060" -Database "workgroup" -Credentials "readonly-$($Platform.Instance)" -SslMode require

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