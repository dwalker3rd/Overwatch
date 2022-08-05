    #region TOPOLOGY

    function global:Get-PlatformTopology {
            
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Key,
            [switch]$Online,
            [switch]$Offline,
            [switch]$ResetCache,
            [switch][Alias("k")]$Keys,
            [switch]$NoAlias
        )

        # read cache if it exists, else initialize the topology
        if (!$ResetCache -and $(get-cache platformtopology).Exists()) {
            $platformTopology = Read-Cache platformtopology
        } else {
            if ($ResetCache) {
                $platformTopology = Initialize-PlatformTopology -ResetCache
            } else {
                $platformTopology = Initialize-PlatformTopology
            }
        }

        # filter to offline/online nodes
        if ($Online -or $Offline) {
            $pt = $platformTopology | Copy-Object
            $nodes = $pt.nodes.keys #.psobject.properties.name
            $components = $pt.components.keys #.psobject.properties.name
            foreach ($node in $nodes) {
                if (($Online -and ($platformTopology.Nodes.$node.Offline)) -or 
                    ($Offline -and (!$platformTopology.Nodes.$node.Offline))) {
                        foreach ($component in $components) {
                            if ($node -in $platformTopology.Components.$component.Nodes) {
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
                throw "Invalid key sequence: $($Key)"
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
            [Parameter(Mandatory=$false,Position=0)][string]$Alias
        )
        $platformTopology = Get-PlatformTopology
        return $Alias ? $platformTopology.Alias.$Alias : $platformTopology.Alias
    
    }
    Set-Alias -Name ptGetAlias -Value Get-PlatformTopologyAlias -Scope Global
    Set-Alias -Name ptAlias -Value Get-PlatformTopologyAlias -Scope Global

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

#endregion TOPOLOGY