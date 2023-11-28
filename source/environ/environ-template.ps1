#region ENVIRON

$global:Environ = @{
    Overwatch = "Overwatch"
    OS = "WindowsServer"
    Cloud = "Azure"
    Platform = "TableauServer"
    Instance = "tableautest-path-org"
    Product = @("AzureADCache", "AzureADSyncTS", "AzureProjects", "AzureUpdateMgmt", "Cleanup", "Command", "DiskCheck", "Monitor")
    Provider = @("AzureAD", "MicrosoftTeams", "Okta", "OnePassword", "Postgres", "SMTP", "TableauServerRestApi", "TableauServerTabCmd", "TableauServerTsmApi", "TableauServerWC", "TwilioSMS", "Views")
}

#endregion ENVIRON
#region LOCATION

$global:Location = @{
    Root = "F:\Overwatch"
    Images = "https://pathai4healthusers.z33.web.core.windows.net/Overwatch/img"
}
$global:Location += @{
    Archive = "$($global:Location.Root)\archive"
    Config = "$($global:Location.Root)\config"
    Credentials = "$($global:Location.Root)\data"
    Data = "$($global:Location.Root)\data"
    Definitions = "$($global:Location.Root)\definitions"
    Help = "$($global:Location.Root)\help"
    Initialize = "$($global:Location.Root)\initialize"
    Install = "$($global:Location.Root)\install"
    Logs = "$($global:Location.Root)\logs"
    Postflight = "$($global:Location.Root)\postflight"
    Preflight = "$($global:Location.Root)\preflight"
    Providers = "$($global:Location.Root)\providers"
    Scripts = "$($global:Location.Root)"
    Services = "$($global:Location.Root)\services"
    Source = "$($global:Location.Root)\source"
    Temp = "$($global:Location.Root)\temp"
    Views = "$($global:Location.Root)\views"
}
$global:Location += @{ Classes = "$($global:Location.Definitions)\classes.ps1"}
$global:Location += @{ Catalog = "$($global:Location.Definitions)\catalog.ps1"}

#endregion LOCATION