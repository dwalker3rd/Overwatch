#region PLATFORM DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:Platform =
    [Platform]@{
        Id = "TableauServer"
        Name = "Tableau Server"
        DisplayName = "Tableau Server"
        Image = "$($global:Location.Images)/tableau_sparkle.png"
        Description = ""
    }    

$global:Platform.Api = @{
    TsRestApiVersion = "3.6"
    TsmApiVersion = "0.5"
}

$global:PlatformStatusNotOK = @(
    'Unlicensed',
    'Down',
    'StatusNotAvailable','StatusUnAvailable',
    'StatusNotAvailableSyncing',
    'NotAvailable',
    'DecommissionedReadOnly','DecommisionedReadOnly',
    'DecommissioningReadOnly','DecomisioningReadOnly',
    'DecommissionFailedReadOnly',
    'Degraded',
    'Stopping',"Starting","Restarting"
)

$global:PlatformStatusOK = @(
    'Active',
    'ActiveSyncing',
    'Busy',
    'Running',
    'Passive',
    'ReadOnly'
)

$global:SiteRoles = @(
    "Creator",
    "Explorer",
    "ExplorerCanPublish",
    "SiteAdministratorExplorer",
    "SiteAdministratorCreator",
    "Unlicensed",
    "Viewer",
    "ServerAdministrator"
)

$global:SiteAdminRoles = @(
    "SiteAdministratorExplorer",
    "SiteAdministratorCreator",
    "ServerAdministrator"
)

$global:Backup = $null
$global:Backup += @{
    Path = $(. tsm configuration get -k basefilepath.backuprestore)
    Name = "$($global:Environ.Instance).$(Get-Date -Format 'yyyyMMddHHmm')"
    Extension = "tsbak"
    Keep = 1
}
$global:Backup += @{File = "$($Backup.Name).$($Backup.Extension)"}

#endregion PLATFORM DEFINITIONS