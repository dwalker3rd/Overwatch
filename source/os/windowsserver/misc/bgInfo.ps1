#Requires -RunAsAdministrator
#Requires -Version 7

function global:Install-BgInfo {

    param(
        [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Config")][switch]$Configure
    )

    $bgInfoVMExtension = "Microsoft.Compute.BgInfo"
    $bgInfoVMExtensionName = "BgInfo"
    $bgInfoTypeHandlerVersion = "2.1"
    $bgInfoVMExtensionDisplayName = "$bgInfoVMExtension $bgInfoTypeHandlerVersion"

    Set-CursorInvisible

    Write-Host+ -NoTrace -NoTimestamp "Azure VM Extension: $bgInfoVMExtensionDisplayName" -ForegroundColor Blue

    foreach ($node in $ComputerName) {

        $message = "[$node] Status : PENDING    "
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

        $vm = Get-AzVm -Name $node
        $ResourceGroupName = $vm.ResourceGroupName
        $subscription = Get-AzSubscription -SubscriptionId ($vm.Id -split "/")[2]
        $Tenant = (Get-AzTenant -TenantId $subscription.TenantId).Domains[0].split(".")[0].ToLower()
        
        $tenantKey = $Tenant.split(".")[0].ToLower()
        if (!$global:AzureAD.$tenantKey) {throw "$tenantKey is not a valid/configured AzureAD tenant."}
        
        $Location = $global:AzureAD.$tenantKey.Defaults.Location

        $isBgInfoInstalled = Confirm-BgInfoVmExtension -ResourceGroupName $ResourceGroupName -ComputerName $node -Name $bgInfoVMExtensionName -ErrorAction SilentlyContinue

        if (!$isBgInfoInstalled) {
            $message = "$($emptyString.PadLeft(12,"`b")) INSTALLING "
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor Yellow 
            Install-BgInfoVmExtension -ResourceGroupName $ResourceGroupName -ComputerName $node -Name "$bgInfoVMExtensionName" -TypeHandlerVersion $bgInfoTypeHandlerVersion -Location $Location
        }

        if (!$isBgInfoInstalled -or $Configure) {
            $message = "$($emptyString.PadLeft(12,"`b")) CONFIGURING"
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor Yellow 
            Build-BgInfoFile -ComputerName $node
        }

        if (!$Configure) {
            $message = "$($emptyString.PadLeft(12,"`b")) INSTALLED  "
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor Green 
        }
        else {
            $message = "$($emptyString.PadLeft(12,"`b")) CONFIGURED "
            Write-Host+ -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor Green
        }

        Write-Host+

    }

    Write-Host+
    Set-CursorVisible

}
Set-Alias -Name Update-BgInfo -Value Install-BgInfo -Scope Global

function Confirm-BgInfoVmExtension {

    param(
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Name

    )

    return Get-AzVmExtension -ResourceGroupName $ResourceGroupName -VMName $ComputerName -Name $Name

}

function Install-BgInfoVmExtension {

    param(
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Location,
        [Parameter(Mandatory=$true)][string]$TypeHandlerVersion
    )

    $psAzureOperationResponse = Set-AzVMBgInfoExtension -ResourceGroupName $ResourceGroupName -VMName $ComputerName -Name $Name -TypeHandlerVersion $TypeHandlerVersion -Location $Location
    $psAzureOperationResponse | Out-Null

    return

}

function Build-BgInfoFile {

    param(
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $tenantKey = "pathaiforhealth"

    function Write-BgInfo {
        param (
            [Parameter(Mandatory=$true,Position=0)]
            [AllowEmptyString()]
            [AllowNull()]
            [string]$Row
        )
        Add-Content -Path $bgInfoFile.Path -Value $Row
    }
        
    $bgInfoPath = "\\$ComputerName\C$\Packages\Plugins\Microsoft.Compute.BGInfo\2.1\".replace(":","$")
    $bgInfoPath += "bginfo.txt"
    $bgInfoFile = Get-Files -Path $bgInfoPath

    if (([FileObject]$bgInfofile).exists()) {
        Clear-Content -Path $bgInfoFile.Path
    }
    else {
        $bgInfoFile = [FileObject]::New($bgInfoFile.Path)
    }

    $serverInfo = Get-ServerInfo -ComputerName $ComputerName
    $disks = Get-Disk -ComputerName $ComputerName -IgnoreDisks $null

    Write-BgInfo "ComputerName:`t$($ComputerName.ToUpper())"
    Write-BgInfo "IPv4 Address:`t$($serverInfo.Ipv4Address)"
    Write-BgInfo "IPv6 Address:`t$($serverInfo.Ipv6Address)"
    Write-BgInfo "MAC Address:`t$($serverInfo.MACAddress)"
    Write-BgInfo ""
    Write-BgInfo "Tenant Type:`t$($global:AzureAD.$tenantKey.Tenant.Type)"
    Write-BgInfo "Tenant Type:`t$($global:AzureAD.$tenantKey.Tenant.Type)"
    Write-BgInfo ""
    Write-BgInfo "OS Version:`t$($serverInfo.WindowsProductName)"
    Write-BgInfo "System Type:`t$($serverInfo.DomainRole)"
    Write-BgInfo ""
    Write-BgInfo "CPU:`t$($serverInfo.CPU.Replace('(R)','').Replace('CPU ','')), $($serverInfo.OSArchitecture)"
    Write-BgInfo "Processors:`t$($serverInfo.NumberOfCores) Cores, $($serverInfo.NumberOfLogicalProcessors) Logical Processors"
    Write-BgInfo "Memory:`t$([math]::round($serverInfo.TotalPhysicalMemory/1gb,0).ToString()) GB"
    Write-BgInfo ""
    $label = $null
    foreach ($disk in $disks) {
        if (!$label) {$label = "Volumes:"} else {$label = "       "}
        Write-BgInfo "$label`t$($disk.Name)\ $($disk.Size) $($disk.Unit) $($disk.FileSystem)"
    }
    Write-BgInfo ""
    $label = $null
    foreach ($disk in $disks) {
        if (!$label) {$label = "Free Space:"} else {$label = "          "}
        Write-BgInfo "$label`t$($disk.Name)\ $($disk.FreeSpace) $($disk.Unit) $($disk.FileSystem)"
    }
    Write-BgInfo ""
    Write-BgInfo "Overwatch:`t$($Overwatch.DisplayName)"
    Write-BgInfo "Platform:`t$($global:Platform.DisplayName)"
    Write-BgInfo "URL:`t$($global:Platform.Uri)"
    Write-BgInfo ""
    Write-BgInfo "Powershell:`tPowershell $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"

    return
    
}
