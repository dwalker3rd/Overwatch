<# 
.Synopsis
Microsoft Teams provider for Overwatch
.Link
https://docs.microsoft.com/en-us/outlook/actionable-messages/message-card-reference
#>

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

    # $messageCard = Build-MessageCard -Title $Message.Title -Text $($Message.Text ? $Message.Text : " ") -Sections $Message.Sections

    $logEntry = read-log $Provider.Id -Context "Provider.MicrosoftTeams" -Status $global:PlatformMessageStatus.Transmitted -Message $Message.Summary -Newest 1
    $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds :  $null

    $messageCard = ConvertTo-Json -Depth 8 `
    @{
        context = "https://schema.org/extensions"
        type = "MessageCard"
        title = $Message.Title
        text = $Message.Text ? $Message.Text : " "
        sections = $Message.Sections
    }

    if (!$throttle) {
        foreach ($connector in $provider.Config.Connector.$($Message.Type)) {
            $result = Invoke-RestMethod -uri $Connector -Method Post -body $messageCard -ContentType "application/json" -TimeoutSec 60 | Out-Null
            $result | Out-Null
        }
    }
    
    Write-Log -Context "Provider.MicrosoftTeams" -Name $Provider.Id -Message $Message.Summary -Status $($throttle ? $global:PlatformMessageStatus.Throttled : $global:PlatformMessageStatus.Transmitted) -Force

    return $throttle ? $global:PlatformMessageStatus.Throttled : $global:PlatformMessageStatus.Transmitted
}