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

function global:Update-BgInfoCustomContent {

    param(
        [Parameter(Mandatory=$false)][string]$Path = $global:Product.Config.Content,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME
    )

    foreach ($node in $ComputerName) {

        $bgInfoContent = ([FileObject]::new($Path, $node))
        
        if ($bgInfoContent.exists()) {
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

            Add-Content -Path $bgInfoContent.Path -Value "OS Version:`t$($serverInfo.WindowsProductName)"
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

# required! reload product using -nocache
$Product = Get-Product $Product.Id -NoCache

# update bginfofile
Update-BgInfoCustomContent -Path $Product.Config.Content -ComputerName (pt nodes -k)

# run bginfo to update background
$commandLineExpression = ". `"$($Product.Config.Executable)`" `"$($Product.Config.Config)`" $($Product.Config.Options -join ' ')"
Invoke-Expression $commandLineExpression