#region PROVIDER DEFINITIONS

    $definitionsPath = $global:Location.Definitions
    . $definitionsPath\classes.ps1

    $Provider = $null
    $Provider = $global:Catalog.Provider.MicrosoftTeams

    if (!$global:MicrosoftTeamsConfig) {
        throw "Microsoft Teams Connectors have not been defined."
    }

    $Provider.Config = $global:MicrosoftTeamsConfig
    $Provider.Config += @{
        Throttle = New-TimeSpan -Minutes 15
    }

    return $Provider

#endregion PROVIDER DEFINITIONS