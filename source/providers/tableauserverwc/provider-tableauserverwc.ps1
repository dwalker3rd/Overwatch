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

    $Message = $json | ConvertFrom-Json -Depth 99

    $provider = get-provider -id 'TableauServerWC'  # TODO: pass this in from Send-Message?
 
    # update the customizable welcome banner text
    $notification = Format-TableauServerWCFooter $Message.Summary
    Update-PostgresData -Database workgroup -Table global_settings -Column Value -Filter "Name = 'welcome_channel_server_footer'" -Value $notification

    # enable the show welcome banner preference for any user that has disabled it 
    Update-PostgresData -Database workgroup -Table site_user_prefs -Column show_welcome_screen -Value true -Filter "show_welcome_screen = '0'" -ErrorAction SilentlyContinue
    
    Write-Log -Name $provider.Id -Context "TableauServerWC" -Message $Message.Summary -Status $global:PlatformMessageStatus.Transmitted -Force

    return $global:PlatformMessageStatus.Transmitted

}

function global:Get-TableauServerWC {
    return (Read-PostgresData -Database workgroup -Table global_settings -Filter "Name like 'welcome_channel_%'")
}