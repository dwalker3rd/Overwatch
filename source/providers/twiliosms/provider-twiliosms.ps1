<# 
.Synopsis
Twilio provider for Overwatch
.Link
https://www.twilio.com/docs/usage/tutorials/how-to-make-http-basic-request-twilio-powershell
#>


<# 
.Synopsis
Send a SMS message via Twilio
.Description
Send-TwilioSMS-Message posts a web request to a Twilio REST endpoint in order to send a SMS message from a Twilio phone 
number (associated with your Twilio account) to one or more phone numbers.
.Parameter From
A Twilio-powered phone number in E.164 format.
.Parameter To
One or more destination phone numbers in E.164 format.
.Parameter Message
If the message is more than 160 GSM-7 characters (or 70 UCS-2characters), Twilio will send the message as a segmented SMS and charge your account accordingly.
.Link
https://www.twilio.com/docs/usage/tutorials/how-to-make-http-basic-request-twilio-powershell
https://www.twilio.com/docs/glossary/what-e164
#>

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

function global:Send-TwilioSMS-Message {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$false)][object]$Message,
        [Parameter(Mandatory=$false)][string]$json,
        [Parameter(Mandatory=$false)][string]$From,
        [Parameter(Mandatory=$false)][object]$To
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Message = $json | ConvertFrom-Json -Depth 99
    # Write-Log -EntryType "Debug" -Target "Platform" -Action "Send-TwilioSMS-Message" -Message $Message -Force

    $provider = get-provider -id "TwilioSMS" # TODO: pass this in from Send-Message?
    if (!$From) {$From = $provider.Config.From}
    if (!$To) {$To = $(get-contact).Phone}

    $result = @()
    foreach ($t in $To) {
        $params = @{ To = $t; From = $From; Body = $Message.Summary }

        $logEntry = read-log $Provider.Id -Context "SMS" -Action $t -Status "Sent" -Message $Message.Summary -Newest 1
        $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds : $null

        if (!$throttle) {
            $result += Invoke-WebRequest $provider.Config.RestEndpoint -Method Post -Credential $provider.Config.Credentials -Body $params | ConvertFrom-Json 
        }
        else {
            $unthrottle = New-Timespan -Seconds ([math]::Round($Message.Throttle.TotalSeconds - ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds,0))
            Write-Host+ -NoTrace "Throttled $($Provider.DisplayName) message to $($To)"
            If ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period: $($Message.Throttle.TotalSeconds) seconds"
                Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period remaining: $($unthrottle.TotalSeconds) seconds"
            }
        }
        
        Write-Log -Name $Provider.Id -Context "SMS" -Action $t -Message $Message.Summary -Status $($throttle ? "Throttled" : "Sent") -Force
    
    }

    return
}