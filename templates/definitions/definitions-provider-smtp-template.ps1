#region PROVIDER DEFINITIONS

<# 
.Synopsis
Template for SMTP provider
.Description
Definitions required by the SMTP provider

.Parameter Server
The SMTP server
.Parameter Port
The SMTP port
.Parameter UseSSL
Whether or not SSL should be used with SMTP
.Parameter MessageType
The message types for which messages should be sent.
Supported options:  Information, Warning, Alert, Task, AllClear
.Parameter Credentials
Encrypted credentials file for the SMTP account 
#>

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
        Vendor = "Overwatch"
    }

    $SmtpCredentials = Get-Credentials smtp
    $SmtpConfig = 
        @{
            Server = “smtp.office365.com”
            Port = "587"
            UseSsl = $true
            MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear)
            Credentials = $SmtpCredentials
            From = $($SmtpCredentials).UserName
            To = @()
            Throttle = New-TimeSpan -Minutes 15
        }

    $Provider.Config = $SmtpConfig

    return $Provider

#endregion PROVIDER DEFINITIONS