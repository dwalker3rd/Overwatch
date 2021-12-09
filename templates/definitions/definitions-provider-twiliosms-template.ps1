#region PROVIDER DEFINITIONS

<# 
.Synopsis
Template for Twilio SMS provider
.Description
Definitions required by the TwilioSMS provider

.Parameter From
The Twilio phone number from which SMS messages will be sent.
.Parameter To
The phone numbers to which SMS messages will be sent.  Must be defined here OR when calling the provider code.
.Parameter Throttle
Period of time during before a duplicate SMS message can be sent.
.Parameter MessageType
The message types for which messages should be sent.
Supported options:  Information, Warning, Alert, Task, AllClear
.Parameter Credentials
Encrypted credentials file for Twilio account. 
#>

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $Provider = $null
    $Provider = [Provider]@{
        Id = "TwilioSMS"
        Name = "Twilio SMS"
        DisplayName = "Twilio SMS"
        Category = "Messaging"
        SubCategory = "SMS"
        Description = "Overwatch messaging via Twilio SMS"
        Log = "$($global:Location.Logs)\$($Provider.Id).log"
        Vendor = "Overwatch"
    }

    $SMSConfig = @{
        From = "+15025551212"
        To = @()
        Throttle = New-TimeSpan -Minutes 15
        MessageType = @($PlatformMessageType.Alert)
    }
    $SMSConfig += @{Credentials = Get-Credentials $Provider.Id}
    $SMSConfig += @{RestEndpoint = "https://api.twilio.com/2010-04-01/Accounts/$($($SMSConfig.Credentials).UserName)/Messages.json"}

    $Provider.Config = $SMSConfig

    return $Provider

#endregion PROVIDER DEFINITIONS