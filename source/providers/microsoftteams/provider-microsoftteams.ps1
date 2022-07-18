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

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Message = $json | ConvertFrom-Json -Depth 99
    # Write-Log -EntryType "Debug" -Target "Platform" -Action "Send-MicrosoftTeams-Message" -Message $Message -Force

    $provider = get-provider -id "MicrosoftTeams"  # TODO: pass this in from Send-Message?

    $messageCard = Build-MessageCard -Title $Message.Title -Text $($Message.Text ? $Message.Text : " ") -Sections $Message.Sections

    $logEntry = read-log $Provider.Id -Context "MicrosoftTeams" -Status "Sent" -Message $Message.Summary -Newest 1
    $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds :  $null

    if (!$throttle) {
        foreach ($connector in $provider.Config.Connector.$($Message.Type)) {
            Invoke-RestMethod -uri $Connector -Method Post -body $messageCard -ContentType "application/json" -TimeoutSec 60 | Out-Null
        }
    }
    else {
        $unthrottle = New-Timespan -Seconds ([math]::Round($Message.Throttle.TotalSeconds - ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds,0))
        Write-Host+ -NoTrace "Throttled $($Provider.DisplayName) message"
        If ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {
            Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period: $($Message.Throttle.TotalSeconds) seconds"
            Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period remaining: $($unthrottle.TotalSeconds) seconds"
        }
    }
    
    Write-Log -Name $Provider.Id -Context "MicrosoftTeams" -Message $Message.Summary -Status $($throttle ? "Throttled" : "Sent") -Force

    return
}