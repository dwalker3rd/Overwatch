#region INSTANCE DEFINITIONS

$global:Environ = 
@{
    OS = "WindowsServer"
    Platform = "AlteryxServer"
    Instance = "alteryx-acme-org"
    Product = @("Monitor","Backup","DiskCheck","Cleanup","Command")
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

    Pip = 'F:\Program Files\Alteryx\bin\Miniconda3\envs\DesignerBaseTools_vEnv\Scripts'
}

#endregion INSTANCE DEFINITIONS