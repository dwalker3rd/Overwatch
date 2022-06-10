#region TABCMD

function global:Connect-Tabcmd {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = "localhost",
        [Parameter(Mandatory=$false)][Alias("Site")][string]$ContentUrl = "",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)"
    )

    $creds = get-credentials -Name $Credentials
    if (!$creds) { throw "`"$Credentials`" is not a valid credentials name" }

    . tabcmd login -s $Server -u $creds.Username -p $creds.GetNetworkCredential().Password --no-certcheck

    return
        
}

function global:Disconnect-Tabcmd {

    [CmdletBinding()]
    param ()

    . tabcmd logout
        
}

function global:Reset-OpenIdSub {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Username
    )

    . tabcmd reset_openid_sub --target-username $Username --no-certcheck
        
}

#endregion TABCMD