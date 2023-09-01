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

$global:Product = @{Id="BgInfo"}
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

function Update-BgInfoCustomContent {

    param(
        [Parameter(Mandatory=$false)][string]$Path = $global:Product.Config.Location.Files.Destination.ConfigTxt,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME
    )

    foreach ($node in $ComputerName) {

        $bgInfoContent = ([FileObject]::new($Path, $node))
        
        if ($bgInfoContent.Exists) {
            Clear-Content -Path $bgInfoContent.Path
        }

        #region CUSTOMIZE THIS REGION ONLY

            $serverInfo = Get-ServerInfo -ComputerName $node
            Add-Content -Path $bgInfoContent.Path -Value "ComputerName:`t$($node.ToUpper())"
            Add-Content -Path $bgInfoContent.Path -Value "IPv4 Address:`t$($serverInfo.Ipv4Address)"
            Add-Content -Path $bgInfoContent.Path -Value "IPv6 Address:`t$($serverInfo.Ipv6Address)"
            Add-Content -Path $bgInfoContent.Path -Value "MAC Address:`t$($serverInfo.MACAddress)"
            Add-Content -Path $bgInfoContent.Path -Value ""

            Add-Content -Path $bgInfoContent.Path -Value "CPU:`t$($serverInfo.CPU.Replace('(R)','').Replace('CPU ','')), $($serverInfo.OSArchitecture)"
            Add-Content -Path $bgInfoContent.Path -Value "Processors:`t$($serverInfo.NumberOfCores) Cores, $($serverInfo.NumberOfLogicalProcessors) Logical Processors"
            Add-Content -Path $bgInfoContent.Path -Value "Memory:`t$([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
            Add-Content -Path $bgInfoContent.Path -Value ""
            
            $disks = Get-Disk -ComputerName $node -IgnoreDisks $null
            Add-Content -Path $bgInfoContent.Path -Value "Volumes:`t           Size       Free Space"
            Add-Content -Path $bgInfoContent.Path -Value "        `t           ----       ----------"
            foreach ($disk in $disks) {
                $diskName = $disk.Name
                $diskSize = "$([math]::Round($($disk.Size),1))$($disk.Unit)"
                $diskFreeSpace = "$([math]::Round($($disk.FreeSpace),1))$($disk.Unit)"
                $diskPercentFreeSpace = "($([math]::Round($($disk.PercentFreeSpace),0))%)"
                Add-Content -Path $bgInfoContent.Path -Value "`t$diskName\  $($emptyString.PadLeft(10-$diskSize.Length))$diskSize $($emptyString.PadLeft(10-$diskFreeSpace.Length))$diskFreeSpace $diskPercentFreeSpace"
            }
            Add-Content -Path $bgInfoContent.Path -Value ""

            Add-Content -Path $bgInfoContent.Path -Value "OS Version:`t$($serverInfo.OSName)"
            Add-Content -Path $bgInfoContent.Path -Value "System Type:`t$($serverInfo.DomainRole)"
            Add-Content -Path $bgInfoContent.Path -Value ""

            $azVmContext = Get-AzVmContext -VmName $node
            Add-Content -Path $bgInfoContent.Path -Value "Environment:`t$($azVmContext.Subscription.Environment)"
            Add-Content -Path $bgInfoContent.Path -Value "Subscription:`t$($azVmContext.Subscription.Name)"
            Add-Content -Path $bgInfoContent.Path -Value "Tenant:`t$($azVmContext.Tenant.Name) ($($azVmContext.Tenant.Type))"
            Add-Content -Path $bgInfoContent.Path -Value "Domain:`t$($azVmContext.Tenant.Domain)"
            Add-Content -Path $bgInfoContent.Path -Value ""

            Add-Content -Path $bgInfoContent.Path -Value "Overwatch:`t$($Overwatch.DisplayName)"
            Add-Content -Path $bgInfoContent.Path -Value "Platform:`t$($global:Platform.DisplayName)"
            Add-Content -Path $bgInfoContent.Path -Value "URL:`t$($global:Platform.Uri)"
            Add-Content -Path $bgInfoContent.Path -Value ""

            Add-Content -Path $bgInfoContent.Path -Value "Powershell:`tPowershell $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
            Add-Content -Path $bgInfoContent.Path -Value ""

        #endregion CUSTOMIZE THIS REGION ONLY

    }

}

function global:Invoke-BgInfoCommandLine {

    param(
        [Parameter(Mandatory=$false,Position=0)][string]$ConfigurationFile = $global:Product.Config.Location.Files.Destination.ConfigCgi
    )

    $_product = Get-Product BgInfo -NoCache
    $_expression = ". "
    $_expression += $_product ? $_product.Config.CommandLine.Executable : "C:\Packages\Plugins\Microsoft.Compute.BGInfo\2.1\bgInfo.exe"
    $_expression += ![string]::IsNullOrEmpty($ConfigurationFile) ? " $ConfigurationFile" : ""
    $_expression += " /NOLICPROMPT"
    Invoke-Expression $_expression

}
Set-Alias -Name bgInfoExe -Value Invoke-BgInfoCommandLine -Scope Global

# required! reload product using -nocache
$global:Product = Get-Product $Product.Id -NoCache

# update bginfofile
Update-BgInfoCustomContent -ComputerName (pt nodes -k)

Remove-PSSession+