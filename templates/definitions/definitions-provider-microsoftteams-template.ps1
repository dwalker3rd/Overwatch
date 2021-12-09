#region PROVIDER DEFINITIONS

<# 
.Synopsis
Template for Microsoft Teams provider
.Description
Definitions required by the MicrosoftTeams provider

.Parameter Connector
The Microsoft Teams webhook uri[s] for each message type.
.Parameter MessageType
The message types for which messages should be sent.
Supported options:  Information, Warning, Alert, Task, AllClear

.Link
https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference
#>

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
        # Configure Microsoft Teams in platform instance definition file
    }

    $Provider.Config = $global:MicrosoftTeamsConfig
    $Provider.Config += @{
        Throttle = New-TimeSpan -Minutes 15
    }

    return $Provider

#endregion PROVIDER DEFINITIONS