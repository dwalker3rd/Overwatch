#region PROVIDER DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $Provider = $null
    $Provider = [Provider]@{
        Id = "MicrosoftTeams"
        Name = "Microsoft Teams"
        DisplayName = "Microsoft Teams"
        Category = "Messaging"
        SubCategory = "Teams"
        Description = "Overwatch messaging via Microsoft Teams"
        Vendor = "Overwatch"
    }

    if (!$global:MicrosoftTeamsConfig) {
        throw "Microsoft Teams Connectors have not been defined."
    }

    $Provider.Config = $global:MicrosoftTeamsConfig
    $Provider.Config += @{
        Throttle = New-TimeSpan -Minutes 15
    }

    return $Provider

#endregion PROVIDER DEFINITIONS