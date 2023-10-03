param (
    [switch]$UseDefaultResponses
)

$Provider = Get-Provider -Id 'TableauServerWC'
$Id = $Provider.Id 

$interaction = $false

$cursorVisible = [console]::CursorVisible
Set-CursorVisible

$message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray


#region PRODUCT-SPECIFIC INSTALLATION

    $tblwgadminCreds = Request-Credentials -Username "tblwgadmin" -Password (. tsm configuration get -k pgsql.adminpassword)
    $readonlyCreds = Request-Credentials -Username "readonly" -Password (. tsm configuration get -k pgsql.readonly_password)

    Set-Credentials -Id "tblwgadmin-$($Platform.Instance)" -Credentials $tblwgadminCreds
    Set-Credentials -Id "readonly-$($Platform.Instance)" -Credentials $readonlyCreds

    if (!(Get-ConnectionString -Id "workgroup-admin-$($Platform.Instance)")) {
        New-ConnectionString -Id "workgroup-admin-$($Platform.Instance)" -DatabaseType "PostgreSQL" -DriverType "ODBC" -Driver "PostgreSQL Unicode(x64)" -Server (pt initialnode) -Port "8060" -Database "workgroup" -Credentials $tblwgadminCreds -SslMode require
    }
    else {
        Update-ConnectionString -Id "workgroup-admin-$($Platform.Instance)" -DatabaseType "PostgreSQL" -DriverType "ODBC" -Driver "PostgreSQL Unicode(x64)" -Server (pt initialnode) -Port "8060" -Database "workgroup" -Credentials $tblwgadminCreds -SslMode require
    }
    if (!(Get-ConnectionString -Id "workgroup-readonly-$($Platform.Instance)")) {
        New-ConnectionString -Id "workgroup-readonly-$($Platform.Instance)" -DatabaseType "PostgreSQL" -DriverType "ODBC" -Driver "PostgreSQL Unicode(x64)" -Server (pt initialnode) -Port "8060" -Database "workgroup" -Credentials $readonlyCreds -SslMode require
    }
    else {
        Update-ConnectionString -Id "workgroup-readonly-$($Platform.Instance)" -DatabaseType "PostgreSQL" -DriverType "ODBC" -Driver "PostgreSQL Unicode(x64)" -Server (pt initialnode) -Port "8060" -Database "workgroup" -Credentials $readonlyCreds -SslMode require
    }

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