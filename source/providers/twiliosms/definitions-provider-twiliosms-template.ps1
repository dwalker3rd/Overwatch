#region PROVIDER DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $Provider = $null
    $Provider = $global:Catalog.Provider.TwilioSMS

    $SMSConfig = @{
        From = "<fromPhone>"
        To = @()
        Throttle = New-TimeSpan -Minutes 15
        MessageType = @($PlatformMessageType.Alert,$PlatformMessageType.AllClear)
    }
    $SMSConfig += @{Credentials = Get-Credentials $Provider.Id}
    $SMSConfig += @{RestEndpoint = "https://api.twilio.com/2010-04-01/Accounts/$($($SMSConfig.Credentials).UserName)/Messages.json"}

    $Provider.Config = $SMSConfig

    return $Provider

#endregion PROVIDER DEFINITIONS