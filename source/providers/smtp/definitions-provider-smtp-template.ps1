#region PROVIDER DEFINITIONS

    . "$($global:Location.Definitions)\classes.ps1"

    $Provider = $null
    $Provider = $global:Catalog.Provider.SMTP

    $SmtpCredentials = Get-Credentials smtp
    $SmtpConfig = 
        @{
            Server = “<server>”
            Port = "<port>"
            UseSsl = "<useSsl>"
            MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear)
            # Credentials = $SmtpCredentials
            From = $($SmtpCredentials).UserName
            To = @()
            Throttle = New-TimeSpan -Minutes 15
        }

    $Provider.Config = $SmtpConfig

    return $Provider

#endregion PROVIDER DEFINITIONS