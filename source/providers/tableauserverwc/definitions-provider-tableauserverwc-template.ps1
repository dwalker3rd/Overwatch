#region PROVIDER DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\catalog.ps1
. $definitionsPath\classes.ps1

$Provider = $null
$Provider = $global:Catalog.Provider.TableauServerWC
$Provider.Config = @{
    MessageType = $PlatformMessageType.UserNotification
}

return $Provider

#endregion PROVIDER DEFINITIONS