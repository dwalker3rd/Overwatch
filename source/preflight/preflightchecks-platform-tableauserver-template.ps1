#region PREFLIGHT

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

Test-Connections
Test-PSRemoting

$platformStatus = Get-PlatformStatus
if ($platformStatus.IsOK) {
    Test-TsmController
    Confirm-PlatformLicenses
    Test-SslProtocol $global:Platform.Uri.Host 
    Get-PlatformTopology nodes -Keys | ForEach-Object {Test-SslProtocol ($_ + "." + $global:Platform.Domain) -PassFailOnly}
    # $global:PreflightChecksCompleted = $true
}
else {
    $global:PreflightChecksCompleted = $false
}

#endregion PREFLIGHT