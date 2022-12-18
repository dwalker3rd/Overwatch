<# 
.Synopsis
Microsoft Teams provider for Overwatch
.Link
https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference
#>


<# 
.Synopsis
Build a section for a message card.
.Description
Build-Section builds a section for a legacy actionable message card.
.Link
https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference#section-fields
#>

function Build-Section {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$ActivityTitle,
        [Parameter(Mandatory=$false)][string]$ActivitySubTitle,
        [Parameter(Mandatory=$false)][string]$ActivityText,
        [Parameter(Mandatory=$false)][string]$ActivityImage,
        [Parameter(Mandatory=$false)][object]$Facts
    )

    return @{
        activityTitle = $ActivityTitle
        activitySubtitle = $ActivitySubTitle
        activityText = $ActivityText
        activityImage = $ActivityImage
        facts = $Facts
    }

}

<# 
.Synopsis
Build a message card.
.Description
Build-MessageCard creates a legacy actionable message card (as JSON) used with Microsoft Teams via a connector (webhook).
.Link
https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference
#>
function Build-MessageCard {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$false)][string]$Text = " ",
        [Parameter(Mandatory=$true)][object]$Sections
    )

    $messageCard = ConvertTo-Json -Depth 8 `
    @{
        context = "https://schema.org/extensions"
        type = "MessageCard"
        title = $Title
        text = $Text
        sections = $Sections
    }

    return $messageCard

}

<# 
.Synopsis
Send a message to Microsoft Teams.
.Description
Send-MicrosoftTeams-Message sends a legacy actionable message card to a Microsoft Teams channel via a connector (webhook).
.Parameter Connector
A Microsoft Teams connector (webhook) configured for a specific Microsoft Teams channel
.Parameter MessageCard
A Microsoft Teams legacy actionable message card
.Link
https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference
#>
function global:Send-MicrosoftTeams {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$false)][object]$Message,
        [Parameter(Mandatory=$false)][string]$json
    )

    $Message = $json | ConvertFrom-Json -Depth 99

    $provider = get-provider -id "MicrosoftTeams" # TODO: pass this in from Send-Message?

    $messageCard = Build-MessageCard -Title $Message.Title -Text $($Message.Text ? $Message.Text : " ") -Sections $Message.Sections

    $logEntry = read-log $Provider.Id -Context "MicrosoftTeams" -Status $global:PlatformMessageStatus.Transmitted -Message $Message.Summary -Newest 1 -View Raw
    $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds :  $null

    if (!$throttle) {
        foreach ($connector in $provider.Config.Connector.$($Message.Type)) {
            $result = Invoke-RestMethod -uri $Connector -Method Post -body $messageCard -ContentType "application/json" -TimeoutSec 60 | Out-Null
            $result | Out-Null
        }
    }
    
    Write-Log -Name $Provider.Id -Context "MicrosoftTeams" -Message $Message.Summary -Status $($throttle ? $global:PlatformMessageStatus.Throttled : $global:PlatformMessageStatus.Transmitted) -Force

    return $throttle ? $global:PlatformMessageStatus.Throttled : $global:PlatformMessageStatus.Transmitted
}