#region ENVIRON

    $global:Environ = @{
        OS = "<operatingSystemId>"
        Platform = "<platformId>"
        Instance = "<platformInstanceId>"
        Product = @(<productIds>)
        Provider = @(<providerIds>)
    }

#endregion ENVIRON
#region LOCATION

    $global:Location = @{
        Root = "<overwatchInstallLocation>"
        Images = "<imagesURI>"
    }
    $global:Location += @{
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
        Sysinternals = "$($global:Location.Root)\sysinternals"
}

#endregion LOCATION     







