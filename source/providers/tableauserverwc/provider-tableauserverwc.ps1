function Format-TableauServerWCFooter {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Message
    )
    $Message = $Message -replace "\s","&nbsp;"
    $Message = $Message -replace "\*","\*"
    return $Message
}

function global:Send-TableauServerWC {
 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object]$Message,
        [Parameter(Mandatory=$false)][string]$json
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Message = $json | ConvertFrom-Json -Depth 99
    # Write-Log -EntryType "Debug" -Target "Platform" -Action "Send-TableauServerWC-Message" -Message $Message -Force

    $provider = get-provider -id 'TableauServerWC'  # TODO: pass this in from Send-Message?

    $logEntry = read-log $provider.Id -Context "TableauServerWC" -Status "Sent" -Message $Message.Summary -Newest 1
    $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds : $null

    if (!$throttle) {
        
        # update the customizable welcome banner text
        $notification = Format-TableauServerWCFooter $Message.Summary
        Update-PostgresData -Database workgroup -Table global_settings -Column Value -Filter "Name = 'welcome_channel_server_footer'" -Value $notification

        # enable the show welcome banner preference for any user that has disabled it 
        Update-PostgresData -Database workgroup -Table site_user_prefs -Column show_welcome_screen -Value true -Filter "show_welcome_screen = '0'" -ErrorAction SilentlyContinue

    }
    else {
        $unthrottle = New-Timespan -Seconds ([math]::Round($Message.Throttle.TotalSeconds - ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds,0))
        Write-Host+ -NoTrace "Throttled $($provider.DisplayName) message"
        If ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {
            Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period: $($Message.Throttle.TotalSeconds) seconds"
            Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period remaining: $($unthrottle.TotalSeconds) seconds"
        }
    }
    
    Write-Log -Name $provider.Id -Context "TableauServerWC" -Message $Message.Summary -Status $($throttle ? "Throttled" : "Sent") -Force

    return 

}

function global:Get-TableauServerWC {
    return (Read-PostgresData -Database workgroup -Table global_settings -Filter "Name like 'welcome_channel_%'")
}