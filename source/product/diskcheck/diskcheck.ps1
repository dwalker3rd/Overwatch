#Requires -RunAsAdministrator
#Requires -Version 7

Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "Continue"

$global:Product = @{Id = "DiskCheck"}
. $PSScriptRoot\definitions.ps1

#region SERVER

    # check for server shutdown/startup events
    $return = $false
    $serverStatus = Get-ServerStatus -ComputerName (Get-PlatformTopology nodes -Keys)
    $return = switch (($serverStatus -split ",")[1]) {
        "InProgress" {$true}
    }
    if ($return) {
        $message = "Exiting due to server status: $serverStatus"
        Write-Host+ -NoTrace $message -ForegroundColor DarkYellow
        Write-Log -Action "Monitor" -Message $message -EntryType "Warning" -Status "Exiting" -Force
        return
    }

#endregion SERVER

$diskSpaceThresholds = @(-1,$diskSpaceLowThreshold,$diskSpaceCriticalThreshold)
$diskSpaceState = @("","Low","Critical")
# $webhooks = @($null,$webhookWarning,$webhookAlert)
$diskSpaceMessageType = @($null,$PlatformMessageType.Warning,$PlatformMessageType.Alert)

foreach ($node in (Get-PlatformTopology nodes -Online -Keys)) {

    $disks = get-disk -ComputerName $node
    $serverInfo = Get-ServerInfo -ComputerName $node
    Write-Host+ "Drive information for $($serverInfo.DisplayName)"
    $disks | Format-Table

    $sections = @(
        $diskSpaceStateIndex = 0
        $maxDiskSpaceStateIndex = -1
        $disks | ForEach-Object {
            $diskSpaceStateIndex = $_.PercentFreeSpace -le $diskSpaceLowThreshold ? 1 : 0
            $diskSpaceStateIndex = $_.PercentFreeSpace -le $diskSpaceCriticalThreshold ? 2 : $diskSpaceStateIndex
            if ($diskSpaceStateIndex -gt 0) {
                @{
                    ActivityTitle = "Disk Space on $($_.Name) is $($diskSpaceState[$diskSpaceStateIndex].ToUpper())"
                    ActivitySubtitle = "$($_.PercentFreeSpace)% free space remaining : $($_.FreeSpace) $($_.Unit) of $($_.Size) $($_.Unit)."
                    ActivityText = "Disk space is considered to be $($diskSpaceState[$diskSpaceStateIndex].ToUpper()) when free space falls below $($diskSpaceThresholds[$diskSpaceStateIndex])%."
                    ActivityImage = $imgDiskSpaceLow
                }
            }
            $maxDiskSpaceStateIndex = $diskSpaceStateIndex -gt $maxDiskSpaceStateIndex ? $diskSpaceStateIndex : $maxDiskSpaceStateIndex
        }
    )

    if ($maxDiskSpaceStateIndex -gt 0) {
        $msg = @{
            Sections = @(
                @{
                    ActivityTitle = $serverInfo.WindowsProductName
                    ActivitySubtitle = $serverInfo.DisplayName
                    ActivityText = "$($serverInfo.Model), $($serverInfo.NumberOfLogicalProcessors) Cores, $([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
                    ActivityImage = $global:OS.Image
                }
            )
            Title = $global:Product.TaskName
            Text = $global:Product.Description
            Type = $diskSpaceMessageType[$maxDiskSpaceStateIndex]
            Summary = "Disk Space on $($serverInfo.DisplayName) is $($diskSpaceState[$diskSpaceStateIndex].ToUpper())"
        }
        $msg.Sections += $sections

        Send-Message -Message $msg
    }
}
