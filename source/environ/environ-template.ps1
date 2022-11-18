$global:Environ = 
@{
    OS = "<operatingSystemId>"
    Platform = "<platformId>"
    Instance = "<platformInstanceId>"
    Product = @(<productIds>)
    Provider = @(<providerIds>)
}

$global:Location =
@{
    Root = "<overwatchInstallLocation>"
    Images = "<imagesURI>"
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
    Views = "$($global:Location.Root)\views"
    Logs = "$($global:Location.Root)\logs"
    Temp = "$($global:Location.Root)\temp"
}