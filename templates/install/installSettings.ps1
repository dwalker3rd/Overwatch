[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
Param()
$operatingSystemId = "WindowsServer"
$platformId = "TableauServer"
$platformInstallLocation = "F:\Program Files\Tableau\Tableau Server"
$platformInstanceId = "tableautest-path-org"
$productIds = @('Monitor', 'Command')
$providerIds = @('SMTP', 'Views')
$imagesUri = [System.Uri]::new("https://pathai4healthusers.z33.web.core.windows.net/Overwatch/img")
