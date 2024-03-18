#region PLATFORM TOPOLOGY

function global:Get-PlatformTopology {
            
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Key,
        [switch]$Online,
        [switch]$Offline,
        [switch]$Until,
        [switch]$Shutdown,
        [switch]$ResetCache,
        [switch][Alias("k")]$Keys,
        [switch]$NoAlias,
        [Parameter(Mandatory=$false)][Alias("Controller","c")][string]$ComputerName = $env:COMPUTERNAME
    )

    $platformTopology = $null

    # remote query
    if ($ComputerName -ne $env:COMPUTERNAME) {

        # read cache if it exists
        if ((Get-Cache platformtopology -ComputerName $ComputerName).Exists) {
            $platformTopology = Read-Cache platformtopology -ComputerName $ComputerName
        }
        if (!$platformTopology) { return }

    }

    # local query
    else {

        # read cache if it exists, else initialize the topology
        if (!$ResetCache -and $(Get-Cache platformtopology).Exists) {
            $platformTopology = Read-Cache platformtopology
        }
        else {
            if ($ResetCache) {
                $platformTopology = Initialize-PlatformTopology -ResetCache
            } else {
                $platformTopology = Initialize-PlatformTopology
            }
        }

    }

    # filter to offline/online nodes
    if ($Online -or $Offline -or $Until -or $Shutdown) {
        $pt = $platformTopology | Copy-Object
        $nodes = $pt.nodes.keys #.psobject.properties.name
        $components = $pt.components.keys #.psobject.properties.name
        foreach ($node in $nodes) {
            if (($Online -and ($platformTopology.Nodes.$node.Offline)) -or 
                ($Offline -and (!$platformTopology.Nodes.$node.Offline)) -or
                ($Until -and (!$platformTopology.Nodes.$node.Until)) -or 
                ($Shutdown -and (!$platformTopology.Nodes.$node.Shutdown))) {
                    foreach ($component in $components) {
                        if ($node -in $platformTopology.Components.$component.Nodes.Keys) {
                            $platformTopology.Components.$component.Nodes.Remove($node)
                        }
                        if ($platformTopology.Components.$component.Nodes.Count -eq 0) {
                            $platformTopology.Components.Remove($component)
                        }
                    }
                    $platformTopology.Nodes.Remove($node)
                }
        }
    }

    # Get-PlatformTopology allows for dot-notated keys:  worker.nodes
    # $px are the original key splits saved for message writes
    # $kx are the processed keys that are used to access the topology hashtable
    $len = $Key ? $Key.Split('.').Count : 0
    $p = $Key.Split('.').ToLower()
    $k = [array]$p.Clone()
    if ($k[0] -eq "alias") { $NoAlias = $true }
    for ($i = 0; $i -lt $len; $i++) {
        $k[$i] = "['$($NoAlias ? $k[$i] : ($platformTopology.Alias.($k[$i]) ?? $k[$i]))']"
    }

    $ptExpression = "`$platformTopology"
    if ($len -gt 0) {$ptExpression += "$($k -join '')"}
    $result = Invoke-Expression $ptExpression
    if (!$result) {
        $keysRegex = [regex]"(\[.+?\])"
        $groups = $keysRegex.Matches($ptExpression)
        $lastGroup = $groups[$groups.Count-1]
        $lastKey = $lastGroup.Value.replace("['","").replace("']","")
        $parent = Invoke-Expression $ptExpression.replace($lastGroup.Value,"")
        if (!$parent.Contains($lastKey)) {
            Write-Host+ "Invalid key sequence: $($Key)"
        }
    }

    return $Keys ? $result.Keys : $result

}
Set-Alias -Name pt -Value Get-PlatformTopology -Scope Global

function global:Save-PlatformTopology {

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)][object]$Topology,
        [Parameter(Mandatory=$false)][string]$Extension,
        [switch]$AsDefault,
        [switch]$UseTimeStamp
    )

    begin {

        if (!$Extension -and !$AsDefault -and !$UseTimeStamp) {
            $Extension = Read-Host "Extension"
            if (!$Extension) {throw "Extension must be specified."}
        }

        if ($AsDefault) {$Extension = "default"}
        if ($UseTimeStamp) {$Extension = "$(Get-Date -Format 'yyyyMMddHHmm')"}

        $platformTopology = @{}
    }
    process {
        $platformTopology = $Topology 
    }
    end {
        $platformTopology ??= Get-PlatformTopology
        $platformTopology | Write-Cache "platformtopology.$($Extension)"
    }
}
Set-Alias -Name ptSave -Value Save-PlatformTopology -Scope Global

function global:Restore-PlatformTopology {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Extension,
        [switch]$FromDefault
    )
    if ($FromDefault) {$Extension = "default"}

    if (!$Extension) {
        $Extension = Read-Host "Extension"
        if (!$Extension) {throw "Extension must be specified."}
    }
    
    $platformTopology = Read-Cache "platformtopology.$($Extension)" 
    $platformTopology | Write-Cache platformtopology

    return $platformTopology

}
Set-Alias -Name ptRestore -Value Restore-PlatformTopology -Scope Global

function global:Get-PlatformTopologyAlias {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$Alias,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][object]$PlatformTopology = (Get-PlatformTopology -ComputerName $ComputerName)
    )

    return $Alias ? $PlatformTopology.Alias.$Alias : $PlatformTopology.Alias

}
Set-Alias -Name ptGetAlias -Value Get-PlatformTopologyAlias -Scope Global
Set-Alias -Name ptAlias -Value Get-PlatformTopologyAlias -Scope Global

function global:Build-PlatformTopologyAlias {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false,Position=0)][string]$ComputerName
    )

    $ptAlias = $null
    if (![string]::IsNullOrEmpty($global:RegexPattern.PlatformTopology.Alias.Match)) {
        if ($ComputerName -match $global:RegexPattern.PlatformTopology.Alias.Match) {
            foreach ($i in $global:RegexPattern.PlatformTopology.Alias.Groups) {
                $ptAlias += $Matches[$i]
            }
        }
    }

    return $ptAlias
}
Set-Alias -Name ptBuildAlias -Value Build-PlatformTopologyAlias -Scope Global

function global:Set-PlatformTopologyAlias {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Alias,
        [Parameter(Mandatory=$true,Position=1)][string]$Value
    )
    $platformTopology = Get-PlatformTopology
    $platformTopology.Alias.$Alias = $Value
    $platformTopology | Write-Cache platformtopology

}
Set-Alias -Name ptSetAlias -Value Set-PlatformTopologyAlias -Scope Global

#endregion PLATFORM TOPOLOGY
#region OVERWATCH TOPOLOGY

function global:Find-OverwatchControllers {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName
    )

    if (!$ComputerName) {
        $_controllers = @()
        $_controllers += $env:COMPUTERNAME
        if ($global:OverwatchRemoteControllers.Count -gt 0) {
            $_controllers += $global:OverwatchRemoteControllers
        }
        $ComputerName = $_controllers | Sort-Object -Unique
    }

    $controllers = @()
    foreach ($node in $ComputerName) {
        $_overwatch = Get-Catalog -Uid Overwatch.Overwatch -ComputerName $node
        if ($_overwatch.Installed) {
            if ($controllers -inotcontains $node) { 
                $controllers += $node.ToLower()
            }
        }
    }

    return $controllers

}
Set-Alias -Scope Global -Name owtFindC -Value Find-OverwatchControllers

function global:Get-OverwatchController {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$false)][string]$Search
    )

    $nodes = Get-OverwatchTopology nodes -Keys
    $environs = Get-OverwatchTopology environ -Keys

    $controller = $null
    if ($Search -in $nodes) { 
        $controller = Get-OverwatchTopology nodes.$Search.Controller
    }
    if ($Search -in $environs) { 
        $controller = Get-OverwatchTopology environ.$Search.Controller
    }

    return $controller

}
Set-Alias -Scope Global -Name owtGetC -Value Get-OverwatchController

function global:Get-OverwatchTopology {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Key,
        [switch]$ResetCache,
        [switch][Alias("k")]$Keys,
        [switch]$NoAlias
    )

    $overwatchTopology = $null

    # read cache if it exists, else initialize the topology
    if (!$ResetCache -and $(Get-Cache overwatchtopology).Exists) {
        $overwatchTopology = Read-Cache overwatchtopology
    }
    else {
        if ($ResetCache) {
            $overwatchTopology = Initialize-OverwatchTopology -ResetCache
        } else {
            $overwatchTopology = Initialize-OverwatchTopology
        }
    }

    # Get-OverwatchTopology allows for dot-notated keys:  controller.nodes
    # $px are the original key splits saved for message writes
    # $kx are the processed keys that are used to access the topology hashtable
    $len = $Key ? $Key.Split('.').Count : 0
    $p = $Key.Split('.').ToLower()
    $k = [array]$p.Clone()
    if ($k[0] -eq "alias") { $NoAlias = $true }
    for ($i = 0; $i -lt $len; $i++) {
        $k[$i] = "['$($NoAlias ? $k[$i] : ($overwatchTopology.Alias.($k[$i]) ?? $k[$i]))']"
    }

    $owtExpression = "`$overwatchTopology"
    if ($len -gt 0) {$owtExpression += "$($k -join '')"}
    $result = Invoke-Expression $owtExpression
    if (!$result) {
        $keysRegex = [regex]"(\[.+?\])"
        $groups = $keysRegex.Matches($owtExpression)
        $lastGroup = $groups[$groups.Count-1]
        $lastKey = $lastGroup.Value.replace("['","").replace("']","")
        $parent = Invoke-Expression $owtExpression.replace($lastGroup.Value,"")
        if (!$parent.Contains($lastKey)) {
            throw "Invalid key sequence: $($Key)"
        }
    }

    return $Keys ? $result.Keys : $result

}  
Set-Alias -Scope Global -Name owt -Value Get-OverwatchTopology

function global:Initialize-OverwatchTopology {

    [CmdletBinding()] 
    param (
        # [Parameter(Mandatory=$false)][Alias("Controller","c")][string[]]$ComputerName = $global:OverwatchControllers,
        [switch]$ResetCache,
        [switch]$NoCache
    )

    if (!$ResetCache -and !$NoCache) {
        if ($(Get-Cache overwatchTopology).Exists) {
            return Read-Cache overwatchTopology
        }
    }

    $overwatchTopology = @{
        Environ = @{}
        Controller = @{}
        Nodes = @{}
        Alias = Get-PlatformTopology alias
    }

    # add overwatch controllers to wsman trusted hosts (required for remoting)
    Add-WSManTrustedHosts -ComputerName $global:OverwatchControllers

    # find-overwatchcontrollers ensures that each node in $ComputerName is reachable
    foreach ($overwatchController in (Find-OverwatchControllers)) {
        
        # add overwatch controller to wsman trusted hosts (required for remoting)
        # Add-WSManTrustedHosts -ComputerName $overwatchController | Out-Null

        $owcEnviron = Get-EnvironConfig -Key Environ -ComputerName $overwatchController
        $owcNodes = Get-PlatformTopology nodes -Keys -Controller $overwatchController

        # environ
        $owcPlatformInstance = $owcEnviron.Instance
        foreach ($key in $owcEnviron.Keys) {
            $overwatchTopology.Environ.$owcPlatformInstance += @{ 
                $key = $owcEnviron.$key
            }
        }
        $overwatchTopology.Environ.$owcPlatformInstance += @{ Controller = $overwatchController }
        $overwatchTopology.Environ.$owcPlatformInstance += @{ Nodes = $owcNodes }

        # controller
        $overwatchTopology.Controller += @{ 
            $overwatchController = @{
                Environ = $owcPlatformInstance
                Nodes = $owcNodes
            }
        }

        # nodes
        foreach ($node in $owcNodes) {
            $overwatchTopology.Nodes += @{ 
                $node = @{ 
                    Controller = $overwatchController
                    Environ = $owcPlatformInstance
                }
            }
            $owtAlias = ptBuildAlias $node
            if ($owtAlias) {
                $overwatchTopology.Alias.$owtAlias = $node
            }
        }

    }

    if (!$NoCache -and $overwatchTopology.Controller) {
        $overwatchTopology | Write-Cache overwatchTopology
    }

    return $overwatchTopology

}
Set-Alias -Scope Global -Name owtInit -Value Initialize-OverwatchTopology

#endregion OVERWATCH TOPOLOGY