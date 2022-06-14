#region PROVIDER DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $Provider = $null
    $Provider = [Provider]@{
        Id = "SMTP"
        Name = "SMTP"
        DisplayName = "SMTP"
        Category = "Messaging"
        SubCategory = "SMTP"
        Description = "Overwatch messaging via SMTP"
        Log = "$($global:Location.Logs)\$($Provider.Id).log"
        Publisher = "Overwatch"
    }

    $SmtpCredentials = Get-Credentials smtp
    $SmtpConfig = 
        @{
            Server = “<server>”
            Port = "<port>"
            UseSsl = "<useSsl>"
            MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear)
            Credentials = $SmtpCredentials
            From = $($SmtpCredentials).UserName
            To = @()
            Throttle = New-TimeSpan -Minutes 15
        }

    $Provider.Config = $SmtpConfig

    return $Provider

#endregion PROVIDER DEFINITIONS