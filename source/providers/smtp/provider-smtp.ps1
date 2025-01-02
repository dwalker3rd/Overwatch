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

function global:Send-SMTP {
 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$From,
        [Parameter(Mandatory=$false)][string[]]$To, 
        [Parameter(Mandatory=$false)][string]$Subject,
        [Parameter(Mandatory=$false)][string]$Body,
        [Parameter(Mandatory=$false)][ValidateSet("HTML", "Text")][string]$BodyFormat = "HTML",
        [Parameter(Mandatory=$false)][object]$Message,
        [Parameter(Mandatory=$false)][string]$json
    )

    $Message = $json | ConvertFrom-Json -Depth 99

    $provider = get-provider -id 'SMTP'
    $providerCredentials = Get-Credentials $provider.Id
    $From = ![string]::IsNullOrEmpty($From) ? $From : (![string]::IsNullOrEmpty($provider.Config.From) ? $provider.Config.From : $providerCredentials.UserName)
    if (!$To) {$To = [array]($(get-contact).Email)}
    if (!$Subject) {$Subject = $Message.Subject}

    $builder = New-Object MimeKit.BodyBuilder
    if (![string]::IsNullOrEmpty($Body)) {
        switch ($BodyFormat) {
            "HTML" {$builder.HtmlBody += $Body}
            "Text" {$builder.TextBody += $Body}
        }
    }
    else {
        foreach ($section in $Message.Sections) {
            foreach ($fact in $section.Facts) {
                $tab = Format-Leader -Character " " -Length 20 -Adjust ((("$($fact.name):").Length))
                $builder.TextBody += $fact.name ? "$($fact.name):$($tab)$($fact.value)`n" : $fact.value
                $builder.HtmlBody += $fact.name ? "<pre><b>$($fact.name)</b>:$($tab)$($fact.value)</pre>" : "<pre>$($fact.value)</pre>"
            }
        }
    }

    $SMTP = New-Object MailKit.Net.Smtp.SmtpClient
    $SMTPMessage = New-Object MimeKit.MimeMessage
    $SMTPMessage.From.Add($From)
    foreach ($emailAddress in $To) {
        $SMTPMessage.To.Add($emailAddress)
    }
    $SMTPMessage.Subject = $Subject
    $SMTPMessage.Body = $builder.ToMessageBody()

    $logEntry = read-log $provider.Id -Context "Provider.SMTP" -Action $To[0] -Status $global:PlatformMessageStatus.Transmitted -Message $Message.Summary -Newest 1
    $throttle = $logEntry -and $logEntry.Message -eq $Message.Summary ? ([datetime]::Now - $logEntry.TimeStamp).TotalSeconds -le $Message.Throttle.TotalSeconds : $null

    if (!$throttle) {
        $SMTP.Connect($provider.Config.Server,$provider.Config.Port, [MailKit.Security.SecureSocketOptions]::StartTls)
        $SMTP.Authenticate($providerCredentials)
        $SMTP.Send($SMTPMessage) | Out-Null
        $SMTP.Disconnect($true)
        $SMTP.Dispose()
    }
    
    Write-Log -Context "Provider.SMTP" -Name $provider.Id -Action $To[0] -Message $Message.Summary -Status $($throttle ? $global:PlatformMessageStatus.Throttled : $global:PlatformMessageStatus.Transmitted) -Force

    return $throttle ? $global:PlatformMessageStatus.Throttled : $global:PlatformMessageStatus.Transmitted

}