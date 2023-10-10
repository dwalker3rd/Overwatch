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
$Provider = $global:Catalog.Provider.SMTP

$SmtpConfig = 
    @{
        Server = "smtp.office365.com"
        Port = "587"
        UseSsl = $true
        MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear,$PlatformMessageType.Intervention)
        From = $null # deferred to provider
        To = @()
        Throttle = New-TimeSpan -Minutes 15
    }

$Provider.Config = $SmtpConfig

return $Provider

#endregion PROVIDER DEFINITIONS
