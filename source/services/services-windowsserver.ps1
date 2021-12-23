function global:Measure-ServerPerformance {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][object]$Counters = $PerformanceCounters,
        [Parameter(Mandatory=$false)][int32]$MaxSamples = $PerformanceCounterMaxSamples,
        [Parameter(Mandatory=$false)][int32]$SampleInterval = $PerformanceMeasurementampleInterval
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Measurements = @()

    foreach ($node in $ComputerName) {

        foreach ($counter in $Counters) {

            $Measurement = New-Object -TypeName PerformanceMeasurement 

            $Measurement.Class = $counter.Class 
            $Measurement.Instance = $counter.Instance 
            $Measurement.Counter = $counter.Counter
            $Measurement.Name = $counter.Name
            $Measurement.Suffix = $counter.Suffix
            $Measurement.Factor = $counter.Factor
            $Measurement.SingleSampleOnly = $counter.SingleSampleOnly
            $Measurement.ComputerName = $node

            # single sample for all Measurement
            $queryResult = Get-CimInstance -ComputerName $node -Query "Select * from $($Measurement.Class)" 
            $queryResult = $Measurement.Instance ? ($queryResult | Where-Object Name -EQ $Measurement.Instance) : $queryResult
            $Measurement.Raw = ($queryResult.($Measurement.Counter) | Measure-Object -Sum).Sum
            $Measurement.TimeStamp += Get-Date

            if ($SampleInterval -gt 0) {Start-Sleep -Milliseconds $SampleInterval}
            
            # multiple samples for Measurement NOT marked as SingleSampleOnly 
            for ($i=1;$i -lt $MaxSamples;$i++) {
                if ($Measurement.SingleSampleOnly -ne "True") {
                    $queryResult = Get-CimInstance -ComputerName $node -Query "Select $($Measurement.Counter) from $($Measurement.Class)" 
                    $queryResult = $Measurement.Instance ? ($queryResult | Where-Object Name -EQ $Measurement.Instance) : $queryResult
                    $Measurement.Raw = ($queryResult.($Measurement.Counter) | Measure-Object -Sum).Sum
                    $Measurement.TimeStamp += Get-Date
                }
                if ($SampleInterval -gt 0) {Start-Sleep -Milliseconds $SampleInterval}
            }

            $Measurement.Value = [math]::Round($($Measurement.Raw | Measure-Object -Average).Average * $Measurement.Factor,0)
            $Measurement.Text = "$($Measurement.Value)$($Measurement.Suffix)"

            $Measurements += $Measurement

        }
        
    }

    return $Measurements

}

function global:Get-ServerInfo {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    ) 

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    # if ($(Get-Cache serverinfo).Exists()) {
    #     Write-Information  "Read-Cache serverinfo"
    #     $serverInfo = Read-Cache serverinfo
    #     if ($serverInfo) {return $serverInfo}
    # }

    $serverInfo = @()
    foreach ($node in $ComputerName) {

        $Win32_ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $node | 
            Select-Object -Property *, @{Name="DomainRoleString"; Expression = {[Microsoft.PowerShell.Commands.DomainRole]$_.DomainRole}} | 
            Select-Object -ExcludeProperty DomainRole | 
            Select-Object -Property *, @{Name="DomainRole"; Expression = {$_.DomainRoleString}} | 
            Select-Object -ExcludeProperty DomainRoleString

        Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $node | 
            Select-Object -Property OSArchitecture | ForEach-Object {
                $Win32_ComputerSystem | Add-Member -NotePropertyName OSArchitecture -NotePropertyValue $_.OSArchitecture
            }

        Get-CimInstance -ClassName Win32_Processor -ComputerName $node | 
            Select-Object -Property Name, NumberOfCores, NumberOfLogicalProcessors | ForEach-Object {
                $Win32_ComputerSystem | Add-Member -NotePropertyName CPU -NotePropertyValue $_.Name
                $Win32_ComputerSystem | Add-Member -NotePropertyName NumberOfCores -NotePropertyValue $_.NumberOfCores
            }

        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter IPEnabled=$true -ComputerName $node | 
            Select-Object -Property MACAddress | ForEach-Object {
                $Win32_ComputerSystem | Add-Member -NotePropertyName MACAddress -NotePropertyValue $_.MACAddress
            }

        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter IPEnabled=$true -ComputerName $node | 
            Select-Object -ExpandProperty IPAddress | ForEach-Object {
                if ($_ -like "*::*") {$Win32_ComputerSystem | Add-Member -NotePropertyName Ipv6Address -NotePropertyValue $_}
                if ($_ -like "*.*") {$Win32_ComputerSystem | Add-Member -NotePropertyName Ipv4Address -NotePropertyValue $_}
            }

        $Win32_ComputerSystem | Add-Member -NotePropertyName WindowsProductName -NotePropertyValue  $((Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $node).Name -split "\|")[0]
        $Win32_ComputerSystem | Add-Member -NotePropertyName FQDN -NotePropertyValue $("$($Win32_ComputerSystem.Name)$($Win32_ComputerSystem.PartOfDomain ? "." + $Win32_ComputerSystem.Domain : $null)")
        $Win32_ComputerSystem | Add-Member -NotePropertyName DisplayName -NotePropertyValue $("$($Win32_ComputerSystem.FQDN) at $($Win32_ComputerSystem.Ipv4Address)")

        $serverInfo += $Win32_ComputerSystem
    }

    # Write-Debug "Write-Cache serverinfo"
    # Write-Cache serverinfo -InputObject $serverInfo

    return $serverInfo
}

function global:Get-ServerStatus {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $lastRunTime = Read-Cache lastruntime
    if (!$lastRunTime) {$lastRunTime = $(Get-Date).AddHours(-1)}
    Write-Verbose  "Get events since $($lastRunTime)"

    $filterHashtable = @{
        Logname = "System"
        StartTime = $lastRunTime
        Id = "1074","1075","1076","6005","6006","6008"
    }

    $eventCheckTimeStamp = [datetime]::Now

    $events = $ComputerName | ForEach-Object -Parallel {
        Get-WinEvent -FilterHashtable $using:filterHashtable -ComputerName $_ -ErrorAction SilentlyContinue
    } 

    Write-Verbose  "$($events.Count) events since $($lastRunTime)"

    $lastShutdown = @()

    if ($events) {

        foreach ($node in $ComputerName) {

            $machineName = $PrincipalContextType -eq [System.DirectoryServices.AccountManagement.ContextType]::Machine ? $node : "$($node).$($PrincipalContextName)"
            $nodeEvents = $events | Where-Object -Property MachineName -EQ $machineName | Sort-Object -Property TimeCreated -Descending
            if ($nodeEvents) {

                $shutdown = @{
                    user = $null
                    reason = $null
                    event = $null
                    status = $null
                    comment = $null
                    level = $null
                    node = $node
                    timeCreated = $null
                    id = $null
                    reasonId = $null
                }

                $be = $null
                $lastShutdownEvent = $nodeEvents[0]
                $shutdown.timeCreated = $lastShutdownEvent.TimeCreated
                $shutdown.id = $lastShutdownEvent.Id
                switch ($lastShutdownEvent.Id) {
                    1074 { # user-initiated shutdown w/reason
                        $shutdown.event = "Shutdown"
                        $shutdown.status = "In Progress"
                        $shutdown.level = $PlatformMessageType.Alert
                        $be = "is"
                    }
                    1075 { # aborted shutdown
                        $shutdown.event = "Shutdown"
                        $shutdown.status = "Aborted"
                        $shutdown.level = $PlatformMessageType.AllClear
                        $be = "was"
                    }
                    1076 { # unexpected shutdown w/post-startup reason
                        $shutdown.event = "Shutdown"
                        $shutdown.status = "In Progress"
                        $shutdown.level = $PlatformMessageType.Alert
                        $be = "is"
                    }
                    6005 { # event log service started
                        $shutdown.event = "Startup"
                        $shutdown.status = "Completed"
                        $shutdown.level = $PlatformMessageType.AllClear
                        $be = "has"
                    }
                    6006 { # event log service stopped
                        $shutdown.event = "Shutdown"
                        $shutdown.status = "In Progress"
                        $shutdown.level = $PlatformMessageType.Alert
                        $be = "is"
                    }
                    default {}
                } 

                # don't combine this switch w/the one above!
                # the latest event may be startup with the shutdown reason in a previous event

                $shutdownEventWithReason = $($nodeEvents | Where-Object -property Id -in -Value 1074,1076,6008 | Sort-Object -Property Time -Descending)[0]
                if ($shutdownEventWithReason) {
                    $shutdown.reasonId = $shutdownEventWithReason.Id
                    switch ($shutdownEventWithReason.Id) {
                        1074 {
                            # $regex = "The\sprocess\s(?'process'\S*\s\(.*\))\shas\sinitiated\sthe\s(\S*)\sof\scomputer\s(?'computer'\S*)\son\sbehalf\sof\suser\s(?'user'\S*)\s.*:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Shutdown\sType:\s*(?'type'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
                            $shutdown.user = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent.$_))).Groups["user"].Value.Trim()
                            $shutdown.reason = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent.$_))).Groups["reason"].Value.Trim()
                            $shutdown.event = ((Get-Culture).TextInfo).ToTitleCase(([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent.$_))).Groups["type"].Value.Trim()).Replace("Restart","Reboot")
                        }
                        1076 {
                            # $regex = "The\sreason\ssupplied\sby\suser\s(?'user'\S*)\sfor\sthe\slast\sunexpected\sshutdown\sof\sthis\scomputer\sis:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Bug\sID:\s*(?'bugID'.*)\s*Bugcheck\sString:\s*(?'bugcheckString'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
                            $shutdown.user = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent.$_))).Groups["user"].Value
                            $shutdown.reason = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent.$_))).Groups["reason"].Value.Trim()
                            $shutdown.comment = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent.$_))).Groups["comment"].Value.Trim()
                        }
                        6008 {
                            $shutdown.reason = $shutdownEventWithReason.message.Trim()
                        }
                        default {}
                    }
                    if (!$shutdown.reason -or $shutdown.reason.Trim() -eq "No title for this reason could be found") {
                        $shutdown.reason = "No reason provided"
                    }
                }

                Write-Log -EntryType $PlatformMessageType.Warning -Action $shutdown.event -Status $shutdown.status -Data ($shutdownEventWithReason | Select-Object -property MachineName,ProviderName,LogName,Id,TimeCreated,Message | ConvertTo-Json -Compress) -Target $node
                Write-Host+ -NoTrace -NoTimestamp -ForegroundColor ($shutdown.level -eq $PlatformMessageType.Alert ? "DarkRed" : "DarkYellow") "[$($shutdown.timeCreated.ToString('u'))] $($shutdown.event.ToUpper()) of $($node.ToUpper()) $($be) $($shutdown.status.ToUpper())" 

                Send-ServerStatusMessage -ComputerName $shutdown.node -Event $shutdown.event -Status $shutdown.status -Reason $shutdown.reason -Comment $shutdown.comment -User $shutdown.user -Level $shutdown.level -TimeCreated $shutdown.timeCreated

                $lastShutdown += $shutdown
            }        
        }
    }

    $lastShutdownThisNode = $lastShutdown | Where-Object {$_.node -eq $env:COMPUTERNAME}
    if ($lastShutdownThisNode) {
        $serverStatus = $lastShutdownThisNode.event + "." + $lastShutdownThisNode.status
    }

    # update product lastruntime *BEFORE* processing $serverStatus
    $eventCheckTimeStamp | Write-Cache lastruntime

    # actions based on $serverStatus
    switch ($serverStatus) {
        "Startup.Completed" {Clear-Cache}
        "Reboot.Completed" {Clear-Cache}
        "Restart.Completed" {Clear-Cache}
    }

    return $serverStatus
}

function global:Register-GroupPolicyScript {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][ValidateSet("Shutdown","Startup")][string]$Type,
    [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
    [switch]$AllowDuplicates
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

if (!$(Test-Path $Path)) {throw "$($Path) does not exist"}

foreach ($node in $ComputerName) {

    $index = -1
    $psScriptsPath = "\\$($node)\c$\Windows\System32\GroupPolicy\Machine\Scripts\psscripts.ini"
    if (Test-Path $psScriptsPath) {
        $psScripts = Get-IniContent $psScriptsPath

        if ($psScripts[$Type].Count -gt 0) {
            if (!$AllowDuplicates -and $psScripts[$Type].Values -Contains $Path) {continue}
            $index = $([regex]::Match($psscripts[$Type].Keys,"^(\d+)").groups[1].Value | Sort-Object -Descending)[0].ToString().ToInt32($null) + 1
        }
    }
    if ($index -eq -1) {
        $psScripts = [ordered]@{"$($Type)" = [ordered]@{}}
        $index = 0
    }

    $psScripts[$Type].Add("$($index)CmdLine", $Path)
    $psScripts[$Type].Add("$($index)Parameters","")

    $psScripts | Out-IniFile $psScriptsPath -Force
}

return

}

function global:Get-Disk {

[CmdletBinding()] 
param(
    [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)][int[]]$IgnoreDriveType = $global:ignoreDriveType,
    [Parameter(Mandatory=$false)][string[]]$IgnoreDisks = $global:ignoreDisks
)

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

return Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $ComputerName |
    Where-Object {$_.DriveType -notin $ignoreDriveType} | Where-Object {$_.Name -notin $ignoreDisks} |
    Sort-Object -Property Name | 
    Select-Object PSComputerName, Name, Description,`
        @{Label="Size";Expression={"{0:N}" -f ($_.Size/1GB) -as [float]}}, `
        @{Label="FreeSpace";Expression={"{0:N}" -f ($_.FreeSpace/1GB) -as [float]}}, `
        @{Label="PercentFreeSpace";Expression={"{0:N}" -f ($_.FreeSpace/$_.Size*100) -as [float]}}, `
        @{Label="Unit";Expression={"GB"}}, `
        FileSystem

}

function global:Confirm-ServiceLogonCredentials {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$StartName,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

# $StartName should be in the format domain\username, workgroup\username or .\username
# if $StartName doesn't include a "\", assume local and prepend ".\"
if ($StartName.IndexOf("\") -eq -1) {$StartName = ".\" + $StartName}

$svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ComputerName $ComputerName 

return $svc | Select-Object -Property @{Name="ComputerName";Expression={$_.PSComputerName.ToLower()}}, Name, StartName, @{Name="IsOK";Expression={$_.StartName -eq $StartName}} | Sort-Object -Property ComputerName
}

function global:Set-ServiceLogonCredentials {

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$StartName,
    [Parameter(Mandatory=$true)][string]$StartPassword,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

# $StartName should be in the format domain\username, workgroup\username or .\username
# if $StartName doesn't include a "\", assume local and prepend ".\"
if ($StartName.IndexOf("\") -eq -1) {$StartName = ".\" + $StartName}

$svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ComputerName $ComputerName 
if ($svc.StartName -ne $StartName) { 
    $svc | Invoke-CimMethod -MethodName Change -Arguments @{ StartName = "$($StartName)"; StartPassword = "$($StartPassword)" }
    Grant-LogOnAsAService -Name $StartName -ComputerName $ComputerName
}
return $svc
}

function global:Confirm-LogOnAsAService {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Policy,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

$results = @()
$psSession = Get-PSSession+ -ComputerName $ComputerName
$results = Invoke-Command -Session $psSession {
    secedit /export /cfg "c:\secpol.cfg" | Out-Null
    $secpolcfg = get-content "c:\secpol.cfg"
    $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith($using:Policy)}
    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Policy = $using:Policy
        Setting = $seServiceLogonRight.split("=")[1]
        Name = $using:Name
        IsOK = $seServiceLogonRight.IndexOf($using:Name) -gt -1
    }
    Remove-Item -force c:\secpol.cfg -confirm:$false
} 

return $results | Select-Object -Property ComputerName, Policy, Setting, Name, IsOK | Sort-Object ComputerName
}

function global:Grant-LogOnAsAService {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

$psSession = Get-PSSession+ -ComputerName $ComputerName
Invoke-Command -Session $psSession {
    secedit /export /cfg "c:\secpol.cfg" | Out-Null
    Copy-Item "c:\secpol.cfg" -Destination "c:\secpol.cfg.$($env:COMPUTERNAME).$(Get-Date -Format 'yyyyMMddHHmm')"
    $secpolcfg = get-content "c:\secpol.cfg"
    $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
    Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
    if ($seServiceLogonRight.IndexOf($using:Name) -eq -1) {
        $secpolcfg.replace($seServiceLogonRight,$seServiceLogonRight + "," + $using:Name) | Out-File "c:\secpol.cfg"
        $secpolcfg = get-content "c:\secpol.cfg"
        $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
        Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
        secedit /configure /db c:\windows\security\local.sdb /cfg "c:\secpol.cfg" /areas User_Rights | Out-Null
    }
    # Remove-Item -force c:\secpol.cfg -confirm:$false
}
}

function global:Revoke-LogOnAsAService {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

$psSession = Get-PSSession+ -ComputerName $ComputerName
Invoke-Command -Session $psSession {
    secedit /export /cfg "c:\secpol.cfg" | Out-Null
    Copy-Item "c:\secpol.cfg" -Destination "c:\secpol.cfg.$($env:COMPUTERNAME).$(Get-Date -Format 'yyyyMMddHHmm')"
    $secpolcfg = get-content "c:\secpol.cfg"
    $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
    Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
    if ($seServiceLogonRight.IndexOf($using:Name) -gt -1) {
        $secpolcfg.replace($seServiceLogonRight,$seServiceLogonRight.replace($using:Name,"").replace(",,",",").replace("= ,","= ")) | Out-File "c:\secpol.cfg"
        $secpolcfg = get-content "c:\secpol.cfg"
        $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
        Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
        secedit /configure /db c:\windows\security\local.sdb /cfg "c:\secpol.cfg" /areas User_Rights | Out-Null
    }
    # Remove-Item -force c:\secpol.cfg -confirm:$false
}
}

function Join-SecurityArrays {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][object[]]$svc,
    [Parameter(Mandatory=$true,Position=1)][object[]]$pol
)

$results = @()
foreach ($s in $svc) {
    foreach ($p in $pol) {
        if ($s.ComputerName -eq $p.ComputerName) {
            $results += [PSCustomObject]@{
                ComputerName = $s.ComputerName
                Service = $s.Name
                LogonAs = $p.Name
                LogonOK = $s.IsOK
                Policy = $p.Policy
                PolicyOK = $p.IsOK
                IsOK = $s.IsOK -and $p.IsOK
            }
        }
    }
}

return $results

}

function global:Get-ServiceSecurity {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

$creds = Get-Credentials $Name
$svc = Confirm-ServiceLogonCredentials -Name $Name -StartName $creds.UserName -ComputerName $ComputerName 
$pol = Confirm-LogOnAsAService -Name $creds.UserName -policy SeServiceLogonRight -ComputerName $ComputerName

return Join-SecurityArrays $svc $pol

}

function global:Set-ServiceSecurity {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
)

$svcUpdates = @()
$creds = Get-Credentials $Name
$svc = Confirm-ServiceLogonCredentials -Name $Name -StartName $creds.UserName -ComputerName $ComputerName
$svc | Where-Object {!$_.IsOK}| Foreach-Object {
    $svcUpdates += Set-ServiceLogonCredentials -Name $Name -StartName $creds.UserName -StartPassword $creds.GetNetworkCredential().Password -ComputerName $_.ComputerName
}

$polUpdates = @()
$pol = Confirm-LogOnAsAService -Name $creds.UserName -policy "SeServiceLogonRight" -ComputerName $ComputerName
$pol | Where-Object {!$_.IsOK}| Foreach-Object {
    $polUpdates += Grant-LogOnAsAService -Name $creds.UserName -ComputerName $_.ComputerName
}

if ($svcUpdates -and $polUpdates) {return Join-SecurityArrays $svcUpdates $polUpdates}
if ($svcUpdates) {return $svcUpdates}
if ($polUpdates) {return $polUpdates}

return

}

function Get-PlatformInstallProperties
{
[CmdletBinding()]
[OutputType([PSCustomObject])]
Param
(
    [Parameter(Mandatory=$true, Position=0)][SupportsWildcards()][string]$ProgramName
)

$result = @()
if ($inst = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\*\Products\*\InstallProperties" -ErrorAction SilentlyContinue)
{
    $inst | Where-Object {$_.getValue("DisplayName") -like $ProgramName} | ForEach-Object {
        $result += [PSCustomObject]@{
            "DisplayName" = $_.getValue("DisplayName")
            "Publisher" = $_.getValue("Publisher")
            "InstallPath" = $_.getValue("InstallLocation")
        }
    }
}
else
{
    Write-Error "Cannot get the InstallProperties registry keys."
}

if ($result)
{
    return $result
}
else
{
    Write-Error "Cannot get the InstallProperties registry key for $ProgramName"
}
}

function global:Update-GroupPolicy {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][ValidateSet("Machine","User")][string]$Profile = "Machine",
    [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
    [switch]$Update,
    [switch]$Force
)

$emptyString = ""

[console]::CursorVisible = $false

$message = "  Group Policy: PENDING"
Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

$sourceFileName = "$($Platform.Instance)-registry.pol"
$sourcePath= "$($global:Location.Data)\$sourceFileName"
$targetPathLocal = "C:\Windows\System32\GroupPolicy\$Profile\Registry.pol"
$targetPathUnc = $targetPathLocal.replace(":","$")

if (!(Test-Path $sourcePath)) {
    Write-Host+ -NoTrace "ERROR: The file '$sourcePath' could not be found." -ForegroundColor Red
    return
}

Write-Host+ -NoTrace "    Source: $sourcePath" -ForegroundColor DarkGray -IfVerbose
Write-Host+ -NoTrace "    Target: $targetPathLocal" -ForegroundColor DarkGray -IfVerbose
Write-Host+ -IfVerbose

$fail = $false
foreach ($node in $ComputerName) {

    $message = "    $($node) : PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 40 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

    $thisFail = $false 

    $targetPath = "\\$node\$targetPathUnc"
    $targetPathExists = Test-Path $targetPath -ErrorAction SilentlyContinue
    
    $hashIsDifferent = $false
    if ($targetPathExists) {
        $hashIsDifferent = (Get-FileHash $sourcePath).Hash -ne (Get-FileHash $targetPath).Hash
    }
    
    if ($hashIsDifferent -or !$targetPathExists -or $Force) {

        $thisFail = $true
        
        if ($Update -or $Force) {

            Write-Host+ -NoTrace -Iff (!$targetPathExists) "    $($node): Group policy file does not exist." -ForegroundColor Red -IfVerbose
            Write-Host+ -NoTrace -Iff $hashIsDifferent "    $($node): Group policy does not match $($Platform.Instance) group policy." -ForegroundColor Red -IfVerbose

            Write-Host+ -NoTrace "    $($node): Copying group policy file ... " -ForegroundColor DarkGray -IfVerbose
            Copy-Files $sourcePath -Destination $targetPathLocal -ComputerName $node 
            
            $psSession = Get-PSSession+ -ComputerName $node
            
            Write-Host+ -NoTrace "    $($node): Updating group policy ... " -ForegroundColor Gray -IfVerbose
            
            $result = Invoke-Command -Session $psSession { . gpupdate /target:computer /force } 
            # $resultUserPolicy = $result | Select-String -Pattern "User Policy" -NoEmphasis | Select-String -Pattern "success" -NoEmphasis
            $resultComputerPolicy = $result | Select-String -Pattern "Computer Policy" -NoEmphasis  | Select-String -Pattern "success" -NoEmphasis
            $resultSuccess = $resultComputerPolicy # -and $resultUserPolicy
            if ($resultSuccess) { $thisFail = $false }
            
            Remove-PSSession $psSession

            Write-Host+ -IfVerbose
            
        }

    }
    
    $message = " $($emptyString.PadLeft($message.Split(":")[1].Length,"`b"))$($thisFail ? "FAIL" : "PASS")    "
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($thisFail ? "Red" : "Green")

    $fail = $fail -or $thisFail
}

$message = "  Group Policy : $($fail ? "FAIL" : "PASS")"
Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($fail ? "Red" : "Green")

if ($fail -and !$Update) {
    Write-Host+ -NoTrace "  INFO:  Use `"-Update`" switch to update group policy." -ForegroundColor DarkGray
}

[console]::CursorVisible = $true

}

function global:Enable-CredSspDoubleHop {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
)

if ($ComputerName -ne $env:COMPUTERNAME) {
    Write-Host+ -NoTrace -NoTimestamp "ERROR: CredSSP 'double-hop' cannot be configured for a remote computer." -ForegroundColor Red
    return
}

$message = "  CredSSP Double-Hop Enabled : PENDING"
Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 40 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

$configured = Get-WSManCredSSP | Select-String -Pattern "is configured" -NoEmphasis

if (!$configured) {
    Enable-WSManCredSSP -Role Client -DelegateComputer $ComputerName -Force
    Enable-WSManCredSSP -Role Server –Force
    $configured = Get-WSManCredSSP | Select-String -Pattern "is configured" -NoEmphasis
}

$message = " $($emptyString.PadLeft($message.Split(":")[1].Length,"`b"))$($configured ? "PASS" : "FAIL")    "
Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($configured ? "Green" : "Red")

Write-Host+

}