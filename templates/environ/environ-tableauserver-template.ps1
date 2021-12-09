#region INSTANCE DEFINITIONS

$global:Environ = 
@{
    OS = "WindowsServer"
    Platform = "TableauServer"
    Instance = "tableau-acme-org"
    Product = @("Monitor","Backup","Cleanup","DiskCheck","Command","AzureADCache","AzureADSync","AzureADReset")
    Provider = @("Vault","MicrosoftTeams","TwilioSMS","SMTP","Views")
}

$global:Location =
@{
    Root = "F:\Overwatch"
    Images = "https://public.cdn.com/images"
}
$global:Location += 
@{
    Scripts = "$($global:Location.Root)"
    Definitions = "$($global:Location.Root)\definitions"
    Providers = "$($global:Location.Root)\providers"
    Services = "$($global:Location.Root)\services"
    Install = "$($global:Location.Root)\install"
    Initialize = "$($global:Location.Root)\initialize"
    Preflight = "$($global:Location.Root)\preflight"
    Postflight = "$($global:Location.Root)\postflight"
    Help = "$($global:Location.Root)\help"

    Data = "$($global:Location.Root)\data\$($global:Environ.Instance)"
    Credentials = "$($global:Location.Root)\data\$($global:Environ.Instance)"
    Logs = "$($global:Location.Root)\logs"
    Temp = "$($global:Location.Root)\temp\$($global:Environ.Instance)"
}

#endregion INSTANCE DEFINITIONS