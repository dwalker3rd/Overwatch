#region PROVIDER DEFINITIONS

. "$($global:Location.Definitions)\catalog.ps1"
. "$($global:Location.Definitions)\classes.ps1"

$Provider = $null
$Provider = $global:Catalog.Provider.TableauServerWC
$Provider.Config = @{
    MessageType = $PlatformMessageType.UserNotification
}

return $Provider

#endregion PROVIDER DEFINITIONS