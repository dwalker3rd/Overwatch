[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls11  

#region OVERWATCH

    function global:Get-EnvironConfig {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Key,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
        )

        # find the environ.ps1 file on the remote node
        $environFile = [FileObject]::new("environ.ps1",$ComputerName)

        # if node is not an overwatch controller, use the settings from the overwatch controller
        # note: for now, the overwatch controller is assumed to be the local machine
        if (!$environFile.Exists()) { 
            $ComputerName = $env:COMPUTERNAME
            $environFile = [FileObject]::new("environ.ps1",$ComputerName)
        }

        # get the content from the environ.ps1 file, mod the content to not be global, execute the content
        $environFileContent = Get-Content $environFile.Path
        $environFileContent = $environFileContent.Replace("global:","")
        $environLocationRoot = (Select-String $environFile.Path -Pattern "Root = " -Raw).Trim().Split(" = ")[1].Replace('"','')
        $environFileContent = $environFileContent.Replace($environLocationRoot, ([FileObject]::new($environLocationRoot,$ComputerName)).Path)
        Invoke-Expression ($environFileContent | Out-String)

        # see if the key is defined in environ.ps1
        $result = Invoke-Expression "`$$Key"

        # if key not defined in environ.ps1, search definition files (/definitions/definition-*.ps1)
        if (!$result) {
            # search must result in a SINGLE file
            $definitionFile = (Select-String -Pattern $Key -SimpleMatch -Path "$($Location.Definitions)\definitions-*.ps1" -List)[0]
            if ($definitionFile) {
                $definitionFileContent = Get-Content $definitionFile.Path
                $definitionFileContent = $definitionFileContent.Replace("global:","")
                Invoke-Expression ($definitionFileContent | Out-String)
            }

        }

        return Invoke-Expression "`$$Key"

    }

    function global:Get-Product {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [switch]$ResetCache,
            [switch]$ReadOnly
        )

        # if this is a remote query, then ...
        # 1) disallow cache reset
        # 2) use -MinimumDefinitions switch with definitions file

        $remoteQuery = $ComputerName -ne $env:COMPUTERNAME
        $ResetCache = $remoteQuery ? $false : $ResetCache

        $products = @()
        if (!$ResetCache) {
            if ($(get-cache products -ComputerName $ComputerName).Exists()) {
                $products = Read-Cache products -ComputerName $ComputerName #-MaxAge $(New-Timespan -Minutes 2)
            }
        }

        # persist $global:Product
        $productClone = $global:Product ? $($global:Product | Copy-Object) : $null

        # this method overwrites $global:Product so clone $global:Product
        if (!$products) {

            $products = @()
            (Get-EnvironConfig -Key Environ.Product -ComputerName $ComputerName) | ForEach-Object {
                Write-Host+ -IfDebug -NoTrace $_
                $productDefinitionFile = "$(Get-EnvironConfig -Key Location.Definitions -ComputerName $ComputerName)\definitions-product-$($_).ps1"
                if (Test-Path -Path $productDefinitionFile) {
                    $params = @{}
                    $params.ScriptBlock = { . $productDefinitionFile }
                    if ($remoteQuery) {
                        $params.Session = Use-PSSession+ -ComputerName $ComputerName
                        $params.ScriptBlock = { . $using:productDefinitionFile -MinimumDefinitions }
                    }
                    $_product = Invoke-Command @params
                    $_product.IsInstalled = $true
                    $products += $_product
                }
            }

            if (!$remoteQuery) {
                $products | Write-Cache products -ComputerName $ComputerName
            }
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
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [switch]$ResetCache,
            [switch]$ReadOnly
        )

        # if this is a remote query, then ...
        # 1) disallow cache reset
        # 2) use -MinimumDefinitions switch with definitions file

        $remoteQuery = $ComputerName -ne $env:COMPUTERNAME
        $ResetCache = $remoteQuery ? $false : $ResetCache

        $providers = @()
        if (!$ResetCache) {
            if ($(get-cache providers).Exists()) {
                $providers = Read-Cache providers # -MaxAge $(New-Timespan -Minutes 2)
            }
        }
        
        if (!$providers) {

            $providers = @()
            (Get-EnvironConfig -Key Environ.Provider -ComputerName $ComputerName) | ForEach-Object {
                Write-Host+ -IfDebug -NoTrace $_
                $providerDefinitionFile = "$(Get-EnvironConfig -Key Location.Definitions -ComputerName $ComputerName)\definitions-provider-$($_).ps1"
                if (Test-Path -Path $providerDefinitionFile) {
                    $params = @{}
                    $params.ScriptBlock = { . $providerDefinitionFile }
                    if ($remoteQuery) {
                        $params.Session = Use-PSSession+ -ComputerName $ComputerName
                        $params.ScriptBlock = { . $using:providerDefinitionFile -MinimumDefinitions }
                    }
                    $_provider = Invoke-Command @params
                    $_provider.IsInstalled = $true
                    $providers += $_provider
                }
            }

            if (!$remoteQuery) {
                $providers | Write-Cache providers -ComputerName $ComputerName
            }

        }

        if ($Name) {$providers = $providers | Where-Object {$_.Name -eq $Name}}
        if ($Id) {$providers = $providers | Where-Object {$_.Id -eq $Id}}

        return $providers
    }

#region CATALOG

    function global:Get-Catalog {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][ValidateSet("OS","Platform","Product","Provider")][string]$Type,
            [Parameter(Mandatory=$false,Position=0)][string]$Name
        )

        if ([string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Name)) {

            if ($global:Catalog.OS.$Name) {
                $Type = "OS"
            }
            if ($global:Catalog.Platform.$Name) {
                if ($Type) {
                    throw "Catalog contains multiple objects with the name `"$Name`""
                }
                $Type = "Platform"
            }
            if ($global:Catalog.Product.$Name) {
                if ($Type) {
                    throw "Catalog contains multiple objects with the name `"$Name`""
                }
                $Type = "Product"
            }
            if ($global:Catalog.Provider.$Name) {
                if ($Type) {
                    throw "Catalog contains multiple objects with the name `"$Name`""
                }
                $Type = "Provider"
            }

            if ([string]::IsNullOrEmpty($Type)) {
                throw "Catalog $($Type ? $Type.ToLower() : "object") `"$Name`" was not found"
            }

        }
        if (![string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Name)) {

            if (!$global:Catalog.$Type.$Name) {
                throw "Catalog $($Type.ToLower()) `"$Name`" was not found"
            }

        }

        $catalogObjects = $null
        if (![string]::IsNullOrEmpty($Name)) {
            $catalogObjects = $global:Catalog.$Type.$Name
        }
        elseif (![string]::IsNullOrEmpty($Type)) { 
            $catalogObjects = @()
            $catalogObjects += $global:Catalog.$Type.values
        }
        else {
            $catalogObjects = @{}
            foreach ($key in $global:Catalog.Keys) {
                $catalogObjects += @{ $key = [array]$global:Catalog.$key.values }
            }
        }

        return $catalogObjects

    }

    function global:Get-CatalogDependents {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Type,
            [Parameter(Mandatory=$true,Position=1)][string]$Name,
            [switch]$Installed
        )

        $catalogObject = $global:Catalog.$Type.$Name
        if (!$catalogObject) {
            Write-Host+ -NoTimestamp -NoTrace "NOTFOUND: A $($Type.ToLower()) named $($Name) was not found in the catalog." -ForegroundColor Red
            return
        }

        $dependencies = @()
        foreach ($key in $global:Catalog.Keys) {
            foreach ($subKey in $global:Catalog.$key.Keys) {
                if ([array]$global:Catalog.$key.$subKey.Installation.Prerequisite.$Type -contains $Name) { 
                    $_obj = switch ($key) {
                        "OS" { Get-EnvironConfig Environ.OS }
                        "Platform" { Get-EnvironConfig Environ.Platform }
                        "Product" { 
                            $_product = Get-Product $subKey 
                            if (!$_product.IsInstalled -and $Installed) { continue }
                            $_product
                        }
                        "Provider" {
                            $_provider = Get-Provider $subKey 
                            if (!$_provider.IsInstalled -and $Installed) { continue }
                            $_provider
                        }
                        default { $null }
                    }
                    $dependencies += [PSCustomObject]@{
                        Type = $key
                        Name = $subKey
                        Object = $_obj
                    }
                }
            }
        }

        return $dependencies

    }

    function global:Get-CatalogDependencies {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Type,
            [Parameter(Mandatory=$true,Position=1)][string]$Name,
            [switch]$Installed
        )

        $catalogObject = $global:Catalog.$Type.$Name
        if (!$catalogObject) {
            Write-Host+ -NoTimestamp -NoTrace "NOTFOUND: A $($Type.ToLower()) named $($Name) was not found in the catalog." -ForegroundColor Red
            return
        }

        $dependencies = @()
        foreach ($key in $global:Catalog.$Type.$Name.Installation.Prerequisite.Keys) {
            foreach ($subKey in $global:Catalog.$Type.$Name.Installation.Prerequisite[$key]) {
                $_obj = switch ($key) {
                    "OS" { Get-EnvironConfig Environ.OS }
                    "Platform" { Get-EnvironConfig Environ.Platform }
                    "Product" { 
                        $_product = Get-Product $subKey 
                        if (!$_product.IsInstalled -and $Installed) { continue }
                        $_product
                    }
                    "Provider" {
                        $_provider = Get-Provider $subKey 
                        if (!$_provider.IsInstalled -and $Installed) { continue }
                        $_provider
                    }
                    default { $null }
                }
                $dependencies += [PSCustomObject]@{
                    Type = $key
                    Name = $subKey
                    Object = $_obj
                }
            }
        }

        return $dependencies

    }

#endregion CATALOG

#endregion OVERWATCH
#region PLATFORM

    #region STATUS

        function global:Get-PlatformStatus {
                
            [CmdletBinding()]
            param (
                [switch]$ResetCache,
                [switch]$CacheOnly
            )

            # The $ResetCache switch is only for the platform-specific Get-PlatformStatusRollup
            # function and is *** NOT *** to be used for the platformstatus cache
            if ((get-cache platformstatus).Exists()) {
                $platformStatus = [PlatformStatus](Read-Cache platformStatus)
                # The $CacheOnly switch allows a faster return for those callers that 
                # don't need updated platform-specific status. par example:  Show-PlatformEvent
                if ($CacheOnly) { return $platformStatus }
            }

            if (!$platformStatus) {
                $platformStatus = [PlatformStatus]::new()
            }

            # The $ResetCache switch is only for the platform-specific Get-PlatformStatusRollup
            # function and is *** NOT *** to be used for the platformstatus cache
            $params = @{}
            if ($ResetCache) {$params += @{ResetCache = $true}}
            $platformStatus.IsOK, $platformStatus.RollupStatus, $platformStatus.Issues, $platformStatus.StatusObject = Get-PlatformStatusRollup @params

            if ($platformStatus.RollupStatus -eq "Unavailable") {
                return $platformStatus
            }

            # this assumes that $platformStatus.Event is the same as the platform state
            # TODO: manage events if $platformStatus doesn't match platform state
            # how is Overwatch handling when the platform state is restarting b/c that's a STOP and START event
            if ($platformStatus.RollupStatus -in @("Stopping","Starting","Restarting") -and !$platformStatus.Event) {
                $command = switch ($platformStatus.RollupStatus) {
                    "Stopping" {"Stop"}
                    default {$platformStatus.RollupStatus -replace "ing",""}
                }
                Set-PlatformEvent -Event $command -Context "Unknown" -EventReason "Unknown" -EventStatus $global:PlatformEventStatus.InProgress -PlatformStatus $platformStatus
            }

            $platformCimInstance = Get-PlatformCimInstance
            
            $isOK = $platformStatus.IsOK
            $platformCimInstance | Where-Object {$_.Class -in 'Service'} | ForEach-Object {
                $isOK = $isOK -and ($_.Required ? $_.IsOK : $true)
            }

            $platformStatus.Intervention = $false
            $platformStatus.InterventionReason = $null                    

            if (!$isOK) {
                if ($platformStatus.IsStopped) {

                    $productShutdownTimeout = $(Get-Product -Id $platformStatus.EventCreatedBy).ShutdownMax
                    $shutdownTimeout = $productShutdownTimeout.TotalMinutes -gt 0 ? $productShutdownTimeout : $PlatformShutdownMax
                    $stoppedDuration = New-TimeSpan -Start $platformStatus.EventCreatedAt
                    $IsStoppedTimeout = $stoppedDuration.TotalMinutes -gt $shutdownTimeout.TotalMinutes

                    $isOK = !$IsStoppedTimeout
                    $platformStatus.IsStoppedTimeout = $IsStoppedTimeout

                    if ($IsStoppedTimeout) {
                        $platformStatus.Intervention = $true
                        $platformStatus.InterventionReason = "Platform STOP duration $($stoppedDuration.TotalMinutes) minutes."
                    }
            
                }
            }         

            $platformStatus.IsOk = $isOK

            # this overrides $platformStatus.IsStopped
            # TODO: as above, manage events if $platformStatus doesn't match platform state
            $platformStatus.IsStopped = $platformStatus.RollupStatus -in $ServiceDownState
            
            $platformStatus.ByCimInstance = $platformCimInstance

            # an event failed intervention will overwrite a stopped timeout intervention (above)
            # currently there are two interventions.  new interventions will require a priority scheme
            if ($platformStatus.EventStatus -eq $PlatformEventStatus.Failed) {
                $platformStatus.Intervention = $true
                $platformStatus.InterventionReason = "Platform $($platformStatus.Event.ToUpper()) has $($platformStatus.EventStatus.ToUpper())"
            }

            # update timestamp for active event
            if ($platformStatus.Event) {
                $platformStatus.EventUpdatedAt = [datetime]::Now
            }
            
            # platform has reached EventStatusTarget for the current event
            if ($platformStatus.RollupStatus -eq $platformStatus.EventStatusTarget) {
                    $platformStatus.EventHasCompleted = $true
                    $platformStatus.EventStatus = $PlatformEventStatus.Completed
                    $platformStatus.EventCompletedAt = [datetime]::Now
            }

            $platformStatus | Write-Cache platformstatus

            return $platformStatus

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
                [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
                [Parameter(Mandatory=$true)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Status = "Running",
                [Parameter(Mandatory=$false)][int]$WaitTimeInSeconds = 60,
                [Parameter(Mandatory=$false)][int]$TimeOutInSeconds = 0
            )
            
            $totalWaitTimeInSeconds = 0
            $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
            while ($service.Status -ne $Status) {
                Start-Sleep -Seconds $WaitTimeInSeconds
                $totalWaitTimeInSeconds += $WaitTimeInSeconds
                if ($TimeOutInSeconds -gt 0 -and $totalWaitTimeInSeconds -ge $TimeOutInSeconds) {
                    return $false
                }
                $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
            }
        
            return $true
        
        }

    #endregion SERVICES

#endregion PLATFORM
#region TESTS

    function global:Get-IpAddress {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)][string]$ComputerName
        )

        return (Resolve-DnsName $ComputerName).IPAddress

    }

    function global:Test-Connections {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Keys)
        )

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

        $leader = Format-Leader -Length 47 -Adjust ((("  Powershell Remoting").Length))
        Write-Host+ -NoTrace "  Powershell Remoting",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray
        Write-Log -Action "Test" -Target "Powershell-Remoting"

        $fail = $false
        foreach ($node in (Get-PlatformTopology nodes -Online -Keys)) {

            # Write-Host+ -NoNewline -NoTimestamp -NoTrace "." -ForegroundColor DarkGray

            $leader = Format-Leader -Length 39 -Adjust ((("    Remote to $($node)").Length))
            Write-Host+ -NoTrace -NoNewLine "    Remote to","$($node)",$leader -ForegroundColor Gray,DarkBlue,DarkGray

            try {
                $psSession = New-PSSession+ -ComputerName $node
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

    function global:IsLocalHost {

        [CmdletBinding()]
        [OutputType('bool')]
        param(
            [Parameter(Mandatory=$true)][string]$ComputerName
        )
        return $ComputerName.ToLower() -eq $env:COMPUTERNAME.ToLower()
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