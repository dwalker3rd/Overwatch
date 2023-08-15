#region PLATFORM DEFINITIONS

$global:Platform = $global:Catalog.Platform.TableauServer
$global:Platform.Image = "$($global:Location.Images)/tableau_sparkle.png"
# $global:Platform.Api = @{
#     TsRestApiVersion = $global:Catalog.Platform.TableauServer.Api.TableauServerRestApi.Version
#     TsmApiVersion = $global:Catalog.Platform.TableauServer.Api.TsmApi.Version
# }

$global:PlatformStatusNotOK = @(
    'Unlicensed',
    'Down',
    'StatusNotAvailable','
    StatusUnAvailable',
    'StatusNotAvailableSyncing',
    'NotAvailable',
    'DecommissionedReadOnly',
    'DecommisionedReadOnly',
    'DecommissioningReadOnly',
    'DecomisioningReadOnly',
    'DecommissionFailedReadOnly',
    'Degraded',
    'Stopping',
    'Starting',
    'Restarting'
)

$global:PlatformStatusOK = @(
    'Active',
    'ActiveSyncing',
    'Busy',
    'Running',
    'Passive',
    'ReadOnly'
)

$global:PlatformStatusColor = @{
    Unlicensed = "DarkRed"
    Down = "DarkRed"
    StatusNotAvailable = "DarkYellow"
    StatusUnAvailable = "DarkYellow"
    StatusNotAvailableSyncing = "DarkYellow"
    NotAvailable = "DarkYellow"
    DecommissionedReadOnly = "DarkYellow"
    DecommisionedReadOnly = "DarkYellow"
    DecommissioningReadOnly = "DarkYellow"
    DecomisioningReadOnly = "DarkYellow"
    DecommissionFailedReadOnly = "DarkYellow"
    Degraded = "DarkRed"
    Stopping = "DarkYellow"
    Stopped = "DarkRed"
    Starting = "DarkYellow"
    Restarting = "DarkYellow"
    Active = "DarkGreen"
    ActiveSyncing = "DarkGreen"
    Busy = "Green"
    Running = "DarkGreen"
    Passive = "DarkGreen"
    ReadOnly = "DarkGreen"
}

$global:TSSiteRoles = @(
    "Creator",
    "Explorer",
    "ExplorerCanPublish",
    "SiteAdministratorExplorer",
    "SiteAdministratorCreator",
    "Unlicensed",
    "Viewer",
    "ServerAdministrator"
)

$global:TSSiteRoleMinimum = "Viewer"

$global:TSSiteAdminRoles = @(
    "SiteAdministratorExplorer",
    "SiteAdministratorCreator",
    "ServerAdministrator"
)

$global:Cleanup = $null
$global:Cleanup += @{
    All = $false
    BackupFiles = $false
    BackupFilesRetention = 1
    LogFiles = $true
    LogFilesRetention = 1
    HttpRequestsTable = $false
    HttpRequestsTableRetention = 7
    TempFiles = $true 
    RedisCache = $false 
    SheetImageCache = $false
    TimeoutInSeconds = 0
}   

#endregion PLATFORM DEFINITIONS