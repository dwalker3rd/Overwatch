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

# function global:Publish-TSContent {

#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory=$false)][string]$Path,
#         [Parameter(Mandatory=$false)][string]$Name,
#         [Parameter(Mandatory=$false)][string]$ProjectName,
#         [Parameter(Mandatory=$false)][string]$ParentProjectName,
#         [switch]$Overwrite,
#         [switch]$Tabbed
#     )

#     $workbookExtensions = @("twb","twbx")
#     $datasourceExtensions = @("tde","tds","tdsx","hyper")

#     $fileLeafBase = Split-Path $Path -LeafBase
#     $fileExtension = Split-Path $Path -Extension
#     $fileType = $fileExtension.TrimStart(".")
#     $objectName = [string]::IsNullOrEmpty($Name) ? $fileLeafBase : $Name

#     $objectType = ""
#     if ($fileType -in $workbookExtensions) { $objectType = "workbook" }
#     if ($fileType -in $datasourceExtensions) { $objectType = "datasource" }
#     if ([string]::IsNullOrEmpty($objectType)) { throw "`"$fileType`" is an invalid file type for the tabcmd publish method"}

#     . tabcmd publish $Path --name $objectName --project $ProjectName --overwrite

# }

#endregion TABCMD