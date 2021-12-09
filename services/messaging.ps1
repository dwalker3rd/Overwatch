function global:Send-Message {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][object]$Message
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $json = $Message | ConvertTo-Json -Depth 99
    Write-Log -EntryType "Debug" -Action "Send-Message" -Target "Platform" -Message $json

    Get-Provider | Where-Object {$_.Category -eq 'Messaging'} | ForEach-Object {
        if ($_.Config.MessageType -contains $Message.Type) {
            Invoke-Expression "Send-$($_.Id)-Message -json '$($json)'"
        }
    }
    
}

function global:Send-PlatformStatusMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [Parameter(Mandatory=$false)][PlatformStatus]$PlatformStatus = (Get-PlatformStatus),
        [switch]$ShowAll,
        [switch]$NoThrottle
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    Write-Log -EntryType "Debug" -Action "Send-PlatformStatusMessage" -Target "Platform" -Message ($MessageType | ConvertTo-Json)

    # $platformStatus = Get-PlatformStatus
    # $platformTopology = Get-PlatformTopology

    $sections = @(
        @{
            ActivityTitle = $global:Platform.DisplayName
            ActivitySubtitle = "Instance: $($global:Platform.Instance)"
            ActivityText = "[$($global:Platform.Uri)]($($global:Platform.Uri))"
            ActivityImage = $global:Platform.Image
            Facts = @(@{
                name = "$($global:Platform.Name)"
                value = "**$($PlatformStatus.RollupStatus.ToUpper())**"
            })
        }
    )

    foreach ($node in (Get-PlatformTopology nodes -Offline -Keys)) {

        $serverInfo = Get-ServerInfo -ComputerName $node

        $section = @{
            ActivityTitle = "**$($node.ToUpper())**"
            ActivitySubTitle = "$($serverInfo.WindowsProductName)"
            ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
            ActivityImage = "$($global:Location.Images)/serverOffline500.png"
            Facts = @(
                foreach ($component in (Get-PlatformTopology nodes.$node.components -Keys)) {
                    @{
                        name = $component
                        value = "**OFFLINE**"
                    }
                    @{
                        name = "Source"
                        value = "Requested by **$($global:Product.Name)**"
                    }
                }
            )
        }
        $sections += $section

    }

    # if (!$PlatformStatus.IsOK -or $ShowAll) {
        
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
                    ActivitySubTitle = "$($serverInfo.WindowsProductName), $($serverInfo.Model)"
                    ActivityText = "Performance: $($global:NumberWords.($serverInfo.NumberOfLogicalProcessors.ToString())) ($($serverInfo.NumberOfLogicalProcessors)) cores at $($cpuUtil.Text) utilization; $($memAvailable.Text) of $($memTotal) available"
                    ActivityImage = "$($global:Location.Images)/serverOnline.png"
                    Facts = $facts
                }
                $sections += $section
            }
        }

    # }

    $msg = @{
        Sections = $sections
        Title = $global:Product.TaskName
        Text = $global:Product.Description
        Type = $MessageType
        Summary = "Current status for $($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) is $($PlatformStatus.RollupStatus.ToUpper())"
        Subject = "Current status for $($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) is $($PlatformStatus.RollupStatus.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
    }

    Send-Message -Message $msg

    return

}

function global:Send-AsyncJobMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Id,
        [Parameter(Mandatory=$false)][string]$Context,
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Information,
        [switch]$NoThrottle
    )
    $asyncJob = Get-AsyncJob $Id

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $product = $Context ? (Get-Product $Context) : $global:Product
    $serverInfo = Get-ServerInfo
    
    $status = $asyncJob.statusMessage -replace '(\.*\s*)$'
    if ($status -match '\b(\w+)$') {$status = $status -replace $Matches[1],"**$($Matches[1].ToUpper())**"}

    $facts = @(
        @{name = "Job"; value = "$($asyncJob.jobType), ID: $($asyncJob.id), Async"}
        @{name = "Status"; value = "$($status)"}
        if ($asyncJob.completedAt) {
            @{name = "Completed "; value = $epoch.AddSeconds($asyncJob.completedAt/1000).ToString('u')}
        } 
        elseif ($asyncJob.updatedAt) {                  
            if ($asyncJob.progress -gt 0) {
                @{name = "Progress"; value = "$($asyncJob.progress)% complete"} 
            }
            @{name = "Updated"; value = $epoch.AddSeconds($asyncJob.updatedAt/1000).ToString('u')}    
        }
        elseif ($status -ne "Queued") {
            @{name = "Started"; value = $epoch.AddSeconds($asyncJob.createdAt/1000).ToString('u')}
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
        Summary = "Status of AsyncJob $($asyncJob.id) ($($asyncJob.jobType)) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)): $($status.ToUpper())"
        Subject = "Status of AsyncJob $($asyncJob.id) ($($asyncJob.jobType)) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)): $($status.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
    }

    Send-Message -Message $msg

    return

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $serverInfo = Get-ServerInfo

    $task = Get-PlatformTask -Id $Id
    $Status = $Status ? $Status : $task.Status
    # if ($Status -match '\b(\w+)$') {$Status = $Status -replace $Matches[1],"**$($Matches[1].ToUpper())**"}

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
        Text = $(Get-Product -Id $task.ProductId).Description 
        Type = $MessageType
        Summary = "Status of $($Id) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)): $($Status.ToUpper())"
        Subject = "Status of $($Id) on $($serverInfo.DisplayName) (Instance: $($global:Platform.Instance)): $($Status.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
    }

    Send-Message -Message $msg

    return

}

function global:Send-PlatformEventMessage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][object]$MessageType = $PlatformMessageType.Alert,
        [Parameter(Mandatory=$false)][PlatformStatus]$PlatformStatus = (Get-PlatformStatus),
        [switch]$Reset,
        [switch]$NoThrottle
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # $serverInfo = Get-ServerInfo
    # $platformStatus = Get-PlatformStatus

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
        Title = $global:Product.TaskName
        Text = $global:Product.Description
        Type = $MessageType
        Summary = "$($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) $($PlatformStatus.Event.ToUpper()) $($be) $($PlatformStatus.EventStatus.ToUpper())"
        Subject = "$($global:Platform.DisplayName) (Instance: $($global:Platform.Instance)) $($PlatformStatus.Event.ToUpper()) $($be) $($PlatformStatus.EventStatus.ToUpper())"
        Throttle = $NoThrottle ? [timespan]::Zero : (New-TimeSpan -Minutes 15)
    }

    Send-Message -Message $msg

    return

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

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    # $now = Get-Date
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
    }

    Send-Message -Message $msg

    return

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
        ActivityTitle = $serverInfo.WindowsProductName
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
        Summary = "$($OS.DisplayName) $($Event) $($Status) on $($serverInfo.DisplayName)"
        Subject = "$($OS.DisplayName) $($Event) $($Status) on $($serverInfo.DisplayName)"
        Throttle = $NoThrottle ? [timespan]::Zero : [timespan]::Zero
    }

    Send-Message -Message $msg

    return

}