<# 
.Synopsis
SMTP provider for Overwatch
#>


<# 
.Synopsis
Sends an email message via SMTP.
.Description
Sends an email message via SMTP.
.Parameter From
The email address from which the message will be sent.
.Parameter To
The email address[es] to which the email will be sent.
.Parameter Subject
The subject of the email message.
.Parameter Body
The content of the email message.
.Parameter Message
The message object used by the Overwatch messaging service.
.Parameter Json
The message object used by the Overwatch messaging service serialized into JSON.
#>

$mailKit = Get-Package -Name MailKit
$mimeKit = Get-Package -Name MimeKit
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\$($mailKit.Name).$($mailKit.Version)\lib\net48\MailKit.dll"
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\$($mimeKit.Name).$($mimeKit.Version)\lib\net48\MimeKit.dll"

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

function global:Send-SMTP {
 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$From,
        [Parameter(Mandatory=$false)][string]$To, 
        [Parameter(Mandatory=$false)][string]$Subject,
        [Parameter(Mandatory=$false)][string]$Body,
        [Parameter(Mandatory=$false)][object]$Message,
        [Parameter(Mandatory=$false)][string]$json
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Message = $json | ConvertFrom-Json -Depth 99
    # Write-Log -EntryType "Debug" -Target "Platform" -Action "Send-SMTP-Message" -Message $Message -Force

    $provider = get-provider -id 'SMTP'  # TODO: pass this in from Send-Message?
    if (!$From) {$From = $provider.Config.From}
    if (!$To) {$To = $(get-contact).Email}
    if (!$Subject) {$Subject = $Message.Subject}

    $builder = New-Object MimeKit.BodyBuilder
    foreach ($section in $Message.Sections) {
        foreach ($fact in $section.Facts) {
            $tab = Format-Leader -Character " " -Length 20 -Adjust ((("$($fact.name):").Length))
            $builder.TextBody += $fact.name ? "$($fact.name):$($tab)$($fact.value)`n" : $fact.value
            $builder.HtmlBody += $fact.name ? "<pre><b>$($fact.name)</b>:$($tab)$($fact.value)</pre>" : "<pre>$($fact.value)</pre>"
        }
    }

    $SMTP = New-Object MailKit.Net.Smtp.SmtpClient
    $SMTPMessage = New-Object MimeKit.MimeMessage
    $SMTPMessage.From.Add($From)
    $SMTPMessage.To.Add($To)
    $SMTPMessage.Subject = $Subject
    $SMTPMessage.Body = $builder.ToMessageBody()
    $SMTPMessage.HTML

    # $SMTPClient = New-Object Net.Mail.SmtpClient($Provider.Config.Server,$Provider.Config.Port)
    # $SMTPClient.EnableSsl = $Provider.Config.UseSSL
    # $SMTPClient.Credentials = $Provider.Config.Credentials

    $logEntry = read-log $Provider.Id -Context "SMTP" -Action $To -Status "Sent" -Message $Message.Summary -Newest 1
    $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds : $null

    if (!$throttle) {
        # $result += $SMTPClient.Send($From, $To, $Subject, $Body)
        $SMTP.Connect($Provider.Config.Server,$Provider.Config.Port, [MailKit.Security.SecureSocketOptions]::StartTls)
        $SMTP.Authenticate($Provider.Config.Credentials)
        $SMTP.Send($SMTPMessage)
        $SMTP.Disconnect($true)
        $SMTP.Dispose()
    }
    else {
        $unthrottle = New-Timespan -Seconds ([math]::Round($Message.Throttle.TotalSeconds - ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds,0))
        Write-Host+ -NoTrace "Throttled $($Provider.DisplayName) message to $($To)"
        If ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {
            Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period: $($Message.Throttle.TotalSeconds) seconds"
            Write-Host+ -NoTrace -ForegroundColor DarkYellow "VERBOSE: Throttle period remaining: $($unthrottle.TotalSeconds) seconds"
        }
    }
    
    Write-Log -Name $Provider.Id -Context "SMTP" -Action $To -Message $Message.Summary -Status $($throttle ? "Throttled" : "Sent") -Force

    return 

}