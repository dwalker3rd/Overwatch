#region PROVIDER DEFINITIONS

    param(
        [switch]$MinimumDefinitions
    )

    if ($MinimumDefinitions) {
        $root = $PSScriptRoot -replace "\\definitions",""
        Invoke-Command  -ScriptBlock { . $root\definitions.ps1 -MinimumDefinitions }
    }
    else {
        . $PSScriptRoot\classes.ps1
    }

    $Provider = $null
    $Provider = $global:Catalog.Provider.TwilioSMS

    $SMSConfig = @{
        From = "<fromPhone>"
        To = @()
        Throttle = New-TimeSpan -Minutes 15
        MessageType = @($PlatformMessageType.Intervention)
    }
    $SMSConfig += @{RestEndpoint = "https://api.twilio.com/2010-04-01/Accounts/<AccountSID>/Messages.json"}

    $Provider.Config = $SMSConfig

    return $Provider

#endregion PROVIDER DEFINITIONS
