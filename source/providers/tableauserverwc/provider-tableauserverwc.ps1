function global:Send-TableauServerWC {
 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object]$Message,
        [Parameter(Mandatory=$false)][string]$json
    )

    $Message = $json | ConvertFrom-Json -Depth 99

    $provider = get-provider -id 'TableauServerWC'  # TODO: pass this in from Send-Message?
    
    # replace spaces with the html non-breaking space (for human readability) and escape the asterisk
    $Message.Summary = $Message.Summary.replace(" ","&nbsp;") -replace "\*","\*"

    Set-TableauServerWCMessage -Message $Message.Summary
    
    Write-Log -Context "Provider.TableauServerWC" -Name $provider.Id -Message $Message.Summary -Status $global:PlatformMessageStatus.Transmitted -Force

    return $global:PlatformMessageStatus.Transmitted

}

function global:Get-TableauServerWC {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $env:COMPUTERNAME
    )

    $dataRows = Read-PostgresData -Server $Server -Database workgroup -Table global_settings -Filter "Name like 'welcome_channel_%'"
    $dataRows | Add-Member -NotePropertyName Server -NotePropertyValue $Server

    # replace the html non-breaking space with spaces and unescape the asterisk
    $dataRows[1].value = ($dataRows[1].value) -replace("&nbsp;","X") -replace "\\",""

    return $dataRows
}

function global:Get-TableauServerWCMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $env:COMPUTERNAME
    )

    $dataRows = Get-TableauServerWC -Server $Server
    return $dataRows[1].value
    
}

function global:Set-TableauServerWCMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $env:COMPUTERNAME,
        [Parameter(Mandatory=$true)][string]$Message
    )

    # update the customizable welcome banner text
    $result = Update-PostgresData -Server $Server -Database workgroup -Table global_settings -Column Value -Filter "Name = 'welcome_channel_server_footer'" -Value $Message
    $result | Out-Null

    # enable the show welcome banner preference for any user that has disabled it 
    $result = Update-PostgresData -Server $Server -Database workgroup -Table site_user_prefs -Column show_welcome_screen -Value true -Filter "show_welcome_screen = '0'" -ErrorAction SilentlyContinue
    $result | Out-Null

}