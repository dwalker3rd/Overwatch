#region TABCMD

function global:Connect-Tabcmd {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($global:Platform.Instance)"
    )

    $prerequisiteTestResults = Test-Prerequisites -Type "Provider" -Id "TableauServerTabCmd" -Quiet
    if (!$prerequisiteTestResults.Pass) { 
        throw $prerequisiteTestResults.Prerequisites[0].Tests.Reason
    }

    $_credentials = get-Credentials -Id $Credentials -ComputerName $Server

    . tabcmd login -s $Server -u $_credentials.Username -p $_credentials.GetNetworkCredential().Password --no-certcheck

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