function global:Disable-Messaging {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][timespan]$Duration = $global:PlatformMessageDisabledTimeout,
        [switch]$Notify,
        [switch]$Quiet,
        [switch]$Reset
    )

    if ((IsMessagingDisabled) -and !$Reset) {
        $_platformMessageStatus = Get-MessagingStatus
        if (!$Quiet) { Show-MessagingStatus -Already}
        Write-Host+ -NoTrace "Use -Reset to reset the countdown timer" -ForegroundColor Gray
        return
    }

    if ($Duration.TotalMilliseconds -eq 0) { throw("Duration must be greater than 0.")}

    $now = Get-Date -AsUTC
    $expiry = $now + $Duration
    $_platformMessageStatus = @{
        Status = $global:PlatformMessageStatus.Disabled
        Timestamp = $now
        Expiry = $expiry
    }
    $_platformMessageStatus | Write-Cache platformMessageStatus

    Write-Log -EntryType "Warning" -Action "Disable" -Target "Messaging" -Status $global:PlatformMessageStatus.Disabled -Message "Messaging $($global:PlatformMessageStatus.Disabled) until $expiry" -Force
    if (!$Quiet) { Show-MessagingStatus }
    if ($Notify) { Send-MessagingStatus -NoThrottle | Out-Null }

    return

}

function global:Enable-Messaging {

    [CmdletBinding()]
    param (
        [switch]$Notify,
        [switch]$Quiet,
        [switch]$Force
    )

    if ((IsMessagingEnabled) -and !$Force) {
        $_platformMessageStatus = Get-MessagingStatus
        Write-Host+ -NoTrace "Messaging is already",$_platformMessageStatus.Status.ToUpper() -ForegroundColor Gray,($_platformMessageStatus.Status -eq "Disabled" ? "DarkYellow" : "DarkGreen")
        Write-Host+ -NoTrace "Use -Force to $($_platformMessageStatus.Status.ToLower() -Replace 'd$','') messaging again." -ForegroundColor Gray
        return
    }

    $now = Get-Date -AsUTC
    $_platformMessageStatus = @{
        Status = $global:PlatformMessageStatus.Enabled
        Timestamp = $now
    }
    $_platformMessageStatus | Write-Cache platformMessageStatus

    Write-Log -EntryType "Information" -Action "Enable" -Target "Messaging" -Status $global:PlatformMessageStatus.Enabled -Message "Messaging $($global:PlatformMessageStatus.Enabled.ToUpper())" -Force
    if (!$Quiet) { Show-MessagingStatus }
    if ($Notify) { Send-MessagingStatus -NoThrottle | Out-Null }

    return

}
function global:IsMessagingDisabled {
    $_platformMessageStatus = Get-MessagingStatus
    $_platformStatus = Get-PlatformStatus -CacheOnly
    if ($_platformMessageStatus.Status -eq $global:PlatformMessageStatus.Disabled) {
        if ((Get-Date -AsUTC) -ge $_platformMessageStatus.Expiry -or $_platformStatus.Intervention) {
            Enable-Messaging -Quiet
            return $false
        }
        return $true
    }
    return $false
}
function global:IsMessagingEnabled {
    $_platformMessageStatus = Get-MessagingStatus
    return $_platformMessageStatus.Status -eq $global:PlatformMessageStatus.Enabled
}
function global:Get-MessagingStatus {
    return (Read-Cache platformMessageStatus)
}
function global:Show-MessagingStatus {

    param(
        [switch]$Already
    )

    if (isMessagingDisabled) {

        $_platformMessageStatus = Get-MessagingStatus
        
        $expiry = $_platformMessageStatus.Expiry
        $timeRemaining = $expiry - (Get-Date)
        $minutesAsString = [math]::Floor($timeRemaining.TotalMinutes) -eq 0 ? "" : "$([math]::Floor($timeRemaining.TotalMinutes)) minute$($timeRemaining.Minutes -eq 1 ? '' : 's')"
        $secondsAsString = $timeRemaining.Seconds -eq 0 ? "" : "$($timeRemaining.Seconds) second$($timeRemaining.Seconds -eq 1 ? '' : 's')"
        
        $messagingCountdown = "Messaging will be re-enabled in $minutesAsString"
        if (![string]::IsNullOrEmpty($minutesAsString) -and ![string]::IsNullOrEmpty($secondsAsString)) { 
            $messagingCountdown += " "
        }
        $messagingCountdown += $secondsAsString

        if ([string]::IsNullOrEmpty($minutesAsString) -and [string]::IsNullOrEmpty($secondsAsString)) {
            Enable-Messaging
        }
        else {
            Write-Host+ -NoTrace "Messaging$($Already ? " is already" : $null)",$_platformMessageStatus.Status.ToUpper(),"until $expiry" -ForegroundColor Gray,DarkYellow,Gray
            Write-Host+ -NoTrace "$messagingCountdown" -ForegroundColor Gray
        }
    }  
    else {
        $_platformMessageStatus = Get-MessagingStatus
        Write-Host+ -NoTrace "Messaging",$_platformMessageStatus.Status.ToUpper() -ForegroundColor Gray,DarkGreen
    }  

}

function global:Send-Message {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][object]$Message,
        [switch]$Force
    )

    $json = $Message | ConvertTo-Json -Depth 99
    Write-Log -EntryType "Debug" -Action "Send-Message" -Target $Message.Source

    if ((IsMessagingDisabled) -and $Message.Type -notin $global:PlatformMessageTypeAlwaysSend.Values -and !$Force) {
        Write-Log -EntryType "Information" -Action "Send" -Target $Message.Source -Status $global:PlatformMessageStatus.Disabled -Message "Messaging $($global:PlatformMessageStatus.Disabled.ToUpper())" -Force
        return $global:PlatformMessageStatus.Disabled
    }

    $status = @()
    $providerAndStatus = @()
    Get-Provider | Where-Object {$_.Category -eq 'Messaging'} | ForEach-Object {
        if ($_.Config.MessageType -contains $Message.Type) {
            $status += Invoke-Expression "Send-$($_.Id) -json '$($json)'"
            $providerAndStatus += "$($_.Id):$result"
        }
    }
    $status = $status | Sort-Object -Unique
    if (!$status) { return "Ignored"}
    if ($status.Count -gt 1) { $status = $providerAndStatus -join ", " }

    return $status
    
}

function global:Send-PlatformStatusMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus),
        [switch]$ShowAll,
        [switch]$NoThrottle,
        [switch]$ShowOffline
    )

    $facts = @()
    $facts += @{
        name = "$($global:Platform.Name)"
        value = "**$($PlatformStatus.RollupStatus.ToUpper())**"        
    }

    $sections = @(
        @{
            ActivityTitle = $global:Platform.DisplayName
            ActivitySubtitle = "Instance: $($global:Platform.Instance)"
            ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
            ActivityImage = $global:Platform.Image
            Facts = $facts
        }
    )

    foreach ($node in (Get-PlatformTopology nodes -Online -Keys)) {

        $serverInfo = Get-ServerInfo -ComputerName $node

        $serverPerf = Measure-ServerPerformance $node -MaxSamples 5
        $cpuUtil = $serverPerf | Where-Object {$_.Counter -eq "PercentProcessorTime"}
        $memTotal = "$([math]::Round($serverInfo.TotalPhysicalMemory/1gb,0)) GB"
        $memAvailable = $serverPerf | Where-Object {$_.Counter -eq "AvailableBytes"}
        # $memUtil = [math]::Round((($memTotal-$memAvailable.Value)/$memTotal)*100,0)

        $facts = @(

            # status facts are platform-dependent
            Build-StatusFacts -PlatformStatus $PlatformStatus -Node $node -ShowAll:$ShowAll

        )  

        if ($facts) {
            $section = @{
                ActivityTitle = "**$($node)**"
                ActivitySubTitle = "$($serverInfo.OSName), $($serverInfo.Model)"
                ActivityText = "Performance: $($serverInfo.NumberOfLogicalProcessors) cores at $($cpuUtil.Text) utilization; $($memAvailable.Text) of $($memTotal) available"
                ActivityImage = $global:OS.Image
                Facts = $facts
            }
            $sections += $section
        }
    }    

    if ($ShowOffline) {
        $osImageExtension = ($global:OS.Image -split "\.")[-1]
        $osImageOffline = $global:OS.Image -replace "\.$osImageExtension","_offline.$osImageExtension"
        foreach ($node in (Get-PlatformTopology nodes -Offline -Keys)) {

            $serverInfo = Get-ServerInfo -ComputerName $node

            $section = @{
                ActivityTitle = "**$($node.ToUpper())**"
                ActivitySubTitle = "$($serverInfo.OSName)"
                ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
                ActivityImage = $osImageOffline
                Facts = @(
                    foreach ($component in (Get-PlatformTopology nodes.$node.components -Keys)) {
                        @{
                            name = $component
                            value = "**OFFLINE**"
                        }
                    }
                )
            }
            $sections += $section

        } 
    }  
    
    $msg = @{
        Sections = $sections
        Title = $global:Product.DisplayName
        Text = $global:Product.Description
        Type = $MessageType
        Summary = "Overwatch $MessageType`: $($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) is $($PlatformStatus.RollupStatus.ToUpper())"
        Subject = "Overwatch $MessageType`: $($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) is $($PlatformStatus.RollupStatus.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-PlatformStatusMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-PlatformJobMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Context,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )
    $platformJob = Get-PlatformJob $Id


    $product = $Context ? (Get-Product $Context) : $global:Product
    $serverInfo = Get-ServerInfo
    
    $status = $platformJob.statusMessage -replace '(\.*\s*)$'
    if ($status -match '\b(\w+)$') {$status = $status -replace $Matches[1],"**$($Matches[1].ToUpper())**"}

    $facts = @(
        @{name = "Job"; value = "$($platformJob.jobType), ID: $($platformJob.id)"}
        @{name = "Status"; value = "$($status)"}
        if ($platformJob.completedAt) {
            @{name = "Completed "; value = $epoch.AddSeconds($platformJob.completedAt/1000).ToString('u')}
        } 
        elseif ($platformJob.updatedAt) {                  
            if ($platformJob.progress -gt 0) {
                @{name = "Progress"; value = "$($platformJob.progress)% complete"} 
            }
            @{name = "Updated"; value = $epoch.AddSeconds($platformJob.updatedAt/1000).ToString('u')}    
        }
        elseif ($status -ne "Queued") {
            @{name = "Started"; value = $epoch.AddSeconds($platformJob.createdAt/1000).ToString('u')}
        }            
    )

    $msg = @{
        Sections = @(
            @{
                ActivityTitle = $global:Platform.DisplayName
                ActivitySubtitle = "Instance: $($global:Platform.Instance)"
                ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
                ActivityImage = $global:Platform.Image
                Facts = $facts
            }
        )
        Title = $product.DisplayName
        Text = $product.Description 
        Type = $MessageType
        Summary = "Status of PlatformJob $($platformJob.id) ($($platformJob.jobType)) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)): $($status.ToUpper())"
        Subject = "Status of PlatformJob $($platformJob.id) ($($platformJob.jobType)) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)): $($status.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-PlatformJobMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-TaskMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Status,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )
    
    $serverInfo = Get-ServerInfo

    $task = Get-PlatformTask -Id $Id
    if ($null -eq $task -or $task[0].Id -ne $Id -or !$task[0].Installed) {
        $task = Get-Catalog -Type Product -Id $Id | Select-Object -Property Id,Name,Description,status
        $task | Add-Member -NotePropertyName ProductId -NotePropertyValue $task.Id
        $task.Status = "NotInstalled"
    }
    $Status = $Status ? $Status : $task.Status

    $facts = @(
        @{name = "Status"; value = $Status -match "\b(\w+)$" ? ($Status -replace $Matches[1],"**$($Matches[1].ToUpper())**") : "$($Status)"}
        if ($Message) {
            @{name = "Message"; value = $Message}
        }
        @{name  = $Status; value = (Get-Date).ToString('u')}
        if ($Status -eq 'Completed') {
            if ($task.ScheduledTaskInfo.NextRunTime) {
                @{name  = "NextRunTime"; value = $task.ScheduledTaskInfo.NextRunTime.ToString('u')}
            }
        }
    )

    $msg = @{
        Sections = @(
            @{
                ActivityTitle = $global:Platform.DisplayName
                ActivitySubtitle = "Instance: $($global:Platform.Instance)"
                ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
                ActivityImage = $global:Platform.Image
                Facts = $facts
            }
        )
        Title = $task.Name
        Text = $task.Description 
        Type = $MessageType
        Summary = "Overwatch $MessageType`: $($Id) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)) is $($Status.ToUpper())"
        Subject = "Overwatch $MessageType`: $($Id) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)) is $($Status.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-TaskMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-PlatformEventMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Alert,
        [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus),
        [switch]$Reset,
        [switch]$NoThrottle
    )

    $be = 
        switch ($PlatformStatus.EventStatus) {
            $PlatformEventStatus.InProgress {'is'}
            $PlatformEventStatus.Testing {'is'}
            Default {'has'}
        }

    if ($Reset) {
        $PlatformStatus.Event = "Status"
        $PlatformStatus.EventReason = "Event reset requested."
        $PlatformStatus.EventStatus = $PlatformEventStatus.Reset
        $PlatformStatus.EventCreatedBy = $global:Product.DisplayName
        $be = 'has been'
    }

    $facts = @(
        @{
            name = "Event"
            value =  "Platform **$($PlatformStatus.Event.ToUpper())** $($be) **$($PlatformStatus.EventStatus.ToUpper())**"
        }
        @{
            name = "Source"
            value = "Requested by **$($platformstatus.EventCreatedBy)**"
        }
        @{
            name = "Reason"
            value = $PlatformStatus.EventReason
        }
    )

    $msg = @{
        Sections = @(
            @{
                ActivityTitle = $global:Platform.DisplayName
                ActivitySubtitle = "Instance: $($global:Platform.Instance)"
                ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
                ActivityImage = $global:Platform.Image
                Facts = $facts
            }
        )
        Title = $global:Product.DisplayName
        Text = $global:Product.Description
        Type = $MessageType
        Summary = "Overwatch $MessageType`: $($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) $($PlatformStatus.Event.ToUpper()) $($be) $($PlatformStatus.EventStatus.ToUpper())"
        Subject = "Overwatch $MessageType`: $($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) $($PlatformStatus.Event.ToUpper()) $($be) $($PlatformStatus.EventStatus.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-PlatformEventMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-LicenseMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$License,
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Summary,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )

    $30days = New-TimeSpan -days 30
    $90days = New-TimeSpan -days 90

    $facts = @()
    $sections = @()

    $monitor = Get-Product Monitor

    $sectionMain = @{
        ActivityTitle = $global:Platform.Instance
        ActivitySubtitle = $global:Platform.DisplayName
        ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
        ActivityImage = $global:Platform.Image
        Facts = @(
            @{
                name = $Subject
                value = $Summary
            }
        )
    }
    $sections += $sectionMain

    foreach ($lic in $License) {

        $facts = @(

        
            if ($lic.numCores) {
                @{
                    name = "Units"
                    value = "$($lic.numCores) Cores"
                }
            }

            if ($lic.licenseExpired) {
                @{
                    name = "Expiration"
                    value = "**EXPIRED** on $($lic.expiration.ToString('d MMMM yyyy'))"
                }
            }
            elseif ($lic.licenseExpiry -le $90days) {
                @{
                    name = "Expiration"
                    value = "Expires in **$([math]::Round($lic.licenseExpiry.TotalDays,0)) days** on $($lic.expiration.ToString('d MMMM yyyy'))"
                }
            }
            else {
                @{
                    name = "Expiration"
                    value = "$($lic.expiration.ToString('d MMMM yyyy'))"
                }
            }
            if ($lic.maintenanceExpired) {
                @{
                    name = "Maintenance"
                    value = "**EXPIRED** on $($lic.maintenance.ToString('d MMMM yyyy'))"
                }
            }
            elseif ($lic.maintenanceExpiry -le $90days) {
                @{
                    name = "Maintenance"
                    value = "Expires in **$([math]::Round($lic.maintenanceExpiry.TotalDays,0)) days** on $($lic.maintenance.ToString('d MMMM yyyy'))"
                }
            }
            else {
                @{
                    name = "Maintenance"
                    value = "$($lic.maintenance.ToString('d MMMM yyyy'))"
                }
            }
        )

        $sectionLicense = @{
            ActivityTitle = "$($lic.product)"
            ActivitySubtitle = $lic.serial -replace "(.{4}-){3}","XXXX-XXXX-XXXX-"
            # ActivityText = "$($lic.numCores) cores"
            ActivityImage = "$($global:Location.Images)/key.png"
            Facts = $facts
        }
        $sections += $sectionLicense

    }

    $licenseExpiry30days = ($License.licenseExpiry | Measure-Object -Maximum).Maximum -le $30days
    $maintenanceExpiry30days = ($License.maintenanceExpiry | Measure-Object -Maximum).Maximum -le $30days

    $throttle = $licenseExpiry30days -or $maintenanceExpiry30days ? (New-TimeSpan -Days 1) : (New-TimeSpan -Days 7)
    $throttle = $ComplianceIssue ? (New-TimeSpan -Hours 1) : $throttle
    $throttle = $NoThrottle ? [timespan]::Zero : $throttle

    $msg = @{
        Title = $monitor.DisplayName
        Text = $monitor.Description
        Sections = $sections
        Type = $MessageType
        Summary = "$($Subject): $($Summary) on $($Platform.Name) ($($Platform.Instance))"
        Subject = $Subject
        Throttle = $throttle
        Source = "Send-LicenseMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-ServerStatusMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Event,
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][string]$Reason,
        [Parameter(Mandatory=$false)][string]$Comment,
        [Parameter(Mandatory=$false)][string]$User,
        [Parameter(Mandatory=$true)][datetime]$TimeCreated,
        [Parameter(Mandatory=$false)][object]$Level = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )

    $facts = @()
    $sections = @()

    $serverInfo = Get-ServerInfo -ComputerName $ComputerName
    $monitor = Get-Product Monitor

    $facts = @(
        @{name  = "Event"; value = "**$($Event.ToUpper())** $($global:OS.DisplayName) $($ComputerName.ToUpper())"}
        @{name  = "Status"; value = "**$($Status.ToUpper())** at $($TimeCreated.ToString('u'))"}
        if ($User) {
            @{name  = "User"; value = "Initiated by **$($User)**"}
        }
        @{name  = "Reason"; value = $Reason}
        if ($Comment) {
            @{name  = "Comment"; value = $Comment}
        }
    )

    $sectionMain = @{
        ActivityTitle = $serverInfo.OSName
        ActivitySubtitle = $serverInfo.DisplayName
        ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) Cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
        ActivityImage = $global:OS.Image
        Facts = $facts
    }
    $sections += $sectionMain

    $msg = @{
        Title = $monitor.DisplayName
        Text = $monitor.Description
        Sections = $sections
        Type = $Level
        Summary = "Overwatch $MessageType`: $($OS.DisplayName) $($Event) $($Status) on $($serverInfo.DisplayName)"
        Subject = "Overwatch $MessageType`: $($OS.DisplayName) $($Event) $($Status) on $($serverInfo.DisplayName)"
        Throttle = $NoThrottle ? [timespan]::Zero : [timespan]::Zero
        Source = "Send-ServerStatusMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-SslCertificateExpiryMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object]$Certificate,
        [switch]$NoThrottle
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $1day = New-TimeSpan -days 1
    $7days = New-TimeSpan -days 7
    $30days = New-TimeSpan -days 30

    $expiresInDays = $Certificate.NotAfter - $now

    $cn = $Certificate.Subject # .Replace("*.","")
    $cnShort = $cn.Split(",")[0].Replace("CN=","")

    $facts = @()
    $sections = @()

    $facts = @(
        @{
            name = "Subject" 
            value = $cn
        }
        @{
            name = "Issuer"
            value = $Certificate.Issuer.split(",")[0]
        }
        @{
            name = "SerialNumber"
            value = $Certificate.SerialNumber
        }
        @{
            name = "Thumbprint"
            value = $Certificate.Thumbprint
        }
        @{
            name = "Expiry"
            value = $Certificate.NotAfter
        }
        @{
            name = "Status"
            value = $expiresInDays -le 0 ? "Expired" : "Expires in $([math]::round($expiresInDays.TotalDays,0)) days"
        }
    )

    $sectionMain = @{
        ActivityTitle = $global:Platform.Instance
        ActivitySubtitle = $global:Platform.DisplayName
        ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
        ActivityImage = $global:Platform.Image
        Facts = $facts
    }
    $sections += $sectionMain

    $throttle = $expiresInDays -le $30days ? $1day : $7days
    $throttle = $NoThrottle ? [timespan]::Zero : $throttle

    $msg = @{
        Title = "Overwatch SSL Certificate Monitoring"
        Text = "A SSL certificate on $($Platform.Name) ($($Platform.Instance)) $($expiresInDays -le 0 ? "has expired" : "expires in $([math]::round($expiresInDays.TotalDays,0)) days")"
        Sections = $sections
        Type = $expiresInDays -le 0 ? $PlatformMessageType.Alert : $($expiresInDays -le $30days ? $PlatformMessageType.Warning : $PlatformMessageType.Information)
        Summary = "The `"$cnShort`" SSL certificate on $($Platform.Name) ($($Platform.Instance)) $($expiresInDays -le 0 ? "has expired" : "expires in $([math]::round($expiresInDays.TotalDays,0)) days")"
        Subject = "Overwatch SSL Certificate Monitoring"
        Throttle = $throttle
        Source = "Send-SSLCertificateExpiryMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-UserNotification {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Message,
        [switch]$NoThrottle
    )

    $msg = @{ 
        Type = $PlatformMessageType.UserNotification
        Summary = $Message
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-UserNotification"
    }

    return Send-Message -Message $msg

}

function global:Send-MessagingStatus {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = $($global:Product.Id),
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )

    $product = $Context ? (Get-Product $Context) : $global:Product
    $serverInfo = Get-ServerInfo

    $_platformMessageStatus = Get-MessagingStatus   
    $status = $_platformMessageStatus.Status
    $timestamp = $_platformMessageStatus.Timestamp

    $facts = @(
        @{name = "Messaging"; value = "**$($status.ToUpper())**"}
        @{name = "Timestamp"; value = $timestamp.ToString('u')}
    )

    if ($_platformMessageStatus.Status -eq "Disabled") {

        $_platformMessageStatus = Get-MessagingStatus
        $expiry = $_platformMessageStatus.Expiry

        $facts += @(
            @{name = "Expiry"; value = $expiry.ToString('u')}
        )
    }

    $summary = $subject = "Overwatch $MessageType`: Messaging on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)) is $statusMessage"

    $msg = @{
        Sections = @(
            @{
                ActivityTitle = $global:Platform.DisplayName
                ActivitySubtitle = "Instance: $($global:Platform.Instance)"
                ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
                ActivityImage = $global:Platform.Image
                Facts = $facts
            }
        )
        Title = $product.DisplayName
        Text = $product.Description 
        Type = $MessageType
        Summary = $summary
        Subject = $subject
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-MessagingStatus"
    }

    return Send-Message -Message $msg -Force

}

function global:Send-AzureUpdateMgmtMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = $($global:Product.Id),
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(Mandatory=$false)][string]$Reason,
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Alert,
        [switch]$NoThrottle
    )

    $be = $Status.ToLower().EndsWith("ing") ? "is" : "has"

    $product = $Context ? (Get-Product $Context) : $global:Product

    $facts = @(
        @{name = "Status"; value = "**$($Status.ToUpper())**"}
        @{name = "Command"; value = $Command}
        if ($Reason) { @{name = "Reason"; value = $Reason} }
    )

    $summary = $subject = "Overwatch $MessageType`: $($product.Id) on $($global:Platform.Instance) (Command: $Command) $be $($Status.ToUpper())"

    $msg = @{
        Sections = @(
            @{
                ActivityTitle = $global:Platform.DisplayName
                ActivitySubtitle = "Instance: $($global:Platform.Instance)"
                ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
                ActivityImage = $global:Platform.Image
                Facts = $facts
            }
        )
        Title = $product.DisplayName
        Text = $product.Description 
        Type = $MessageType
        Summary = $summary
        Subject = $subject
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
        Source = "Send-AzureUpdateMgmtMessage"
    }

    return Send-Message -Message $msg -Force

}

function global:Send-ServerInterventionMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Intervention,
        [switch]$NoThrottle
    )

    $sections = @()

    $serverInfo = Get-ServerInfo -ComputerName $ComputerName

    $facts = @(
        @{name  = "Message"; value = $Message}
    )

    $sectionMain = @{}
    $sectionMain = @{
        ActivityTitle = $serverInfo.OSName
        ActivitySubtitle = $serverInfo.DisplayName
        ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) Cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
        ActivityImage = (Get-OS -ComputerName $ComputerName).image
        Facts = $facts
    }

    $sections += $sectionMain

    $msg = @{
        Title = "Overwatch Monitor for Server Status"
        Text = "Monitors the status of remote Overwatch controllers."
        Sections = $sections
        Type = $MessageType
        Summary = "Overwatch $MessageType`: [$($serverInfo.DisplayName ?? $ComputerName.ToUpper())] $Message"
        Subject = "Overwatch $MessageType`: [$($serverInfo.DisplayName ?? $ComputerName.ToUpper())] $Message"
        Throttle = $NoThrottle ? [timespan]::Zero : [timespan]::Zero
        Source = "Send-ServerInterventionMessage"
    }

    return Send-Message -Message $msg

}

function global:Send-GenericMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$true,Position=0)][string]$Message,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )

    $sections = @()

    $_product = $Context ? (Get-Product $Context) : (Get-Product $global:Product.Id)
    $serverInfo = Get-ServerInfo -ComputerName $ComputerName

    $facts = @(
        @{name  = "Message"; value = $Message}
    )

    $sectionMain = @{}
    $sectionMain = @{
        ActivityTitle = $serverInfo.OSName
        ActivitySubtitle = $serverInfo.DisplayName
        ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) Cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
        ActivityImage = (Get-OS -ComputerName $ComputerName).image
        Facts = $facts
    }

    $sections += $sectionMain

    $msg = @{
        Title = $_product.DisplayName
        Text = $_product.Description
        Sections = $sections
        Type = $MessageType
        Summary = "Overwatch $MessageType`: [$($serverInfo.DisplayName ?? $ComputerName.ToUpper())] $Message"
        Subject = "Overwatch $MessageType`: [$($serverInfo.DisplayName ?? $ComputerName.ToUpper())] $Message"
        Throttle = $NoThrottle ? [timespan]::Zero : [timespan]::Zero
        Source = "Send-GenericMessage"
    }

    return Send-Message -Message $msg

}