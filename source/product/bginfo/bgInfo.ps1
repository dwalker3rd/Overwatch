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

$ConfigFile = $global:Product.Config.Files.Config
$CustomContentFile = $global:Product.Config.Files.CustomContent
$ComputerName = Get-PlatformTopology nodes -Keys

#region CUSTOM CONTENT FILE

    foreach ($node in $ComputerName) {

        $bgInfoCustomContent = ([FileObject]::new($CustomContentFile, $node))
        if (!$bgInfoCustomContent.Exists($bgInfoCustomContent.Directory)) {
            $bgInfoCustomContentDirectory = New-Item -ItemType Directory -Path $bgInfoCustomContent.Directory -Force
            $bgInfoCustomContentDirectory | Out-Null
        }
        
        if ($bgInfoCustomContent.exists()) {
            Clear-Content -Path $bgInfoCustomContent.Path
        }

        #region CUSTOMIZE THIS REGION ONLY

            $serverInfo = Get-ServerInfo -ComputerName $node

            Add-Content -Path $bgInfoCustomContent.Path -Value "ComputerName:`t$($node.ToUpper())"
            Add-Content -Path $bgInfoCustomContent.Path -Value "IPv4 Address:`t$($serverInfo.Ipv4Address)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "IPv6 Address:`t$($serverInfo.Ipv6Address)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "MAC Address:`t$($serverInfo.MACAddress)"
            Add-Content -Path $bgInfoCustomContent.Path -Value ""

            $azureVM = Get-AzVm -name $node
            $azureSubscriptionId = ($azureVm.Id -split "/")[2]
            $azureSubscription = Get-AzSubscription -SubscriptionId $azureSubscriptionId
            $azureTenant = Get-AzTenant -TenantId $azureSubscription.TenantId

            Add-Content -Path $bgInfoCustomContent.Path -Value "Azure Tenant:"
            Add-Content -Path $bgInfoCustomContent.Path -Value "`tName:`t$($azureTenant.ExtendedProperties.DisplayName)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "`tType:`t$($azureTenant.TenantType.Replace("AAD","Azure AD"))"
            Add-Content -Path $bgInfoCustomContent.Path -Value "`tDomain:`t$($azureTenant.DefaultDomain)"
            Add-Content -Path $bgInfoCustomContent.Path -Value ""

            Add-Content -Path $bgInfoCustomContent.Path -Value "OS Version:`t$($serverInfo.WindowsProductName)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "System Type:`t$($serverInfo.DomainRole)"
            Add-Content -Path $bgInfoCustomContent.Path -Value ""

            Add-Content -Path $bgInfoCustomContent.Path -Value "CPU:`t$($serverInfo.CPU.Replace('(R)','').Replace('CPU ','')), $($serverInfo.OSArchitecture)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "Processors:`t$($serverInfo.NumberOfCores) Cores, $($serverInfo.NumberOfLogicalProcessors) Logical Processors"
            Add-Content -Path $bgInfoCustomContent.Path -Value "Memory:`t$([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
            Add-Content -Path $bgInfoCustomContent.Path -Value ""
            
            $disks = Get-Disk -ComputerName $node -IgnoreDisks $null
            Add-Content -Path $bgInfoCustomContent.Path -Value "Volumes:`t           Size       Free Space"
            Add-Content -Path $bgInfoCustomContent.Path -Value "        `t           ----       ----------"
            foreach ($disk in $disks) {
                $diskName = $disk.Name
                $diskSize = "$([math]::Round($($disk.Size),1))$($disk.Unit)"
                $diskFreeSpace = "$([math]::Round($($disk.FreeSpace),1))$($disk.Unit)"
                $diskPercentFreeSpace = "($([math]::Round($($disk.PercentFreeSpace),0))%)"
                Add-Content -Path $bgInfoCustomContent.Path -Value "`t$diskName\  $($emptyString.PadLeft(10-$diskSize.Length))$diskSize $($emptyString.PadLeft(10-$diskFreeSpace.Length))$diskFreeSpace $diskPercentFreeSpace"
            }
            Add-Content -Path $bgInfoCustomContent.Path -Value ""

            Add-Content -Path $bgInfoCustomContent.Path -Value "Overwatch:`t$($Overwatch.DisplayName)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "Platform:`t$($global:Platform.DisplayName)"
            Add-Content -Path $bgInfoCustomContent.Path -Value "URL:`t$($global:Platform.Uri)"
            Add-Content -Path $bgInfoCustomContent.Path -Value ""

            Add-Content -Path $bgInfoCustomContent.Path -Value "Powershell:`tPowershell $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
            Add-Content -Path $bgInfoCustomContent.Path -Value ""

        #endregion CUSTOMIZE THIS REGION ONLY

    }

#endregion CUSTOM CONTENT FILE
#region CONFIG FILE

    $bgInfoConfigFile = ([FileObject]::new($ConfigFile))
    if (!$bgInfoConfigFile.Exists()) {
        Write-Host+ -NoTrace -NoTimestamp "Could not find the config file '$($bgInfoConfigFile)'." -ForegroundColor Red
        Write-Host+ -NoTrace -NoTimestamp "Use Sysinternals BgInfo to create/save the config file '$($bgInfoConfigFile)'."
        return
    }

    Copy-Files -Path $ConfigFile -ComputerName $ComputerName -ExcludeComputerName $env:COMPUTERNAME

#endregion CONFIG FILE
#region RUN BGINFO    

    foreach ($node in $ComputerName) {
        $psSession = Use-PSSession+ -ComputerName $node
        $bgInfoExe = "$(Get-EnvironConfig Location.Sysinternals.BgInfo -ComputerName $node)\bginfo.exe"
        $bgInfoConfigFile = "$(Get-EnvironConfig Location.BgInfo -ComputerName $node)\bgInfo.bgi"
        Invoke-Command -Session $psSession -ScriptBlock { . $using:bginfoExe $using:bgInfoConfigFile /all /timer:0 /nolicprompt /silent }
        Remove-PSSession+ $psSession
    }

#endregion RUN BGINFO    

