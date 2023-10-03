param (
    [switch]$UseDefaultResponses
)

$_provider = Get-Provider -Id 'TableauServerWC'
$_provider | Out-Null

#region PROVIDER-SPECIFIC INSTALLATION

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

#endregion PROVIDER-SPECIFIC INSTALLATION