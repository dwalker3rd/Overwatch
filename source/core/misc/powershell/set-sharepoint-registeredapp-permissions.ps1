$siteName = "<your sharepoint site name>"
$applicationId = "<your application id>"
$sharePointTenant = "<your sharepoint tenant name>"

# current version of Microsoft.Graph is required
# determine which version of PowerShellGet is installed
$powerShellGetv3 = Get-Command -Module Microsoft.PowerShell.PSResourceGet -ErrorAction SilentlyContinue
if ($powerShellGetv3) {
    $installedPsResource = Get-InstalledPSResource -Name "Microsoft.Graph" -ErrorAction SilentlyContinue
    if (!$installedPsResource) {
        Install-PSResource -Name "Microsoft.Graph" -Scope CurrentUser
    }
}
else {
    $installedModule = Get-InstalledModule -Name "Microsoft.Graph" -ErrorAction SilentlyContinue
    if (!$installedModule) {
        Install-Module -Name "Microsoft.Graph" -Scope CurrentUser 
    }
}

# Connect with an account that is site admin and can get a token with Sites.FullControl.All
Connect-MgGraph -Scopes "Sites.FullControl.All"

# Resolve siteId (example)
$site = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($sharePointTenant).sharepoint.com:/sites/$siteName`?$select=id"

# grant read access
$params = @{
  roles = @("read")
  grantedTo = @{ application = @{ id = $applicationId } }
}
New-MgSitePermission -SiteId $site.Id -BodyParameter $params

# Verify
Get-MgSitePermission -SiteId $site.Id
 