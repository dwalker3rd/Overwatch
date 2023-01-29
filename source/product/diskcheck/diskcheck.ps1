#Requires -RunAsAdministrator
#Requires -Version 7

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

$global:Product = @{Id = "DiskCheck"}
. $PSScriptRoot\definitions.ps1

#region SERVER CHECK

    # Do NOT continue if ...
    #   1. the host server is starting up or shutting down

    # check for server shutdown/startup events
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    
    # abort if a server startup/reboot/shutdown is in progress
    if ($serverStatus -in ("Startup.InProgress","Shutdown.InProgress")) {
        $action = "Sync"; $target = "AzureAD\$($tenantKey)"; $status = "Aborted"
        $message = "Server $($ServerEvent.($($serverStatus.Split("."))[0]).ToUpper()) is $($ServerEventStatus.($($serverStatus.Split("."))[1]).ToUpper())"
        Write-Log -Target $target -Action $action -Status $status -Message $message -EntryType "Warning" -Force
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        
        return
    }

#endregion SERVER CHECK

function global:Confirm-DiskSpace {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Keys -Online)
    )

    function Build-MessageCard {

        param (
            [Parameter(Mandatory=$true)][object]$Sections
        )

        $msg = @{
            Sections = @()
            Title = $global:Product.TaskName
            Text = $global:Product.Description
            Type = $diskSpaceMessageType[$maxDiskSpaceStateIndex]
            Summary = "Disk Space on $($serverInfo.DisplayName) is $($diskSpaceState[$diskSpaceStateIndex].ToUpper())"
        }
        $msg.Sections += @{
            ActivityTitle = $serverInfo.WindowsProductName
            ActivitySubtitle = $serverInfo.DisplayName
            ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) Cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
            ActivityImage = $global:OS.Image
        }
        $msg.Sections += $Sections

        return $msg

    }

    $diskSpaceThresholds = @(-1,$diskSpaceLowThreshold,$diskSpaceCriticalThreshold)
    $diskSpaceState = @("","Low","Critical")
    $diskSpaceMessageType = @($null,$PlatformMessageType.Warning,$PlatformMessageType.Alert)

    foreach ($node in $ComputerName) {

        $sections = @()

        $disks = get-disk -ComputerName $node
        $serverInfo = Get-ServerInfo -ComputerName $node
        Write-Host+ "Drive information for $($serverInfo.DisplayName)"
        $disks | Format-Table

        $diskSpaceStateIndex = 0
        $maxDiskSpaceStateIndex = -1
        $disks | ForEach-Object {
            $diskSpaceStateIndex = $_.PercentFreeSpace -le $diskSpaceLowThreshold ? 1 : 0
            $diskSpaceStateIndex = $_.PercentFreeSpace -le $diskSpaceCriticalThreshold ? 2 : $diskSpaceStateIndex
            if ($diskSpaceStateIndex -gt 0) {
                $sections += @{
                    ActivityTitle = "Disk Space on $($_.Name) is $($diskSpaceState[$diskSpaceStateIndex].ToUpper())"
                    ActivitySubtitle = "$($_.PercentFreeSpace)% free space remaining : $($_.FreeSpace) $($_.Unit) of $($_.Size) $($_.Unit)."
                    ActivityText = "Disk space is considered to be $($diskSpaceState[$diskSpaceStateIndex].ToUpper()) when free space falls below $($diskSpaceThresholds[$diskSpaceStateIndex])%."
                    ActivityImage = $imgDiskSpaceLow
                }
            }
            $maxDiskSpaceStateIndex = $diskSpaceStateIndex -gt $maxDiskSpaceStateIndex ? $diskSpaceStateIndex : $maxDiskSpaceStateIndex
        }

        if ($maxDiskSpaceStateIndex -gt 0) {
            $msg = Build-MessageCard -Sections $sections
            Send-Message -Message $msg | Out-Null
        }
    }

}

Confirm-DiskSpace

Remove-PSSession+