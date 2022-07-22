[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls11  

#region OVERWATCH

    function global:Get-Overwatch {

        [CmdletBinding()] 
        param ()

        return $global:Overwatch

    }

    function global:Get-Environ {

        [CmdletBinding()] 
        param ()

        return $global:Environ

    }

    function global:Get-OS {

        [CmdletBinding()] 
        param ()

        return $global:OS

    }

    function global:Get-Platform {

        [CmdletBinding()] 
        param ()

        return $global:Platform

    }

    function global:Get-Product {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [switch]$ResetCache
        )

        $products = @()
        if (!$ResetCache) {
            if ($(get-cache products).Exists()) {
                $products = Read-Cache products #-MaxAge $(New-Timespan -Minutes 2)
            }
        }

        # persist $global:Product
        $productClone = $global:Product ? $($global:Product | Copy-Object) : $null

        # this method overwrites $global:Product so clone $global:Product
        if (!$products) {
            $products = @()
            $global:Environ.Product | ForEach-Object {
                $productDefinitionsFile = "$($global:Location.Definitions)\definitions-product-$($_).ps1"
                if (Test-Path -Path $productDefinitionsFile) {
                    $products += . $productDefinitionsFile
                }
            }

            for ($i = 0; $i -lt $products.Count; $i++) {
                $products[$i].IsInstalled = $global:Environ.Product -contains $products[$i].Id
            }
            Write-Cache products -InputObject $products
        }

        if ($Name) {$products = $products | Where-Object {$_.Name -eq $Name}}
        if ($Id) {$products = $products | Where-Object {$_.Id -eq $Id}}

        # reset $global:Product with clone
        $global:Product = $productClone

        return $products
    }

    $global:logLockObject = $false

    function global:Get-Provider {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [switch]$ResetCache
        )

        $providers = @()
        if (!$ResetCache) {
            if ($(get-cache providers).Exists()) {
                $providers = Read-Cache providers -MaxAge $(New-Timespan -Minutes 2)
            }
        }
        
        if (!$providers) {
            $providers = @()
            $global:Environ.Provider | ForEach-Object {
                $providerDefinitionFile = "$($global:Location.Root)\definitions\definitions-provider-$($_).ps1"
                if (Test-Path -Path $providerDefinitionFile) {
                    $providers += . $providerDefinitionFile
                }
            }

            for ($i = 0; $i -lt $providers.Count; $i++) {
                $providers[$i].IsInstalled = $global:Environ.Provider -contains $providers[$i].Id
            }

            Write-Cache providers -InputObject $providers
        }

        if ($Name) {$providers = $providers | Where-Object {$_.Name -eq $Name}}
        if ($Id) {$providers = $providers | Where-Object {$_.Id -eq $Id}}

        return $providers
    }

#endregion OVERWATCH
#region PLATFORM

    #region STATUS

        function global:Get-PlatformStatus {
                
            [CmdletBinding()]
            param (
                [switch]$ResetCache
            )

            Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            if ((get-cache platformstatus).Exists() -and !$ResetCache) {
                $platformStatus = [PlatformStatus](Read-Cache platformStatus)
            }

            if (!$platformStatus) {
                $platformStatus = [PlatformStatus]::new()
            }

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action "Read-Cache" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force

            $params = @{}
            if ($ResetCache) {$params += @{ResetCache = $true}}
            $platformStatus.IsOK, $platformStatus.RollupStatus, $platformStatus.StatusObject = Get-PlatformStatusRollup @params

            if ($platformStatus.RollupStatus -in @("Stopping","Starting","Restarting") -and !$platformStatus.Event) {
                $command = switch ($platformStatus.RollupStatus) {
                    "Stopping" {"Stop"}
                    default {$platformStatus.RollupStatus -replace "ing",""}
                }
                Set-PlatformEvent -Event $command -Context "Unknown" -EventReason "Unknown" -EventStatus $global:PlatformEventStatus.InProgress -PlatformStatus $platformStatus
            }

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action"Get-PlatformStatusRollup" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force

            $platformCimInstance = Get-PlatformCimInstance
            
            $isOK = $platformStatus.IsOK
            $platformCimInstance | `
                Where-Object {$_.Class -in 'Service'} | `
                    ForEach-Object {
                        $isOK = $isOK -and ($_.Required ? $_.IsOK : $true)
                    }

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action"Get-PlatformCimInstance" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force

            $IsStoppedTimeout = $false
            if (!$isOK) {
                if ($platformStatus.IsStopped) {

                    Write-Verbose "IsStopped: $($platformStatus.IsStopped)"
                    Write-Log -Action "IsStopped" -Target "Platform" -EntryType "Warning" -Status $platformStatus.IsStopped

                    $productShutdownTimeout = $(Get-Product -Id $platformStatus.EventCreatedBy).ShutdownMax
                    $shutdownTimeout = $productShutdownTimeout.TotalMinutes -gt 0 ? $productShutdownTimeout : $PlatformShutdownMax
                    # $shutdownTimeout = $platformStatus.EventCreatedBy ? $productShutdownTimeout : $PlatformShutdownMax
                    $IsStoppedTimeout = $(new-timespan -Start $platformStatus.EventCreatedAt).TotalMinutes -gt $shutdownTimeout.TotalMinutes
                    $isOK = !$IsStoppedTimeout

                    Write-Verbose "IsStoppedTimeout: $($IsStoppedTimeout)"
                    Write-Log -Action "IsStoppedTimeout" -Target "Platform" -EntryType "Warning" -Status $IsStoppedTimeout
            
                }
            }         

            $platformStatus.IsOk = $isOK
            $platformStatus.IsStopped = $platformStatus.RollupStatus -in $PlatformServiceDownState
            $platformStatus.IsStoppedTimeout = $IsStoppedTimeout
            
            $platformStatus.ByCimInstance = $platformCimInstance

            $platformStatus.Intervention = $false
            $platformStatus.InterventionReason = $null

            if ($platformStatus.IsStoppedTimeout) {
                $platformStatus.Intervention = $true
                $platformStatus.InterventionReason = "Platform STOP has exceeded $($shutdownTimeout.TotalMinutes) minutes"
            }

            if ($platformStatus.EventStatus -eq $PlatformEventStatus.Failed) {
                $platformStatus.Intervention = $true
                $platformStatus.InterventionReason = "Platform $($platformStatus.Event.ToUpper()) has $($platformStatus.EventStatus.ToUpper())"
            }

            if ($platformStatus.Event) {
                $platformStatus.EventUpdatedAt = [datetime]::Now
            }
            
            if ($platformStatus.RollupStatus -eq $platformStatus.EventStatusTarget) {
                    $platformStatus.EventHasCompleted = $true
                    $platformStatus.EventStatus = $PlatformEventStatus.Completed
                    $platformStatus.EventCompletedAt = [datetime]::Now
            }

            if ($ResetCache) {

                Write-Verbose "Reset Platform Status"
                # Write-Log -Action "Reset" -Target "Platform Status" -EntryType "Warning" -Status $isOK

                $platformStatus.Event = $null
                $platformStatus.EventReason = $null
                $platformStatus.EventStatus = $null
                $platformStatus.EventStatusTarget = $null
                $platformStatus.EventCreatedAt = [datetime]::MinValue
                $platformStatus.EventUpdatedAt = [datetime]::MinValue
                $platformStatus.EventCreatedBy = $null
                $platformStatus.EventHasCompleted = $false
                $platformStatus.Intervention = $false
                $platformStatus.InterventionReason = $null
                $platformStatus.ByCimInstance = $null
                $platformStatus.StatusObject = $null
                
            }

            $platformStatus | Write-Cache platformstatus

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action "return" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force  

            return $platformStatus # .IsOK

        }

    #endregion STATUS
    #region SERVICES

        function global:Wait-PlatformService {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Online -Keys),
                [Parameter(Mandatory=$true)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Status = "Running",
                [Parameter(Mandatory=$false)][int]$WaitTimeInSeconds = 60,
                [Parameter(Mandatory=$false)][int]$TimeOutInSeconds = 0
            )
            
            $totalWaitTimeInSeconds = 0
            $service = Get-PlatformService -ComputerName $ComputerName | Where-Object {$_.Name -eq $Name}
            if (!$service) {
                throw "`"$Name`" is not a valid $($global:Platform.Name) platform service name."
            }

            $currentStatus = $service.Status | Sort-Object -Unique
            while ($currentStatus -ne $Status) {
                Start-Sleep -Seconds $WaitTimeInSeconds
                $totalWaitTimeInSeconds += $WaitTimeInSeconds
                if ($TimeOutInSeconds -gt 0 -and $totalWaitTimeInSeconds -ge $TimeOutInSeconds) {
                    # throw "ERROR: Timeout ($totalWaitTimeInSeconds seconds) waiting for platform service `"$Name`" to transition from status `"$currentStatus`" to `"$Status`""
                    return $false
                }
                $service = Get-PlatformService -ComputerName $ComputerName | Where-Object {$_.Name -eq $Name}
                $currentStatus = $service.Status | Sort-Object -Unique
            }
        
            return $true
        
        }

        function global:Wait-Service {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
                [Parameter(Mandatory=$true)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Status = "Running",
                [Parameter(Mandatory=$false)][int]$WaitTimeInSeconds = 60,
                [Parameter(Mandatory=$false)][int]$TimeOutInSeconds = 0
            )

            $psSession = Get-PSSession+ -ComputerName $ComputerName -ErrorAction SilentlyContinue
            
            $totalWaitTimeInSeconds = 0
            $service = Invoke-Command -Session $psSession { Get-Service -Name $using:Name -ErrorAction SilentlyContinue }
            $currentStatus = $service.Status | Sort-Object -Unique
            while ($currentStatus -ne $Status) {
                Start-Sleep -Seconds $WaitTimeInSeconds
                $totalWaitTimeInSeconds += $WaitTimeInSeconds
                if ($TimeOutInSeconds -gt 0 -and $totalWaitTimeInSeconds -ge $TimeOutInSeconds) {
                    # throw "ERROR: Timeout ($totalWaitTimeInSeconds seconds) waiting for platform service `"$Name`" to transition from status `"$currentStatus`" to `"$Status`""
                    return $false
                }
                $service = Invoke-Command -Session $psSession { Get-Service -Name $using:Name -ErrorAction SilentlyContinue }
                $currentStatus = $service.Status | Sort-Object -Unique
            }
        
            return $true
        
        }

    #endregion SERVICES
    #region EVENT

        function global:Set-PlatformEvent {
                
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true)][string]$Event,
                [Parameter(Mandatory=$false)][string]$Context,
                [Parameter(Mandatory=$false)][string]$EventReason,
                [Parameter(Mandatory=$false)][ValidateSet('In Progress','Completed','Failed','Reset','Testing')][string]$EventStatus,
                [Parameter(Mandatory=$false)][string]$EventStatusTarget,
                [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus)

            )

            Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            # $platformStatus = Get-PlatformStatus
            
            $PlatformStatus.Event = $Event
            $PlatformStatus.EventStatus = $EventStatus
            $PlatformStatus.EventReason = $EventReason
            $PlatformStatus.EventStatusTarget = $EventStatusTarget ? $EventStatusTarget : $PlatformEventStatusTarget.$($Event)
            $PlatformStatus.EventCreatedAt = [datetime]::Now
            $PlatformStatus.EventCreatedBy = $Context ?? $global:Product.Id
            $PlatformStatus.EventHasCompleted = $EventStatus -eq "Completed" ? $true : $false

            $PlatformStatus | Write-Cache platformstatus

            $result = Send-PlatformEventMessage -PlatformStatus $PlatformStatus -NoThrottle
            $result | Out-Null

            return

        }

        function global:Reset-PlatformEvent {

            [CmdletBinding()]
            param ()

            return Get-PlatformStatus -ResetCache

        }

    #endregion EVENT
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

#endregion PLATFORM
#region TESTS

    function global:Get-IpAddress {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)][string]$ComputerName
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        return (Resolve-DnsName $ComputerName).IPAddress

    }

    function global:Test-Connections {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Keys)
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $leader = Format-Leader -Length 47 -Adjust ((("  Network Connections").Length))
        Write-Host+ -NoTrace "  Network Connections",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray
        Write-Log -Action "Test" -Target "Network"

        $fail = $false
        foreach ($node in $ComputerName) {

            $ip = ([System.Net.Dns]::GetHostAddresses($node) | Where-Object {$_.AddressFamily -eq "InterNetwork"}).IPAddressToString

            $leader = Format-Leader -Length 39 -Adjust ((("    Ping $($node) [$($ip)]").Length))
            Write-Host+ -NoTrace -NoNewLine "    Ping","$($node) [$($ip)]",$leader -ForegroundColor Gray,DarkBlue,DarkGray

            if (Test-Connection -ComputerName $node -Quiet) {
                Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
                Write-Log -Action "Test" -Target "Network" -Status "Fail" -EntryType "Error" -Message "Unable to ping $($node) [$($ip)]"
                $fail = $true
            }

        }

        $leader = Format-Leader -Length 47 -Adjust ((("  Network Connections").Length))
        Write-Host+ -NoTrace -NoNewLine  "  Network Connections",$leader -ForegroundColor Gray,DarkGray

        if ($fail) {
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
            Write-Log -Action "Test" -Target "Network" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message
            # throw "Network Connections ... FAIL"
        }
        else {
            Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen
            Write-Log -Action "Test" -Target "Network" -Status "Pass"
        }
    }

    function global:Test-PSRemoting {

        [CmdletBinding()]
        param ()

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $leader = Format-Leader -Length 47 -Adjust ((("  Powershell Remoting").Length))
        Write-Host+ -NoTrace "  Powershell Remoting",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray
        Write-Log -Action "Test" -Target "Powershell-Remoting"

        $fail = $false
        foreach ($node in (Get-PlatformTopology nodes -Online -Keys)) {

            # Write-Host+ -NoNewline -NoTimestamp -NoTrace "." -ForegroundColor DarkGray

            $leader = Format-Leader -Length 39 -Adjust ((("    Remote to $($node)").Length))
            Write-Host+ -NoTrace -NoNewLine "    Remote to","$($node)",$leader -ForegroundColor Gray,DarkBlue,DarkGray

            try {
                $psSession = Get-PSSession+ -ComputerName $node 
                Remove-PSSession -Session $psSession
                Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen 
            }
            catch {
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
                Write-Log -Action "Test" -Target "Powershell-Remoting" -Status "Fail" -EntryType "Error" -Message "Powershell-Remoting to $($node) failed"
                $fail = $true
            }

        }

        $leader = Format-Leader -Length 47 -Adjust ((("  Powershell Remoting").Length))
        Write-Host+ -NoTrace -NoNewLine "  Powershell Remoting",$leader -ForegroundColor Gray,DarkGray
        
        if ($fail) {
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
            Write-Log -Action "Test" -Target "Powershell-Remoting" -Status "Fail" -EntryType "Error"
            throw "Powershell Remoting ... FAIL"
        }
        else {
            Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen
            Write-Log -Action "Test" -Target "Powershell-Remoting" -Status "Pass"
        }
    }

    <#
        .DESCRIPTION
        Outputs the SSL protocols that the client is able to successfully use to connect to a server.

        .PARAMETER ComputerName
        The name of the remote computer to connect to.

        .PARAMETER Port
        The remote port to connect to. The default is 443.

        .EXAMPLE
        Test-SslProtocol -ComputerName "www.google.com"

        ComputerName       : www.google.com
        Port               : 443
        KeyLength          : 2048
        SignatureAlgorithm : rsa-sha1
        Ssl2               : False
        Ssl3               : True
        Tls                : True
        Tls11              : True
        Tls12              : True

        .NOTES
        Copyright 2014 Chris Duck
        http://blog.whatsupduck.net

        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
    #>
    function global:Test-SslProtocol {
        param(
            [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)]
            $ComputerName = $global:Platform.Uri.Host,

            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [int]$Port = 443,

            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [switch]$PassFailOnly
        )

        begin {
                
            Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            If (!$PassFailOnly) {Write-Host+}

            $messagePart = "  SSL Protocol ","$($ComputerName)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $messagePart[0],"[",$messagePart[1],"] ",(Format-Leader -Length 48 -Adjust ((($messagePart -join " ").Length+2)))," PENDING" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,DarkGray

            $now = Get-Date -AsUTC
            $30days = New-TimeSpan -days 30
            # $emptyString = ""
            $fail = $false
            $warn = $false

            $ProtocolNames = [System.Security.Authentication.SslProtocols] |
                Get-Member -Static -MemberType Property |
                Where-Object -Filter { $_.Name -notin @("Default","None") } |
                Foreach-Object { $_.Name }
    
            $bestPractice = @{
                protocols = @{
                    Ssl2  = @{state="Disabled"; displayName="SSLv2"}
                    Ssl3  = @{state="Disabled"; displayName="SSLv3"}
                    Tls   = @{state="Disabled"; displayName="TLSv1"}
                    Tls11 = @{state="Disabled"; displayName="TLSv1.1"}
                    Tls12 = @{state="Enabled"; displayName="TLSv1.2"}
                    Tls13 = @{state=""; displayName="TLSv1.3"}
                }
                signatureAlgorithms = @("sha256RSA")
            }
            $supportedProtocols = $bestPractice.protocols.Keys | Sort-Object

        }

        process {

            $ProtocolStatus = [Ordered]@{}
            $ProtocolStatus.Add("ComputerName", $ComputerName)
            $ProtocolStatus.Add("Port", $Port)
            $ProtocolStatus.Add("KeyLength", $null)
            $ProtocolStatus.Add("SignatureAlgorithm", $null)
            $ProtocolStatus.Add("SupportedProtocols",@())

            $ProtocolNames | ForEach-Object {
                $ProtocolName = $_
                $Socket = New-Object System.Net.Sockets.Socket( `
                    [System.Net.Sockets.SocketType]::Stream,
                    [System.Net.Sockets.ProtocolType]::Tcp)
                $Socket.Connect($ComputerName, $Port)
                try {
                    $NetStream = New-Object System.Net.Sockets.NetworkStream($Socket, $true)
                    $SslStream = New-Object System.Net.Security.SslStream($NetStream, $true)
                    $SslStream.AuthenticateAsClient($ComputerName,  $null, $ProtocolName, $false )
                    $RemoteCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]$SslStream.RemoteCertificate
                    $ProtocolStatus["KeyLength"] = $RemoteCertificate.PublicKey.Key.KeySize
                    $ProtocolStatus["SignatureAlgorithm"] = $RemoteCertificate.SignatureAlgorithm.FriendlyName
                    $ProtocolStatus["Certificate"] = $RemoteCertificate
                    $ProtocolStatus.Add($ProtocolName, $true)
                } catch  {
                    $ProtocolStatus.Add($ProtocolName, $false)
                } finally {
                    $SslStream.Close()
                }
            }

        }

        end {

            $thisWarn = $false
            $thisFail = $false

            $expiresInDays = $ProtocolStatus.Certificate.NotAfter - $now
            
            $thisWarn = $expiresInDays -le $30days
            $warn = $warn -or $thiswarn
            $thisFail = $expiresInDays -le [timespan]::Zero
            $fail = $fail -or $thisFail

            $expiryColor = $thisFail ? "DarkRed" : ($thisWarn ? "DarkYellow" : "DarkGray")
            
            $message = "<    Certificate <.>40> PENDING"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
            $message = "      Subject:      $($ProtocolStatus.Certificate.Subject)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Issuer:       $($ProtocolStatus.Certificate.Issuer.split(",")[0])"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Serial#:      $($ProtocolStatus.Certificate.SerialNumber)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Thumbprint:   $($ProtocolStatus.Certificate.Thumbprint)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Expiry:      | $($ProtocolStatus.Certificate.NotAfter)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor DarkGray,$expiryColor
            $message = "      Status:      | $($thisFail ? "Expired" : ($thisWarn ? "Expires in $([math]::round($expiresInDays.TotalDays,1)) days" : "Valid"))"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor DarkGray,$expiryColor

            # change expireColor success from darkgray to darkgreen for PASS indicators
            $expiryColor = $thisFail ? "DarkRed" : ($thisWarn ? "DarkYellow" : "DarkGreen")

            $message = "<    Certificate <.>40> $($thisFail ? "FAIL" : ($thisWarn ? "WARN" : "PASS"))"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$expiryColor

            if ($thisWarn -or $thisFail) {
                Send-SSLCertificateExpiryMessage -Certificate $ProtocolStatus.Certificate
            }

            $thisWarn = $false
            $thisFail = $false

            foreach ($signatureAlgorithm in $bestPractice.signatureAlgorithms) {
                $thisFail = $ProtocolStatus.SignatureAlgorithm -ne $signatureAlgorithm
                $fail = $fail -or $thisFail
                $message = "<    Signature Algorithm <.>40> $($thisFail ? "FAIL" : "PASS")"
                Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($thisFail ? "DarkRed" : "DarkGreen")
            }

            $thisWarn = $false
            $thisFail = $false

            foreach ($protocol in $supportedProtocols) {
                $thisFail = $bestPractice.protocols.$protocol.state -ne "" ? $ProtocolStatus.$protocol -ne ($bestPractice.protocols.$protocol.state -eq "Enabled") : $false
                $fail = $fail -or $thisFail
                $state = $bestPractice.protocols.$protocol.state -ne "" ? $($bestPractice.protocols.$protocol.state -eq "Enabled" ? "Enabled" : "Disabled") : $($ProtocolStatus.$protocol ? "Enabled" : "Disabled")
                $result = $bestPractice.protocols.$protocol.state -ne "" ? $($thisFail ? "FAIL": "PASS") : "NA"
                $message = "<    $($bestPractice.protocols.$protocol.displayName) <.>31> $(($state.ToUpper() + " ").Substring(0,8))/$result"
                $stateColor = $state -eq "ENABLED" ? "DarkGreen" : "DarkRed"
                $resultColor = $result -ne "NA" ? $thisFail ? "DarkRed" : "DarkGreen" : "DarkGray"
                Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$stateColor,DarkGray,$resultColor
            }

            $thisWarn = $false
            $thisFail = $false

            $messagePart = "  SSL Protocol ","$($ComputerName)"
            Write-Host+ -NoTrace -NoSeparator $messagePart[0],"[",$messagePart[1],"] ",(Format-Leader -Length 48 -Adjust ((($messagePart -join " ").Length+2)))," $($fail ? "FAIL" : ($warn ? "WARN" : "PASS"))" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,$expiryColor
            Write-Log -Action "Test" -Target "SSL" -Status $($fail ? "FAIL" : ($warn ? "WARN" : "PASS"))
        
            # return [PSCustomObject]$ProtocolStatus
        }

    }

#endregion TESTS
#region MISC

    function global:Get-PlatformCimInstance {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$View
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $PlatformServices = Get-PlatformService -ErrorAction SilentlyContinue
        $PlatformProcesses = Get-PlatformProcess -ErrorAction SilentlyContinue
        $PlatformTasks = Get-PlatformTask -ErrorAction SilentlyContinue
        $platformCimInstance = [array]$PlatformServices + [array]$PlatformProcesses + [array]$PlatformTasks

        return $platformCimInstance  | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)

    }

    function global:Copy-Object {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0,ValueFromPipeline)][object]$InputObject
        )

        begin {
            $outputObject = @()
        }
        process {
            $outputObject += $InputObject
        }
        end {
            # return $outputObject  | ConvertTo-Json -Depth 99 | ConvertFrom-Json -Depth 99
            return [System.Management.Automation.PSSerializer]::Deserialize(
                [System.Management.Automation.PSSerializer]::Serialize(
                    $InputObject
                )
            )
        }

    }

    function global:Get-PSSession+ {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME,
            [switch]$All
        )

        if ($All) {return Get-PSSession}

        $allSessions = @()
        foreach ($node in $ComputerName) {
            $psSession = $null
            $nodeIsLocalhost = $node.ToLower() -eq "localhost" -or $node.ToLower() -eq $env:COMPUTERNAME.ToLower()
            $psSessions = $nodeIsLocalhost ? (Get-PSSession | Where-Object {$_.ComputerName.ToLower() -eq "localhost"}) : (Get-PSSession -ComputerName $node)
            $psSessions = $psSessions | Sort-Object -Property @{Expression = "State"; Descending = $true}, @{Expression = "Availability"; Descending = $false}
            foreach ($nodePSSession in $psSessions) {
                if ($null -ne $nodePSSession -and 
                    ($nodePSSession.Availability -eq [System.Management.Automation.Runspaces.RunspaceAvailability]::Available)) {
                    #   -or $nodePSSession.Availability -eq [System.Management.Automation.Runspaces.RunspaceAvailability]::None)) {
                        $psSession = $nodePSSession
                        break
                }
            }
            if ($null -eq $psSession) {
                $psSession = New-PSSession -ComputerName $node -ErrorAction SilentlyContinue
                if ($null -eq $psSession -and $nodeIsLocalhost) {
                    $psSession = New-PSSession -EnableNetworkAccess
                }
            }
            # if ($psSession.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Disconnected) {
            #     Connect-PSSession -Session $psSession | Out-Null
            # }
            $allSessions += $psSession
        }

        return $allSessions

    }

    function global:ConvertTo-Hashtable {

        # Author: Adam Bertram
        # Reference: https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/

        [CmdletBinding()]
        [OutputType('hashtable')]
        param (
            [Parameter(ValueFromPipeline)]
            $InputObject
        )
    
        process {
            ## Return null if the input is null. This can happen when calling the function
            ## recursively and a property is null
            if ($null -eq $InputObject) {
                return $null
            }
    
            ## Check if the input is an array or collection. If so, we also need to convert
            ## those types into hash tables as well. This function will convert all child
            ## objects into hash tables (if applicable)
            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                $collection = @(
                    foreach ($object in $InputObject) {
                        ConvertTo-Hashtable -InputObject $object
                    }
                )
    
                ## Return the array but don't enumerate it because the object may be pretty complex
                Write-Output -NoEnumerate $collection
            } elseif ($InputObject -is [psobject]) { ## If the object has properties that need enumeration
                ## Convert it to its own hash table and return it
                $hash = @{}
                foreach ($property in $InputObject.PSObject.Properties) {
                    $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
                }
                $hash
            } else {
                ## If the object isn't an array, collection, or other object, it's already a hash table
                ## So just return it.
                $InputObject
            }
        }
    }

    function global:ConvertFrom-XmlElement {

        [CmdletBinding()]
        [OutputType('hashtable')]
        param (
            [Parameter(ValueFromPipeline)]
            $InputObject
        )
    
        process {

            if ($null -eq $InputObject) {
                return $null
            }
    
            if ($InputObject -is [System.Xml.XmlElement]) {
                $InputObject | ConvertFrom-Xml
            }
            elseif ($InputObject -is [hashtable]) {
                $ht = @{}
                foreach ($key in $InputObject.Keys) {
                    $ht.$key = ConvertFrom-XmlElement -InputObject $InputObject.$key
                }
                $ht
            }
            elseif ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                $collection = @(
                    foreach ($object in $InputObject) {
                        ConvertFrom-XmlElement -InputObject $object
                    }
                )
                Write-Output -NoEnumerate $collection
            } else {
                $InputObject
            }
        }
    }

    function global:ConvertFrom-XML {
        
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory = $true, ValueFromPipeline)]
            [System.Xml.XmlNode]$node, #we are working through the nodes
            [string]$Prefix='',#do we indicate an attribute with a prefix?
            $ShowDocElement=$false #Do we show the document element? 
        )
        process
        {   #if option set, we skip the Document element
            if ($node.DocumentElement -and !($ShowDocElement)) 
                { $node = $node.DocumentElement }
            $oHash = [ordered] @{ } # start with an ordered hashtable.
            #The order of elements is always significant regardless of what they are
            write-verbose "calling with $($node.LocalName)"
            if ($null -ne $node.Attributes) #if there are elements
            # record all the attributes first in the ordered hash
            {
                $node.Attributes | ForEach-Object {
                    $oHash.$($Prefix+$_.FirstChild.parentNode.LocalName) = $_.FirstChild.value
                }
            }
            # check to see if there is a pseudo-array. (more than one
            # child-node with the same name that must be handled as an array)
            $node.ChildNodes | #we just group the names and create an empty
            #array for each
            Group-Object -Property LocalName | Where-Object { $_.count -gt 1 } | Select-Object Name |
            ForEach-Object{
                write-verbose "pseudo-Array $($_.Name)"
                $oHash.($_.Name) = @() <# create an empty array for each one#>
            };
            foreach ($child in $node.ChildNodes)
            {#now we look at each node in turn.
                write-verbose "processing the '$($child.LocalName)'"
                $childName = $child.LocalName
                if ($child -is [system.xml.xmltext])
                # if it is simple XML text 
                {
                    write-verbose "simple xml $childname";
                    $oHash.$childname += $child.InnerText
                }
                # if it has a #text child we may need to cope with attributes
                elseif ($child.FirstChild.Name -eq '#text' -and $child.ChildNodes.Count -eq 1)
                {
                    write-verbose "text";
                    if ($null -ne $child.Attributes) #hah, an attribute
                    {
                        <#we need to record the text with the #text label and preserve all
                        the attributes #>
                        $aHash = [ordered]@{ };
                        $child.Attributes | ForEach-Object {
                            $aHash.$($_.FirstChild.parentNode.LocalName) = $_.FirstChild.value
                        }
                        #now we add the text with an explicit name
                        $aHash.'#text' += $child.'#text'
                        $oHash.$childname += $aHash
                    }
                    else
                    { #phew, just a simple text attribute. 
                        $oHash.$childname += $child.FirstChild.InnerText
                    }
                }
                elseif ($null -ne $child.'#cdata-section')
                # if it is a data section, a block of text that isnt parsed by the parser,
                # but is otherwise recognized as markup
                {
                    write-verbose "cdata section";
                    $oHash.$childname = $child.'#cdata-section'
                }
                elseif ($child.ChildNodes.Count -gt 1 -and 
                            ($child | Get-Member -MemberType Property).Count -eq 1)
                {
                    $oHash.$childname = @()
                    foreach ($grandchild in $child.ChildNodes)
                    {
                        $oHash.$childname += (ConvertFrom-XML $grandchild)
                    }
                }
                else
                {
                    # create an array as a value  to the hashtable element
                    $oHash.$childname += (ConvertFrom-XML $child)
                }
            }
            $oHash
        }
    } 

    function global:Get-CmdletParameterAliasUsed {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Parameter
        )
    
        $callStack = Get-PSCallStack
        $callerInvocationInfo = $callStack[1].InvocationInfo
    
        $aliasUsed = $Parameter
        $aliasDefined = $callerInvocationInfo.MyCommand.Parameters[$Parameter].Aliases
        if ($callerInvocationInfo.Line -match "\s-($($aliasDefined -join '|'))\s") {
            foreach ($alias in $aliasDefined) {
                if ($alias -eq $Matches[1]) {$aliasUsed = $alias}
            }
        }
    
        return $aliasUsed
    
    }

    function global:Set-CursorVisible {

        try { [console]::CursorVisible = $true }
        catch {}

    }

    function global:Set-CursorInvisible {

        try { [console]::CursorVisible = $false }
        catch {}

    }

#endregion MISC