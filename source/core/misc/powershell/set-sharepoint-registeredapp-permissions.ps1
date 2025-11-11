$applicationClientId = ""

# current version of Microsoft.Graph is required

# Connect with an account that is site admin and can get a token with Sites.FullControl.All
Connect-MgGraph -Scopes "Sites.FullControl.All"

# shortcut site id - not what we need for setting permissions
# use this to get the site object and get the proper site it
$siteId = "<tenantKey>.sharepoint.com:/sites/<siteName>:"
$site = Get-MgSite -SiteId $siteId
$siteId = $site.id

# grant read access
$identity   = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphIdentity]::new()
$identity.Id = $applicationClientId   # ← client ID, not objectId
$identitySet = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphIdentitySet]::new()
$identitySet.Application = $identity
New-MgSitePermission -SiteId $siteId -Role @("read") -GrantedTo $identitySet

# Verify
Get-MgSitePermission -SiteId $siteId
 