enum OSProductType {
    WorkStation = 1
    DomainController = 2
    Server = 3
}

function global:IsWindows {

    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    if ($ComputerName -eq $env:COMPUTERNAME) {
        $IsWindows
    }
    else {
        $psSession = New-PSSession+ -ComputerName $ComputerName
        return Invoke-Command -Session $psSession -ScriptBlock { $IsWindows }
    }

}

function global:IsServer {

    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    return (Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName | Select-Object -Property ProductType).ProductType -eq [OSProductType]::Server

}

function global:IsWindowsServer {

    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    return $IsWindows -and (IsServer)

}

function global:Measure-ServerPerformance {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][object]$Counters = $PerformanceCounters,
        [Parameter(Mandatory=$false)][int32]$MaxSamples = $PerformanceCounterMaxSamples,
        [Parameter(Mandatory=$false)][int32]$SampleInterval = $PerformanceMeasurementampleInterval
    )

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


    $serverInfo = @()
    foreach ($node in $ComputerName) {

        $_serverInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $node | 
            Select-Object -Property *, @{Name="DomainRoleString"; Expression = {[Microsoft.PowerShell.Commands.DomainRole]$_.DomainRole}} | 
            Select-Object -ExcludeProperty DomainRole | 
            Select-Object -Property *, @{Name="DomainRole"; Expression = {$_.DomainRoleString}} | 
            Select-Object -ExcludeProperty DomainRoleString

        Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $node | 
            Select-Object -Property Name, OSArchitecture, Version | ForEach-Object {
                $_serverInfo | Add-Member -NotePropertyName OSName -NotePropertyValue ($_.Name -split "\|")[0]
                $_serverInfo | Add-Member -NotePropertyName OSArchitecture -NotePropertyValue $_.OSArchitecture
                $_serverInfo | Add-Member -NotePropertyName OSVersion -NotePropertyValue $_.Version
            }

        Get-CimInstance -ClassName Win32_Processor -ComputerName $node | 
            Select-Object -Property Name, NumberOfCores, NumberOfLogicalProcessors | ForEach-Object {
                $_serverInfo | Add-Member -NotePropertyName CPU -NotePropertyValue $_.Name
                $_serverInfo | Add-Member -NotePropertyName NumberOfCores -NotePropertyValue $_.NumberOfCores
            }

        $_win32_NetworkAdapterConfiguration = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter IPEnabled=$true -ComputerName $node

        $_win32_NetworkAdapterConfiguration | 
            Select-Object -Property MACAddress | ForEach-Object {
                $_serverInfo | Add-Member -NotePropertyName MACAddress -NotePropertyValue $_.MACAddress
            }

        $_win32_NetworkAdapterConfiguration | 
            Select-Object -ExpandProperty IPAddress | ForEach-Object {
                if ($_ -like "*::*") {$_serverInfo | Add-Member -NotePropertyName Ipv6Address -NotePropertyValue $_}
                if ($_ -like "*.*") {$_serverInfo | Add-Member -NotePropertyName Ipv4Address -NotePropertyValue $_}
            }

        $_serverInfo | Add-Member -NotePropertyName OSType -NotePropertyValue WindowsServer
        $_serverInfo | Add-Member -NotePropertyName FQDN -NotePropertyValue $("$($_serverInfo.Name)$($_serverInfo.PartOfDomain ? "." + $_serverInfo.Domain : $null)")
        $_serverInfo | Add-Member -NotePropertyName DisplayName -NotePropertyValue $("$($_serverInfo.FQDN) at $($_serverInfo.Ipv4Address)")

        $serverInfo += $_serverInfo
    }

    return $serverInfo
}

function global:Get-ServerStatus {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [switch]$Quiet
    )

    $lastRunTime = Read-Cache lastruntime
    if (!$lastRunTime) {$lastRunTime = $(Get-Date).AddHours(-1)}

    $filterHashtable = @{
        Logname = "System"
        StartTime = $lastRunTime
        Id = "1074","1075","1076","6005","6006","6008"
    }

    $eventCheckTimeStamp = [datetime]::Now

    $winEvents = $ComputerName | ForEach-Object -Parallel {
        try{
            Get-WinEvent -FilterHashtable $using:filterHashtable -ComputerName $_ -ErrorAction SilentlyContinue
        }
        catch {
            # if this fails when run from Azure Update Management, ignore the error
        }
    } 

    $shutdownEvents = @()
    if ($winEvents) {

        foreach ($node in $ComputerName) {

            $machineName = $PrincipalContextType -eq [System.DirectoryServices.AccountManagement.ContextType]::Machine ? $node : "$($node).$($PrincipalContextName)"
            $nodeEvents = $winEvents | Where-Object -Property MachineName -EQ $machineName | Sort-Object -Property TimeCreated -Descending
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
                        $shutdown.status = "InProgress"
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
                        $shutdown.status = "InProgress"
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
                        $shutdown.status = "InProgress"
                        $shutdown.level = $PlatformMessageType.Alert
                        $be = "is"
                    }
                    default {}
                } 

                # don't combine this switch w/the one above!
                # the latest event may be startup with the shutdown reason in a previous event

                $nodeEventsWithReason = $($nodeEvents | Where-Object -property Id -in -Value 1074,1076,6008 | Sort-Object -Property Time -Descending)
                $shutdownEventWithReason = $nodeEventsWithReason ? $nodeEventsWithReason[0] : $null
                if ($shutdownEventWithReason) {
                    $shutdown.reasonId = $shutdownEventWithReason.Id
                    switch ($shutdownEventWithReason.Id) {
                        1074 {
                            # $regex = "The\sprocess\s(?'process'\S*\s\(.*\))\shas\sinitiated\sthe\s(\S*)\sof\scomputer\s(?'computer'\S*)\son\sbehalf\sof\suser\s(?'user'\S*)\s.*:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Shutdown\sType:\s*(?'type'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
                            $shutdown.user = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent[$_]))).Groups["user"].Value.Trim()
                            $shutdown.reason = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent[$_]))).Groups["reason"].Value.Trim()
                            $shutdown.event = ((Get-Culture).TextInfo).ToTitleCase(([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent[$_]))).Groups["type"].Value.Trim()).Replace("Restart","Reboot")
                        }
                        1076 {
                            # $regex = "The\sreason\ssupplied\sby\suser\s(?'user'\S*)\sfor\sthe\slast\sunexpected\sshutdown\sof\sthis\scomputer\sis:\s(?'reason'.*)\n\s*Reason\sCode:\s*(?'code'.*)\n\s*Bug\sID:\s*(?'bugID'.*)\s*Bugcheck\sString:\s*(?'bugcheckString'.*)\n\s*Comment:\s*(?'comment'\S?.*)"
                            $shutdown.user = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent[$_]))).Groups["user"].Value
                            $shutdown.reason = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent[$_]))).Groups["reason"].Value.Trim()
                            $shutdown.comment = ([regex]::Match($shutdownEventWithReason.message,($global:RegexPattern.Windows.ShutdownEvent[$_]))).Groups["comment"].Value.Trim()
                        }
                        6008 {
                            $shutdown.reason = $shutdownEventWithReason.message.Trim()
                        }
                        default {}
                    }
                }

                if (!$shutdown.reason -or $shutdown.reason.Trim() -eq "No title for this reason could be found") {
                    $shutdown.reason = "No reason provided"
                }

                Write-Log -EntryType $PlatformMessageType.Warning -Action $shutdown.event -Target $node -Status $shutdown.status -Message $shutdown.reason
                Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -ForegroundColor ($shutdown.level -eq $PlatformMessageType.Alert ? "DarkRed" : "DarkYellow") "[$($shutdown.timeCreated.ToString('u'))] $($shutdown.event.ToUpper()) of $($node.ToUpper()) $($be) $($shutdown.status.ToUpper())" 

                Send-ServerStatusMessage -ComputerName $shutdown.node -Event $shutdown.event -Status $shutdown.status -Reason $shutdown.reason -Comment $shutdown.comment -User $shutdown.user -Level $shutdown.level -TimeCreated $shutdown.timeCreated | Out-Null

                $shutdownEvents += $shutdown
            }        
        }
    }

    # update product lastruntime *BEFORE* processing $serverStatus
    $eventCheckTimeStamp | Write-Cache lastruntime

    # select primary/priority shutdown event
    $serverStatus = $null
    if ($shutdownEvents) {
        $initialNodeEvent = $shutdownEvents | Where-Object {$_.node -eq (pt InitialNode)}
        $mainEvent = $initialNodeEvent ?? $shutdownEvents[0]
        $serverStatus = $mainEvent.event + "." + $mainEvent.status
    }

    # actions based on $serverStatus
    switch ($serverStatus) {
        "Startup.Completed" {
            Clear-Cache clusterstatus
            Clear-Cache platforminfo
            Clear-Cache platformservices
        }
    }

    return $serverStatus
}

function global:Get-Disk {

[CmdletBinding()] 
param(
    [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)][int[]]$IgnoreDriveType = $global:ignoreDriveType,
    [Parameter(Mandatory=$false)][string[]]$IgnoreDisks = $global:ignoreDisks
)

return Get-CimInstance -ClassName Cim_LogicalDisk -ComputerName $ComputerName |
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

$svc = Get-CimInstance -ClassName Cim_Service -Filter "Name='$Name'" -ComputerName $ComputerName 

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

$svc = Get-CimInstance -ClassName Cim_Service -Filter "Name='$Name'" -ComputerName $ComputerName 
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
    $psSession = Use-PSSession+ -ComputerName $ComputerName
    $results = Invoke-Command -Session $psSession {
        secedit /export /cfg "$($using:Location.Data)\secpol.cfg" | Out-Null
        $secpolcfg = get-content "$($using:Location.Data)\secpol.cfg"
        $seServiceLogonRight = $secpolcfg | Where-Object {$_.StartsWith($using:Policy)}
        $seServiceLogonRightMatch = [regex]::Match($seServiceLogonRight,"^SeServiceLogonRight\s=\s*(.*?\s*,*\s*(alteryxsvc)\s*,.*)$",[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $isOk = $seServiceLogonRightMatch.Success
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Policy = $using:Policy
            Setting = $isOk ? $seServiceLogonRightMatch.Captures.Groups[1].Value : $null
            Name = $isOk ? $seServiceLogonRightMatch.Groups[2].Value : $Name
            IsOK = $isOk
        }
        Remove-Item -force "$($using:Location.Data)\secpol.cfg" -confirm:$false
    }

return $results | Select-Object -Property ComputerName, Policy, Setting, Name, IsOK | Sort-Object ComputerName
}

function global:Grant-LogOnAsAService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName
    Invoke-Command -Session $psSession {
        secedit /export /cfg "$($using:Location.Data)\secpol.cfg" | Out-Null
        Copy-Item "$($using:Location.Data)\secpol.cfg" -Destination "$($using:Location.Data)\secpol.cfg.$($env:COMPUTERNAME).$(Get-Date -Format 'yyyyMMddHHmm')"
        $secpolcfg = get-content "$($using:Location.Data)\secpol.cfg"
        $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
        Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
        if ($seServiceLogonRight.IndexOf($using:Name) -eq -1) {
            $secpolcfg.replace($seServiceLogonRight,$seServiceLogonRight + "," + $using:Name) | Out-File "$($using:Location.Data)\secpol.cfg"
            $secpolcfg = get-content "$($using:Location.Data)\secpol.cfg"
            $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
            Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
            secedit /configure /db c:\windows\security\local.sdb /cfg "$($using:Location.Data)\secpol.cfg" /areas User_Rights | Out-Null
        }
        # Remove-Item -force "$($using:Location.Data)\secpol.cfg" -confirm:$false
    }
    # Remove-PsSession $psSession

}

function global:Revoke-LogOnAsAService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName
    Invoke-Command -Session $psSession {
        secedit /export /cfg "$($using:Location.Data)\secpol.cfg" | Out-Null
        Copy-Item "$($using:Location.Data)\secpol.cfg" -Destination "$($using:Location.Data)\secpol.cfg.$($env:COMPUTERNAME).$(Get-Date -Format 'yyyyMMddHHmm')"
        $secpolcfg = get-content "$($using:Location.Data)\secpol.cfg"
        $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
        Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
        if ($seServiceLogonRight.IndexOf($using:Name) -gt -1) {
            $secpolcfg.replace($seServiceLogonRight,$seServiceLogonRight.replace($using:Name,"").replace(",,",",").replace("= ,","= ")) | Out-File "$($using:Location.Data)\secpol.cfg"
            $secpolcfg = get-content "$($using:Location.Data)\secpol.cfg"
            $seServiceLogonRight = $secpolcfg | Where-Object {$_.startswith("SeServiceLogonRight")}
            Write-Output "$($env:COMPUTERNAME): $($seServiceLogonRight)"
            secedit /configure /db c:\windows\security\local.sdb /cfg "$($using:Location.Data)\secpol.cfg" /areas User_Rights | Out-Null
        }
        # Remove-Item -force "$($using:Location.Data)\secpol.cfg" -confirm:$false
    }
    # Remove-PsSession $psSession

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
    Write-Host+ "Cannot get the InstallProperties registry keys." -ForegroundColor DarkRed
}

if ($result)
{
    return $result
}
else
{
    Write-Host+ "Cannot get the InstallProperties registry key for $ProgramName" -ForegroundColor DarkRed
}
}

# function global:Update-GroupPolicy {

# [CmdletBinding()]
# param (
#     [Parameter(Mandatory=$false)][ValidateSet("Machine","User")][string]$Profile = "Machine",
#     [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
#     [switch]$Update,
#     [switch]$Force
# )

# $emptyString = ""

# Set-CursorInvisible

# $message = "<  Group Policy <.>48> PENDING"
# Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

# $sourceFileName = "$($Platform.Instance)-registry.pol"
# $sourcePath= "C:\$sourceFileName"
# $targetPathLocal = "C:\Windows\System32\GroupPolicy\$Profile\Registry.pol"
# $targetPathUnc = $targetPathLocal.replace(":","$")

# if (!(Test-Path $sourcePath)) {
#     Write-Host+ -NoTrace "ERROR: The file '$sourcePath' could not be found." -ForegroundColor Red
#     return
# }

# Write-Host+ -NoTrace "    Source: $sourcePath" -ForegroundColor DarkGray -IfVerbose
# Write-Host+ -NoTrace "    Target: $targetPathLocal" -ForegroundColor DarkGray -IfVerbose
# Write-Host+ -IfVerbose

# $fail = $false
# foreach ($node in $ComputerName) {

#     $message = "<    $($node) <.>40> PENDING"
#     Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

#     $thisFail = $false 

#     $targetPath = "\\$node\$targetPathUnc"
#     $targetPathExists = Test-Path $targetPath -ErrorAction SilentlyContinue
    
#     $hashIsDifferent = $false
#     if ($targetPathExists) {
#         $hashIsDifferent = (Get-FileHash $sourcePath).Hash -ne (Get-FileHash $targetPath).Hash
#     }
    
#     if ($hashIsDifferent -or !$targetPathExists -or $Force) {

#         $thisFail = $true
        
#         if ($Update -or $Force) {

#             Write-Host+ -NoTrace -Iff (!$targetPathExists) "    $($node): Group policy file does not exist." -ForegroundColor Red -IfVerbose
#             Write-Host+ -NoTrace -Iff $hashIsDifferent "    $($node): Group policy does not match $($Platform.Instance) group policy." -ForegroundColor Red -IfVerbose

#             Write-Host+ -NoTrace "    $($node): Copying group policy file ... " -ForegroundColor DarkGray -IfVerbose
#             Copy-Files $sourcePath -Destination $targetPathLocal -ComputerName $node 
            
#             $psSession = Use-PSSession+ -ComputerName $node
            
#             Write-Host+ -NoTrace "    $($node): Updating group policy ... " -ForegroundColor Gray -IfVerbose
            
#             $result = Invoke-Command -Session $psSession { . gpupdate /target:computer /force } 
#             # $resultUserPolicy = $result | Select-String -Pattern "User Policy" -NoEmphasis | Select-String -Pattern "success" -NoEmphasis
#             $resultComputerPolicy = $result | Select-String -Pattern "Computer Policy" -NoEmphasis  | Select-String -Pattern "success" -NoEmphasis
#             $resultSuccess = $resultComputerPolicy # -and $resultUserPolicy
#             if ($resultSuccess) { $thisFail = $false }
            
#             Remove-PSSession $psSession

#             Write-Host+ -IfVerbose
            
#         }

#     }
    
#     $message = " $($emptyString.PadLeft($message.Split(":")[1].Length,"`b"))$($thisFail ? "FAIL" : "PASS")    "
#     Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($thisFail ? "Red" : "Green")

#     $fail = $fail -or $thisFail
# }

# $message = "<  Group Policy <.>48> $($fail ? "FAIL" : "PASS")"
# Write-Host+ -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($fail ? "Red" : "Green")

# if ($fail -and !$Update) {
#     Write-Host+ -NoTrace "  INFO:  Use `"-Update`" switch to update group policy." -ForegroundColor DarkGray
# }

# Set-CursorVisible

# }

function global:Enable-CredSspDoubleHop {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string]$ComputerName = "*"
)

# if ($ComputerName -ne $env:COMPUTERNAME) {
#     Write-Host+ -NoTrace -NoTimestamp "ERROR: CredSSP 'double-hop' cannot be configured for a remote computer." -ForegroundColor Red
#     return
# }

$message = "<  CredSSP Double-Hop Enabled <.>40> PENDING"
Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

$configured = $true
$notConfigured = Get-WSManCredSSP | Select-String -Pattern "is not configured" -NoEmphasis

if ($notConfigured) {
    $clientWSManCredSSP = Enable-WSManCredSSP -Role Client -DelegateComputer $ComputerName -Force
    $clientWSManCredSSP | Out-Null
    $serverWSManCredSSP = Enable-WSManCredSSP -Role Server –Force
    $serverWSManCredSSP | Out-Null
    $configured = Get-WSManCredSSP | Select-String -Pattern "is configured" -NoEmphasis
}

$message = " $($emptyString.PadLeft(8,"`b"))$($configured ? "PASS" : "FAIL")    "
Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor ($configured ? "Green" : "Red")

}

function global:Request-PlatformService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][ValidateSet("Start","Stop")][string]$Command,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
        [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName=$env:COMPUTERNAME
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName -ErrorAction SilentlyContinue

    Invoke-Command -Session $psSession {
        if ($using:Command -eq "Stop") {
            Stop-Service -Name $using:Name -ErrorAction SilentlyContinue
        }
        elseif ($using:Command -eq "Start") {
            Start-Service -Name $using:Name -ErrorAction SilentlyContinue
        }
    }

    # Remove-PSSession $psSession

    return 

}

function global:Stop-PlatformService {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
    [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName=$env:COMPUTERNAME
)
Request-PlatformService -Command "Stop" -Name $Name -ComputerName $ComputerName -ExcludeComputerName $ExcludeComputerName
}
function global:Start-PlatformService {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
    [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName=$env:COMPUTERNAME
)
Request-PlatformService -Command "Start" -Name $Name -ComputerName $ComputerName -ExcludeComputerName $ExcludeComputerName
}
function global:Restart-PlatformService {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
    [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName=$env:COMPUTERNAME
)
Request-PlatformService -Command "Stop" -Name $Name -ComputerName $ComputerName -ExcludeComputerName $ExcludeComputerName
Request-PlatformService -Command "Start" -Name $Name -ComputerName $ComputerName -ExcludeComputerName $ExcludeComputerName
}

function global:Set-PlatformService {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][ValidateSet("Manual","Automatic","AutomaticDelayedStart","Disabled")][Microsoft.PowerShell.Commands.ServiceStartupType]$StartupType
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName -ErrorAction SilentlyContinue

    Invoke-Command -Session $psSession {
        Get-Service -Name $using:Name -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.StartupType -ne $using:StartupType) {
                Set-Service -Name $_.Name -StartupType $using:StartupType
            }
        }
    }

    # Remove-PsSession $psSession

    return

}

function global:Start-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName
    )
    Write-Host+ "The Overwatch $($global:OS.DisplayName) $($MyInvocation.MyCommand) cmdlet is not supported."
    return

}
Set-Alias -Name Start-VM -Value Stop-Computer -Scope Global
Set-Alias -Name startVM -Value Stop-Computer -Scope Global

function global:Stop-Computer {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$ComputerName
    )
    Write-Host+ "The Overwatch $($global:OS.DisplayName) $($MyInvocation.MyCommand) cmdlet is not supported."
    return

}
Set-Alias -Name Stop-VM -Value Stop-Computer -Scope Global
Set-Alias -Name stopVM -Value Stop-Computer -Scope Global

function global:Get-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        # [Parameter(Mandatory=$false)][object[]]$Session,
        [Parameter(Mandatory=$false)][string]$View
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }
    
    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $groups = @()

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    $groups = Invoke-Command -Session $psSession {
        $group = Get-LocalGroup @using:params -ErrorAction SilentlyContinue 
        $group | Add-Member -NotePropertyName Members -NotePropertyValue (Get-LocalGroupMember -Group $group.Name) -ErrorAction SilentlyContinue
        $group
    }

    foreach ($group in $groups) {
        $group | Add-Member -NotePropertyName ComputerName -NotePropertyValue $group.PSComputerName -ErrorAction SilentlyContinue
    }

    return $groups | Select-Object -Property $($View ? $GroupView.$($View) : $GroupView.Default)

}

function global:New-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    $params = @{};
    if ($Description) {$params += @{Description = $Description}}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        New-LocalGroup -Name $using:Name @using:params
    }

}

function global:Set-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Set-LocalGroup @using:params -Description $using:Description
    }

}

function global:Remove-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    $groups = Get-LocalGroup+ @params -ComputerName $ComputerName -Session $psSession

    $hasMembers = $false
    foreach ($group in $Groups) {
        if ($group.Members.Count -gt 0) {
            $hasMembers = $true
            Write-Host+ -NoTrace -NoTimestamp "    $($group.PSComputerName) > $($group.Name) > $($group.Members.Count) member[s]" -ForegroundColor DarkGray
        }
    }
    if ($hasMembers) {
        Write-Host+ -NoTrace -NoTimestamp "  You must remove the members from local group `"$($group.Name)`" before it can be deleted." -ForegroundColor Red 
        return
    }
    else {
        return Invoke-Command -Session $psSession {
            Remove-LocalGroup @using:params
        }
    }

}

function global:Get-LocalUser+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        # [Parameter(Mandatory=$false)][object[]]$Session,
        [Parameter(Mandatory=$false)][string]$View

    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name } }
    if ($SID) { $params += @{ SID = $SID } }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    $localUser = Invoke-Command -Session $psSession {
        Get-LocalUser @using:params -ErrorAction SilentlyContinue
    }
    $localUser | Add-Member -NotePropertyName "Username" -NotePropertyValue "$($localUser.PSComputerName.ToUpper())\$($localUser.Name)"

    return $localUser

}

function global:New-LocalUser+ {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Password,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][boolean]$PasswordNeverExpires=$false,
        [Parameter(Mandatory=$false)][boolean]$UserMayNotChangePassword=$false,   
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    $params = @{};
    if ($FullName) {$params += @{FullName = $FullName}}
    if ($Description) {$params += @{Description = $Description}}
    if ($Password) {
        $params += @{Password = ConvertTo-SecureString -String $Password -AsPlainText -Force}
        $params += @{PasswordNeverExpires = $PasswordNeverExpires}
        $params += @{UserMayNotChangePassword = $UserMayNotChangePassword}
    }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        New-LocalUser -Name $using:Name @using:params
    }

}

function global:Set-LocalUser+ {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string]$Password,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][boolean]$PasswordNeverExpires,
        # [Parameter(Mandatory=$false)][boolean]$UserMayNotChangePassword,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}
    if ($FullName) {$params += @{FullName = $FullName}}
    if ($Description) {$params += @{Description = $Description}}
    if ($Password) {
        $params += @{Password = ConvertTo-SecureString -String $Password -AsPlainText -Force}
        $params += @{PasswordNeverExpires = $PasswordNeverExpires}
        # $params += @{UserMayNotChangePassword = $UserMayNotChangePassword}
    }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Set-LocalUser @using:params
    }

}

function global:Remove-LocalUser+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Remove-LocalUser @using:params
    }

}

function global:Add-LocalGroupMember+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string]$Member,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Add-LocalGroupMember @using:params -Member $using:Member
    }

}

function global:Remove-LocalGroupMember+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string]$Member,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Remove-LocalGroupMember @using:params -Member $using:Member -ErrorAction SilentlyContinue
    }

}