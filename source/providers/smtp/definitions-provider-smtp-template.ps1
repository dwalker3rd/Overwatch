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
        Server = "<server>"
        Port = "<port>"
        UseSsl = "<useSsl>"
        MessageType = @($PlatformMessageType.Warning,$PlatformMessageType.Alert,$PlatformMessageType.AllClear,$PlatformMessageType.Intervention)
        From = $null # deferred to provider
        To = @()
        Throttle = New-TimeSpan -Minutes 15
    }

$Provider.Config = $SmtpConfig

return $Provider

#endregion PROVIDER DEFINITIONS
