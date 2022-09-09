#region PROVIDER DEFINITIONS

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$Provider = $null
$Provider = $global:Catalog.Provider.TwilioSMS

$SMSConfig = @{
    From = "+12075582078"
    To = @()
    Throttle = New-TimeSpan -Minutes 15
    MessageType = @($PlatformMessageType.Alert,$PlatformMessageType.AllClear)
}
$SMSConfig += @{RestEndpoint = "https://api.twilio.com/2010-04-01/Accounts/<AccountSID>/Messages.json"}

$Provider.Config = $SMSConfig

return $Provider

#endregion PROVIDER DEFINITIONS
