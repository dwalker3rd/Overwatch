. "$($global:Location.Definitions)\classes.ps1"

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls13

#region OVERWATCH

    function global:Get-OverwatchGlobalVariables {
        
        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Type,
            [Parameter(Mandatory=$false)][ValidateSet("Global","Local")][string]$Scope = "Global",
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
        )

        if ($ComputerName -eq $env:COMPUTERNAME -and [string]::IsNullOrEmpty($Path)) {
            
            $result = Invoke-Expression "`$$($Scope):$($Type)"

        }
        else {

            $remoteOverwatchRoot = Get-EnvironConfig -Key Location.Root -ComputerName $ComputerName
            if (![string]::IsNullOrEmpty($remoteOverwatchRoot)) {

                # this is a sandbox, so instead of the usual pssession reuse pattern,
                # create a new session, make the remoting call, and delete the session
                $psSession = New-PSSession+ -ComputerName $ComputerName

                try {
                    $result = Invoke-Command -Session $psSession -ScriptBlock {
                        Set-Location $using:remoteOverwatchRoot
                        . $using:remoteOverwatchRoot/definitions.ps1 -MinimumDefinitions
                        Invoke-Expression "`$$($using:Scope):$($using:Type)"
                    } 
                }
                catch {}             
                finally {       

                    $typedResult = New-Object -Type $Type
                    foreach ($property in $typedResult.PSObject.Properties.Name) {
                        $typedResult.$property = $result.$property
                    }
                    $result = $typedResult   
                    
                }

                Remove-PSSession+ -Session $psSession

            }
        }

        if (!$result) { 
            throw "Overwatch object `$$($Scope):$($Type) was NOT FOUND on node $ComputerName"
        }            

        return $result

    }

    function global:Get-EnvironConfig {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Key,
            [Parameter(Mandatory=$false)][ValidateSet("Global","Local")][string]$Scope,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [Parameter(Mandatory=$false)][string]$Path
        )

        if ($ComputerName -eq $env:COMPUTERNAME -and [string]::IsNullOrEmpty($Path)) {
            Invoke-Expression "`$$($Scope):$($Key)"
            return
        }

        try {

            # this is a sandbox, so instead of the usual pssession reuse pattern,
            # create a new session, make the remoting call, and delete the session
            $psSession = New-PSSession+ -ComputerName $ComputerName

            if ([string]::IsNullOrEmpty($Path)) {
                $overwatchRegistryPath = (Get-Catalog -Uid Overwatch.Overwatch).Installation.Registry.Path
                $overwatchRegistryKey = "InstallLocation"
                $overwatchRoot = Invoke-Command -Session $psSession -ErrorAction SilentlyContinue -ScriptBlock {
                    Get-ItemPropertyValue -Path $using:overwatchRegistryPath -Name $using:overwatchRegistryKey
                } 
                if ([string]::IsNullOrEmpty($overwatchRoot)) { 
                    $errorMessage = (Get-Error).Exception.Message -replace [regex]::Escape($overwatchRegistryPath), "\\$ComputerName\$overwatchRegistryPath"
                    throw $errorMessage
                }
                $Path = "$overwatchRoot\environ.ps1"
            }
            
            # find the environ.ps1 file on the remote node
            $environFile = [FileObject]::new($Path,$ComputerName)
            if (!$environFile.Exists) {
                throw "Cannot find path `'$($environFile.FullName)`' because it does not exist."
             }
            
            $result = Invoke-Command -Session $psSession -ScriptBlock {
                . $using:environFile.FullName
                Invoke-Expression "`$$using:Key"
            }

        }
        catch {

            Write-Host+ -IfDebug -NoTimestamp "$($_.Exception.Message)" -Foreground Red
            $result = $null

        }
        finally {

            Remove-PSSession+ -Session $psSession

        }


        return $result

    } 

#endregion OVERWATCH
#region OS

    function global:Get-OS {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
        )

        return (Get-OverwatchGlobalVariables -Type OS -ComputerName $ComputerName)
        
    }

#endregion OS
#region PRODUCTS

    function global:Get-Product {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [switch]$ResetCache,
            [switch]$NoCache
        )

        # if this is a remote query, then ...
        # 1) disallow cache reset
        # 2) use -MinimumDefinitions switch with definitions file

        $remoteQuery = $ComputerName -ne $env:COMPUTERNAME
        $ResetCache = $remoteQuery ? $false : $ResetCache

        $products = @()
        if (!$ResetCache -and !$NoCache) {
            if ($(Get-Cache products -ComputerName $ComputerName).Exists) {
                $products = Read-Cache products -ComputerName $ComputerName #-MaxAge $(New-Timespan -Minutes 2)
            }
        }
        if ($Id) {$products = $products | Where-Object {$_.Id -eq $Id}}

        # persist $global:Product
        $productClone = $global:Product ? $($global:Product | Copy-Object) : $null

        # this method overwrites $global:Product so clone $global:Product
        if (!$products) {
            
            $definitionsPath = $global:Location.Definitions
            if ($ComputerName -ne $env:COMPUTERNAME) {
                $definitionsPath = Get-EnvironConfig -Key Location.Definitions -ComputerName $ComputerName
            }

            $_installedProducts = ![string]::IsNullOrEmpty($Id) ? $Id : (Get-EnvironConfig -Key Environ.Product -ComputerName $ComputerName)

            $products = @()
            foreach ($_product in $_installedProducts) {
                $productDefinitionFilePath = ([FileObject]::new("$definitionsPath\definitions-product-$($_product).ps1", $ComputerName)).FullName
                if (Test-Path -Path $productDefinitionFilePath) {
                    $params = @{}
                    $params.ScriptBlock = { . $productDefinitionFilePath }
                    if ($remoteQuery) {
                        $params.Session = Use-PSSession+ -ComputerName $ComputerName
                        $params.ScriptBlock = { $__product = . $using:productDefinitionFilePath -MinimumDefinitions; $__product.Refresh(); $__product }
                    }
                    $_product = Invoke-Command @params
                    $products += $_product
                }
            }

            # if (!$remoteQuery) {
                $products | Write-Cache products -ComputerName $ComputerName
            # }
        }

        # reset $global:Product with clone
        $global:Product = $productClone

        return $products | Select-Object -Property $($View ? $ProductView.$($View) : $ProductView.Default)
    }

    # $global:logLockObject = $false

#endregion PRODUCTS
#region PROVIDERS

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
            if ($(Get-Cache providers).Exists) {
                $providers = Read-Cache providers # -MaxAge $(New-Timespan -Minutes 2)
            }
        }
        if ($Id) {$providers = $providers | Where-Object {$_.Id -eq $Id}}
        
        if (!$providers) {

            $definitionsPath = $global:Location.Definitions
            if ($ComputerName -ne $env:COMPUTERNAME) {
                $definitionsPath = Get-EnvironConfig -Key Location.Definitions -ComputerName $ComputerName
            }

            $_installedProviders = ![string]::IsNullOrEmpty($Id) ? $Id : (Get-EnvironConfig -Key Environ.Provider -ComputerName $ComputerName)

            $providers = @()
            foreach ($_provider in $_installedProviders) {
                $providerDefinitionFilePath = ([FileObject]::new("$definitionsPath\definitions-provider-$($_provider).ps1", $ComputerName)).FullName
                if (Test-Path -Path $providerDefinitionFilePath) {
                    $params = @{}
                    $params.ScriptBlock = { . $providerDefinitionFilePath }
                    if ($remoteQuery) {
                        $params.Session = Use-PSSession+ -ComputerName $ComputerName
                        $params.ScriptBlock = { $__provider = . $using:providerDefinitionFilePath -MinimumDefinitions; $__provider.Refresh(); $__provider }
                    }
                    $_provider = Invoke-Command @params
                    $providers += $_provider
                }
            }

            if (!$remoteQuery) {
                $providers | Write-Cache providers -ComputerName $ComputerName
            }

        }

        return $providers | Select-Object -Property $($View ? $ProviderView.$($View) : $ProviderView.Default)
    }

#endregion PROVIDERS
#region CATALOG

    function global:Get-Catalog {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][ValidatePattern("^(\w*?)\.{1}(\w*?)$")][string]$Uid,
            [Parameter(Mandatory=$false)][string]$Type = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[0]}),
            [Parameter(Mandatory=$false)][string]$Id = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[1]}),
            [switch]$AllowDuplicates,
            [switch]$Installed,
            [switch]$NotInstalled,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
        )

        $remoteQuery = $ComputerName -ne $env:COMPUTERNAME
        
        $catalogObjectExpressions = @()

        $catalogObjectExpressionsUid = ""
        if (![string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Id)) {
            $catalogObjectExpressions += "`$global:Catalog.$Type.`"$Id`""
            $catalogObjectExpressionsUid = "Type.Id"
        }
        elseif (![string]::IsNullOrEmpty($Type) -and [string]::IsNullOrEmpty($Id)) { 
            $catalogObjectExpressions += "`$global:Catalog.$Type"
            $catalogObjectExpressionsUid = "Type"
        }
        elseif ([string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Id)) { 
            $params = @{ Id = $Id; AllowDuplicates = $AllowDuplicates.IsPresent }
            if ($PSBoundParameters.ErrorAction) {$params += @{ ErrorAction = $PSBoundParameters.ErrorAction }}
            $catalogObjectExpressions += "`$global:Catalog.$((Search-Catalog @params).object).`"$Id`""
            $catalogObjectExpressionsUid = "Type.Id"
        }
        else {
            $catalogObjectExpressions += "`$global:Catalog"
            $catalogObjectExpressionsUid = "Catalog"
        }

        $_catalogObjects = @()

        if ($remoteQuery) {

            $remoteOverwatchRoot = Get-EnvironConfig -Key Location.Root -ComputerName $ComputerName
            if (![string]::IsNullOrEmpty($remoteOverwatchRoot)) {

                # this is a sandbox, so instead of the usual pssession reuse pattern,
                # create a new session, make the remoting call, and delete the session
                $psSession = New-PSSession+ -ComputerName $ComputerName

                foreach ($catalogObjectExpression in $catalogObjectExpressions) {
                    try {
                        $_catalogObjects += Invoke-Command -Session $psSession -ScriptBlock {
                            Set-Location $using:remoteOverwatchRoot
                            . $using:remoteOverwatchRoot/definitions.ps1 -MinimumDefinitions
                            $catalogObject = Invoke-Expression $using:catalogObjectExpression
                            $catalogObject
                        }
                    }
                    catch {}                    
                }

                Remove-PSSession+ -Session $psSession

            }
            
        }
        else {
            foreach ($catalogObjectExpression in $catalogObjectExpressions) {
                $_catalogObjects += Invoke-Expression $catalogObjectExpression
            }
        }

        $__catalogObjects = @()
        switch ($catalogObjectExpressionsUid) {
            "Type" {
                foreach ($skey in $_catalogObjects.Keys) {
                    $__catalogObjects += $_catalogObjects.$skey
                }
            }
            "Catalog" {
                foreach ($pkey in $_catalogObjects.Keys) {
                    foreach ($skey in $_catalogObjects.$pkey.Keys) {
                        $__catalogObjects += $_catalogObjects.$pkey.$skey
                    }
                }
            }
            default {
                $__catalogObjects += $_catalogObjects
            }
        }

        $catalogObjects = @()
        if ($remoteQuery) {
            # remote objects are returned as pscustomobjects, so retype
            foreach ($__catalogObject in $__catalogObjects) {
                $catalogObjects += Invoke-Expression "`$__catalogObject -as [$($__catalogObject.Type)]"
            }
        }
        else {
            $catalogObjects += $__catalogObjects
        }

        if ($remoteQuery){
            $environKeyValues = Get-EnvironConfig -Key Environ.$Type -ComputerName $ComputerName
            foreach ($catalogObject in $catalogObjects) {

                # this is clumsy: need a better way to determine if an object is installed or running
                switch ($catalogObject.Type) {
                    # "Driver" {
                    #     $_installedDrivers = (Invoke-Expression "Get-$($catalogObject.DriverType)InstalledDrivers -Name `"$($catalogObject.Id)`" -ComputerName $ComputerName")
                    #     $catalogObject.Installed = $catalogObject.Id -in $_installedDrivers.Name
                    #     continue
                    # }
                    {$_ -in @("CLI","Installer")} {
                        $catalogObject.Installed = Invoke-Command $global:Catalog.$($catalogObject.Type).$($catalogObject.Id).Installation.IsInstalled -ComputerName $ComputerName
                        continue
                    }
                    "default" {
                        $_.Refresh($environKeyValues)
                        continue
                    }
                }

            }
        }
        else {
            foreach ($catalogObject in $catalogObjects) {

                # this is clumsy: need a better way to determine if an object is installed or running
                switch ($catalogObject.Type) {
                    # "Driver" {
                    #     $_installedDrivers = (Invoke-Expression "Get-$($catalogObject.DriverType)InstalledDrivers -Name `"$($catalogObject.Id)`"")
                    #     $catalogObject.Installed = $catalogObject.Id -in $_installedDrivers.Name
                    #     continue
                    # }
                    {$_ -in @("CLI","Installer")} {
                        $catalogObject.Installed = Invoke-Command $global:Catalog.$($catalogObject.Type).$($catalogObject.Id).Installation.IsInstalled.Command
                        continue
                    }
                    "default" {
                        $_.Refresh()
                        continue
                    }
                }

            }
        }

        if ($Installed) { $catalogObjects = $catalogObjects | Where-Object {$_.IsInstalled()} }
        if ($NotInstalled) { $catalogObjects = $catalogObjects | Where-Object {!$_.IsInstalled()} }

        return $catalogObjects

    }

    function global:Format-Catalog {

        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline)][object]$InputObject,
            [Parameter(Mandatory=$false)][string]$View
        )

        begin {
            $OutputObject = @()
        }
        process {
            $OutputObject += $InputObject
        }
        end {
            return $OutputObject | Sort-Object -Property SortProperty | Select-Object -Property $($View ? $CatalogView.CatalogObject.$($View) : $CatalogView.CatalogObject.Default)
        }

    }

    function global:Show-Catalog {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [Parameter(Mandatory=$false)][string]$View = "Min",
            [switch]$Installed,
            [switch]$NotInstalled
        )

        Get-Catalog -ComputerName $ComputerName -Installed:$Installed.IsPresent -NotInstalled:$NotInstalled.IsPresent | 
            Format-Catalog -View Min | 
                Format-Table

    }

    function global:Update-Catalog {

        [CmdletBinding()]
        param ()

        foreach ($_type in $global:Catalog.Keys) {
            foreach ($_id in $global:Catalog.$_type.Keys) {
                $global:Catalog.$_type.$_id.Refresh()
            }
        }

    }

    function global:Search-Catalog {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][ValidatePattern("^(\w*?)\.{1}(\w*?)$")][string]$Uid,
            [Parameter(Mandatory=$false)][string]$Type = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[0]}),
            [Parameter(Mandatory=$false,Position=0)][string]$Id = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[1]}),
            [switch]$AllowDuplicates

        )

        $catalogObject = @()

        # "None" is a reserved word for an empty $global:Environ definition
        if (![string]::IsNullOrEmpty($Id) -and $Id -eq "None") { return }

        if ([string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Id)) {
            foreach ($pkey in $global:Catalog.Keys) {
                if ($global:Catalog.$pkey.$Id) {
                    $catalogObject += [PSCustomObject]@{
                        Type = $pkey
                        Id = $global:Catalog.$pkey.$Id.Id
                        Object = $global:Catalog.$pkey.$Id
                    } 
                }
            }
        }

        if (![string]::IsNullOrEmpty($Type) -and ![string]::IsNullOrEmpty($Id)) {         
            
            # ensure same case as catalog keys
            $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}

            $catalogObject += [PSCustomObject]@{
                Type = $Type
                Id = $global:Catalog.$Type.$Id.Id
                Object = $global:Catalog.$Type.$Id
            }

        }       

        if ($catalogObject.Count -eq 0) {
            if ($PSBoundParameters.ErrorAction -and $PSBoundParameters.ErrorAction -ne "SilentlyContinue") {
                Write-Host+ -NoTimestamp "A $($Type ? "$Type " : $null ) object with the id `'$($Id)`' was not found in the catalog." -ForegroundColor Red
            }
            return
        }
        if (!$AllowDuplicates -and $catalogObject.Count -gt 1) {
            Write-Host+ -NoTimestamp "Multiple objects with the id `'$($catalogObject[0].Id)`' were found in the catalog." -ForegroundColor Red
            Write-Host+ -NoTimestamp "Use the -Type parameter to specify the object type or the -Duplicates switch to return all the objects with the id `'$($Id)`'." -ForegroundColor Red
            return
        }
        
        return $catalogObject

    }

    function global:Get-CatalogDependents {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][ValidatePattern("^(\w*?)\.{1}(\w*?)$")][string]$Uid,
            [Parameter(Mandatory=$false)][string]$Type = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[0]}),
            [Parameter(Mandatory=$false,Position=0)][string]$Id = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[1]}),
            [Parameter(Mandatory=$false)][string[]]$History = @(),      
            [switch]$DoNotRecurse,
            [Parameter(Mandatory=$false)][int]$RecurseLevel = 0,
            [switch]$AllowDuplicates,
            [switch]$Installed,
            [switch]$NotInstalled
        )

        # "None" is a reserved word for an empty $global:Environ definition
        if (![string]::IsNullOrEmpty($Id) -and $Id -eq "None") { return }

        if ([string]::IsNullOrEmpty($Type)) { 
            $searchResults = Search-Catalog -Id $Id
            $catalogObject = $searchResults.Object
            $Type = $searchResults.Type
        }

        # ensure same case as catalog keys
        $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}

        $catalogObject = $global:Catalog.$Type.$Id
        if (!$catalogObject) {
            Write-Host+ -NoTimestamp -NoTrace "A $($Type) object with the id `'$($Id)`' was not found in the catalog." -ForegroundColor Red
            return
        }

        $validCatalogObjectsToRecurse = @("Overwatch","Cloud","OS","Platform","Product","Provider") -join ","
        if ($Type -in $validCatalogObjectsToRecurse) { 
            $regexMatches = [regex]::Matches($validCatalogObjectsToRecurse,"(\w*,$Type),?.*$")
            $validCatalogObjectsToRecurse = $RecurseLevel -eq 0 ? ($regexMatches.Groups[1].Value) : ($regexMatches.Groups[1].Value -replace "$Type,?","")
            $validCatalogObjectsToRecurse = ![string]::IsNullOrEmpty($validCatalogObjectsToRecurse) ? $validCatalogObjectsToRecurse -split "," : $null
        }
        else {
            $validCatalogObjectsToRecurse = @("Product","Provider") 
        }

        $RecurseLevel--

        $dependents = @()
        $dependency = "$($Type).$($global:Catalog.$Type.$Id.Id)"     

        foreach ($pkey in $validCatalogObjectsToRecurse) {
            foreach ($skey in $global:Catalog.$pkey.Keys) {
                if ($Installed -and !$global:Catalog.$pkey.$skey.IsInstalled()) { continue }
                if ($NotInstalled -and $global:Catalog.$pkey.$skey.IsInstalled()) { continue }
                if ([array]$global:Catalog.$pkey.$skey.Installation.Prerequisites.$Type -contains $Id) { 

                    if ("$pkey.$skey" -notin $History) {

                        $History += "$pkey.$skey"

                        $_dependents = @()
                        $_dependents += [PSCustomObject]@{ Uid = "$pkey.$skey"; Level = $RecurseLevel; Type = $pkey; Id = $skey; Object = $global:Catalog.$pkey.$skey; Dependency = $dependency }

                        if (!$DoNotRecurse) {
                            foreach ($dependent in $_dependents) {
                                $params = @{
                                    Type = $dependent.Type
                                    Id = $dependent.Id
                                    DoNotRecurse = $DoNotRecurse.IsPresent
                                    RecurseLevel = $RecurseLevel
                                    AllowDuplicates = $AllowDuplicates.IsPresent
                                    History = $History
                                }
                                $_dependents += Get-CatalogDependents @params
                            }
                        }
        
                        if ($AllowDuplicates) {
                            $dependents += $_dependents
                        }
                        else {
                            foreach ($_dependent in $_dependents) {
                                if ($_dependent.Uid -notin $dependents.Uid) {
                                    $dependents += $_dependent
                                }
                            }
                        }

                    }

                }
            }
        }

        return $dependents

    }

    function global:Get-CatalogDependencies {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][ValidatePattern("^(\w*?)\.{1}(\w*?)$")][string]$Uid,
            [Parameter(Mandatory=$false)][string]$Type = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[0]}),
            [Parameter(Mandatory=$false,Position=0)][string]$Id = $(if (![string]::IsNullOrEmpty($Uid)) {($Uid -split "\.")[1]}),
            [Parameter(Mandatory=$false)][string[]]$IncludeDependencyType,
            [Parameter(Mandatory=$false)][string[]]$ExcludeDependencyType,
            [Parameter(Mandatory=$false)][string[]]$History = @(),
            [switch]$DoNotRecurse,
            [Parameter(Mandatory=$false)][int]$RecurseLevel = 0,
            [switch]$AllowDuplicates,
            [switch]$CatalogObjectsOnly,
            [switch]$Installed,
            [switch]$NotInstalled,
            [Parameter(Mandatory=$false)][string[]]$Platform
        )

        # "None" is a reserved word for an empty $global:Environ definition
        if (![string]::IsNullOrEmpty($Id) -and $Id -eq "None") { return }        

        if ([string]::IsNullOrEmpty($Type)) { 
            $searchResults = Search-Catalog -Id $Id
            $catalogObject = $searchResults.Object
            $Type = $searchResults.Type
        }

        # ensure same case as catalog keys
        $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}

        $catalogObject = $global:Catalog.$Type.$Id
        if (!$catalogObject) {
            Write-Host+ -NoTimestamp -NoTrace "A $($Type) object with the id `'$($Id)`' was not found in the catalog." -ForegroundColor Red
            return
        }

        if ($RecurseLevel -eq 0) { $History += "$Type.$Id" }

        $RecurseLevel++

        $dependencies = @()
        $dependent = "$($Type).$($global:Catalog.$Type.$Id.Id)" 

        foreach ($prerequisite in $global:Catalog.$Type.$Id.Installation.Prerequisites) {
            $pkey = $prerequisite.Type
            foreach ($skey in $global:Catalog.$Type.$Id.Installation.Prerequisites.$pkey) {
                if ("$pkey.$skey" -notin $History) {

                    if (![string]::IsNullOrEmpty($IncludeDependencyType) -and $pkey -notin $IncludeDependencyType) { continue }
                    if (![string]::IsNullOrEmpty($ExcludeDependencyType) -and $pkey -in $ExcludeDependencyType) { continue }
                    if (![string]::IsNullOrEmpty($Platform)) {
                        $_platform = $global:Catalog.$pkey.$skey.Installation.Prerequisites.Platform ?? "Any"
                        if ($_platform -ne "Any" -and $Platform -notin $_platform) { 
                            continue 
                        }
                    }

                    $History += "$pkey.$skey"

                    $_dependencies = @()
                    switch ($pkey) {
                        "PowerShell" {
                            foreach ($tkey in $skey.Keys) {
                                foreach ($_psObject in $skey.$tkey) {
                                    $_dependencies += [PSCustomObject]@{ 
                                        Uid = "$pkey.$tkey.$($_psObject.Name)"
                                        Level = $RecurseLevel
                                        Type = $pkey
                                        Id = $tkey
                                        Object = [PSCustomObject]$_psObject
                                        Dependent = $dependent
                                        DependentObject = $catalogObject
                                    }
                                }
                            }
                        }
                        default { 
                            if ($Installed -and !$global:Catalog.$pkey.$skey.IsInstalled()) { continue }
                            if ($NotInstalled -and $global:Catalog.$pkey.$skey.IsInstalled()) { continue }
                            $_dependencies += [PSCustomObject]@{ 
                                Uid = "$pkey.$skey"
                                Level = $RecurseLevel
                                Type = $pkey
                                Id = $skey
                                Object = $global:Catalog.$pkey.$skey
                                Dependent = $dependent
                                DependentObject = $catalogObject
                            }
                            if (!$DoNotRecurse) {
                                foreach ($dependency in $_dependencies) {
                                    $params = @{
                                        Type = $dependency.Type
                                        Id = $dependency.Id
                                        DoNotRecurse = $DoNotRecurse.IsPresent
                                        RecurseLevel = $RecurseLevel
                                        AllowDuplicates = $AllowDuplicates.IsPresent
                                        CatalogObjectsOnly = $CatalogObjectsOnly.IsPresent
                                        History = $History
                                    }
                                    if (![string]::IsNullOrEmpty($IncludeDependencyType)) { $params += @{ IncludeDependencyType = $IncludeDependencyType }}
                                    if (![string]::IsNullOrEmpty($ExcludeDependencyType)) { $params += @{ ExcludeDependencyType = $ExcludeDependencyType }}
                                    $_dependencies += Get-CatalogDependencies @params
                                }
                            }
                        }
                    }

                    if ($AllowDuplicates) {
                        $dependencies += $_dependencies
                    }
                    else {
                        foreach ($_dependency in $_dependencies) {
                            if ($_dependency.Uid -notin $dependencies.Uid) {
                                $dependencies += $_dependency
                            }
                        }                    
                    }

                }
            }
        }
        
        if ($CatalogObjectsOnly) {
            $dependencies = $dependencies | Where-Object {$_.Type -in $global:Catalog.Keys}
        }

        If (![string]::IsNullOrEmpty($Platform)) {
            $dependencies = $dependencies | Where-Object {$null -eq $_.Object.Installation.Prerequisites.Platform -or $_.Object.Installation.Prerequisites.Platform -eq "$Platform"}
        }

        return $dependencies

    }

#endregion CATALOG
#region PLATFORM

    #region STATUS

        function global:Get-PlatformStatus {
                
            [CmdletBinding()]
            param (
                [switch]$ResetCache,
                [switch]$CacheOnly,
                [switch]$Quiet
            )

            # The $ResetCache switch is only for the platform-specific Get-PlatformStatusRollup
            # function and is *** NOT *** to be used for the platformstatus cache
            if ((Get-Cache platformstatus).Exists) {
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
            if ($Quiet) { $params = @{ Quiet = $Quiet } }
            $platformStatus.IsOK, $platformStatus.RollupStatus, $platformStatus.Issues, $platformStatus.StatusObject = Get-PlatformStatusRollup @params

            if ($platformStatus.RollupStatus -eq "StatusUnavailable") {
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
                    if ([datetime]::MinValue -ne $platformStatus.EventCreatedAt) {
                        $productShutdownTimeout = $(Get-Product -Id $platformStatus.EventCreatedBy).ShutdownMax
                        $shutdownTimeout = $productShutdownTimeout.TotalMinutes -gt 0 ? $productShutdownTimeout : $PlatformShutdownMax
                        $stoppedDuration = New-TimeSpan -Start $platformStatus.EventCreatedAt
                        $IsStoppedTimeout = $stoppedDuration.TotalMinutes -gt $shutdownTimeout.TotalMinutes

                        $isOK = !$IsStoppedTimeout
                        $platformStatus.IsStoppedTimeout = $IsStoppedTimeout

                        if ($IsStoppedTimeout) {
                            $platformStatus.Intervention = $true
                            $platformStatus.InterventionReason = "Platform STOP duration $([math]::Round($stoppedDuration.TotalMinutes,0)) minutes."
                        }
                    }
                }
            }         

            $platformStatus.IsOk = $isOK

            # this overrides $platformStatus.IsStopped
            # TODO: as above, manage events if $platformStatus doesn't match platform state
            $platformStatus.IsStopped = $platformStatus.RollupStatus -in $global:ServiceDownState
            
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

        function global:Get-PlatformService {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true)][string]$Name,
                [Parameter(Mandatory=$false)][string]$View = "$CimView.Default",
                [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
            )

            return Get-PlatformServices -View $View -ComputerName $ComputerName | Where-Object { $_.Name -eq $Name }
        }

        function global:Wait-PlatformService {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string[]]$ComputerName,
                [Parameter(Mandatory=$true)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Status = "Running",
                [Parameter(Mandatory=$false)][int]$WaitTimeInSeconds = 60,
                [Parameter(Mandatory=$false)][int]$TimeOutInSeconds = 0
            )

            $platformTopology = Get-PlatformTopology -Online
            if ([string]::IsNullOrEmpty($ComputerName)) {
                $ComputerName = $platformTopology.nodes.Keys
            }
            
            $totalWaitTimeInSeconds = 0
            $service = Get-PlatformServices -ComputerName $ComputerName | Where-Object {$_.Name -eq $Name}
            if (!$service) {
                throw "`'$Name`' is not a valid $($global:Platform.Name) platform service name."
            }

            $currentStatus = $service.Status | Sort-Object -Unique
            while ($currentStatus -ne $Status) {
                Start-Sleep -Seconds $WaitTimeInSeconds
                $totalWaitTimeInSeconds += $WaitTimeInSeconds
                if ($TimeOutInSeconds -gt 0 -and $totalWaitTimeInSeconds -ge $TimeOutInSeconds) {
                    # throw "ERROR: Timeout ($totalWaitTimeInSeconds seconds) waiting for platform service `'$Name`' to transition from status `'$currentStatus`' to `'$Status`'"
                    return $false
                }
                $service = Get-PlatformServices -ComputerName $ComputerName | Where-Object {$_.Name -eq $Name}
                $currentStatus = $service.Status | Sort-Object -Unique
            }
        
            return $true
        
        }

        function global:Get-Service+ {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
                [Parameter(Mandatory=$true,Position=0)][string]$Name
            )

            if ($ComputerName -eq $env:COMPUTERNAME) {
                # get the local service
                $service = Get-Service $Name
                # get the process associated with the service
                # this is so we can get properties like CreationDate and calculate service uptime/runtime
                $serviceProcess = Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE '$Name'" | Foreach-Object {
                    Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($_.ProcessId)"
                }
            }
            else {
                $psSession = Use-PSSession+ -ComputerName $ComputerName -ErrorAction SilentlyContinue
                if (!$psSession) { 
                    $message = "Unable to get/create a PowerShell session."
                    Write-Log -Action "Use-PSSession+" -Target "$($Computername)\$($Name)" -Status "Fail" -EntryType Error -Message $message 
                    Write-Host+ -NoTrace $message -ForegroundColor DarkRed
                    return
                }
                # get the remote service
                $service = Invoke-Command -Session $psSession {
                    Get-Service -Name $using:Name -ErrorAction SilentlyContinue
                }
                # get the process associated with the service
                # this is so we can get properties like CreationDate and calculate service uptime/runtime
                $serviceProcess = Invoke-Command -Session $psSession {
                    Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE '$using:Name'" -ErrorAction SilentlyContinue | Foreach-Object {
                        Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($_.ProcessId)" -ErrorAction SilentlyContinue
                    }
                }
            }

            # add CreationDate to the service object
            $service | Add-Member -NotePropertyName CreationDate -NotePropertyValue $serviceProcess.CreationDate
        
            return $service
        
        }

        function global:Start-Service+ {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Status = "Running"
            )

            $service = $null
            if ($ComputerName -eq $env:COMPUTERNAME) {
                $service = Get-Service $Name
            }
            else {
                $service = Get-Service+ $Name -ComputerName $ComputerName
            }
            
            if (!$service -or ($service -and $service.Status -ne $Status)) {
                $message =  "The $Name service is $($service.Status ?? "Unknown")." 
                Write-Log -Action "Get-Service" -Target "$($Computername)\$($Name)" -Status $service.Status -EntryType Error -Message $message 
                Write-Host+ -NoTrace $message -ForegroundColor DarkRed

                if ($ComputerName -eq $env:COMPUTERNAME) {
                    $service = Start-Service -Name $Name -ErrorAction SilentlyContinue
                }
                else {
                    $service = Invoke-Command -Session $psSession { Start-Service -Name $using:Name -ErrorAction SilentlyContinue}
                }

                if (!(Wait-Service $Name -Status $Status -WaitTimeInSeconds 5 -TimeOutInSeconds 15)) {
                    $message = "Unable to start the $Name service."
                    Write-Log -Action "Start-Service" -Target "$($Computername)\$($Name)" -Status $service.Status -EntryType Error -Message $message 
                    Write-Host+ -NoTrace $message -ForegroundColor DarkRed
                }
                else {
                    $service = Get-Service $Name
                    $message =  "The $Name service is $($service.Status ?? "Unknown")." 
                    Write-Log -Action "Get-Service" -Target "$($Computername)\$($Name)" -Status $service.Status -EntryType Information -Message $message -Force
                    Write-Host+ -NoTrace $message -ForegroundColor DarkRed
                }
            }
        
        }

        function global:Wait-Service {

            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
                [Parameter(Mandatory=$true,Position=0)][string]$Name,
                [Parameter(Mandatory=$false)][string]$Status = "Running",
                [Parameter(Mandatory=$false)][int]$WaitTimeInSeconds = 60,
                [Parameter(Mandatory=$false)][int]$TimeOutInSeconds = 0
            )
            
            $totalWaitTimeInSeconds = 0
            
            $service = Get-Service+ $Name -ComputerName $ComputerName -ErrorAction SilentlyContinue
            if (!$service) { return $false }

            while ($service.Status -ne $Status) {
                Start-Sleep -Seconds $WaitTimeInSeconds
                $totalWaitTimeInSeconds += $WaitTimeInSeconds
                if ($TimeOutInSeconds -gt 0 -and $totalWaitTimeInSeconds -ge $TimeOutInSeconds) {
                    return $false
                }
                if ($ComputerName -eq $env:COMPUTERNAME) {
                    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
                }
                else {
                    $service = Invoke-Command -Session $psSession { Get-Service -Name $using:Name -ErrorAction SilentlyContinue}
                }
            }
        
            return $true
        
        }

    #endregion SERVICES

#endregion PLATFORM
#region TESTS

    function global:Get-IpAddress {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$ComputerName,
            [Parameter(Mandatory=$false,Position=1)][ValidateSet("IP4","IP6")][string]$Type = "IP4",
            [Parameter(Mandatory=$false,Position=2)][string]$Mask = "255.255.255.255"
        )

        $ipAddress = (Resolve-DnsName $ComputerName | Where-Object {$null -ne $_."$($Type)Address"}).IPAddress
        $ipAddress = [ipaddress] (([ipaddress]$ipAddress).Address -band ([ipaddress]$Mask).Address)

        return $ipAddress.IPAddressToString

    }

    function global:Test-NetConnection+ {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = (pt nodes -online -k),
            [Parameter(Mandatory=$false)][ValidateSet("HTTP", "RDP", "SMB", "WINRM")][string]$CommonTCPPort = "WINRM",
            [switch]$NoHeader,
            [switch]$Quiet
        )

        $message = "  Network Connections"
        $leader = Format-Leader -Length 46 -Adjust $message.Length
        Write-Host+ -Iff $(!$Quiet -and !$NoHeader) -NoTrace $message,$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

        $fail = $false
        $testResults = [PSCustomObject]@()
        foreach ($node in $ComputerName) {

            $remoteAddress = ((Test-NetConnection -ComputerName $node -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).ResolvedAddresses | 
                Where-Object {$_.AddressFamily -eq "InterNetwork"}).IPAddressToString 

            $message = "    Ping:$node [$remoteAddress]"
            $leader = Format-Leader -Length 39 -Adjust ($message.Length-1)
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoNewLine $message.Split(":")[0], $message.Split(":")[1], $leader, "PENDING" -ForegroundColor Gray,DarkBlue,DarkGray,DarkGray

            $_fail = $false
            #region PING

                $pingResult = Test-NetConnection -ComputerName $node -InformationLevel ($Quiet ? "Quiet" : "Detailed") -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

                if (!$pingResult.PingSucceeded) {
                    Write-Log -Action "Ping" -Target "$($pingResult.ComputerName) [$($pingResult.RemoteAddress)]" -Status "Fail" -EntryType "Information"
                    $fail = $true
                }

                $testResults += [PSCustomObject]@{
                    Test = "Ping"
                    ComputerName = $node
                    RemoteAddress = $pingResult.RemoteAddress
                    Result = $pingResult.PingSucceeded ? "Pass" : "Fail"
                    Pass = $pingResult.PingSucceeded
                    Fail = !$pingResult.PingSucceeded
                    Timestamp = Get-Date -AsUTC
                }

            #endregion PING
            #region TCPTEST

                $tcpTestResult = Test-NetConnection -ComputerName $node -CommonTCPPort $CommonTCPPort -InformationLevel ($Quiet ? "Quiet" : "Detailed") -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

                if (!$tcpTestResult.TcpTestSucceeded) { 
                    Write-Log -Action "TcpTest" -Target "$($tcpTestResult.ComputerName) [$($tcpTestResult.RemoteAddress):$($tcpTestResult.RemotePort)]" -Status "Fail" -EntryType "Information"
                    $_fail = $fail = $true
                }

                $testResults += [PSCustomObject]@{
                    Test = "TcpTest"
                    ComputerName = $node
                    Protocol = $CommonTCPPort
                    RemoteAddress = $tcpTestResult.RemoteAddress
                    RemotePort = $tcpTestResult.RemotePort
                    Result = $tcpTestResult.TcpTestSucceeded ? "Pass" : "Fail"
                    Pass = $tcpTestResult.TcpTestSucceeded
                    Fail = !$tcpTestResult.TcpTestSucceeded
                    Timestamp = Get-Date -AsUTC
                }

            #endregion TCPTEST

            $message = "$($emptyString.PadLeft(8,"`b")) $($_fail ? "FAIL" : "PASS")$($emptyString.PadLeft(8," "))"
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoIndent $message -ForegroundColor ($_fail ? "DarkRed" : "DarkGreen")

        }

        $message = "  Network Connections"
        $leader = Format-Leader -Length 46 -Adjust $message.Length
        Write-Host+ -Iff $(!$Quiet -and !$NoHeader) -NoTrace $message,$leader,($fail ? "FAIL" : "PASS") -ForegroundColor Gray,DarkGray,($fail ? "DarkRed" : "DarkGreen")

        return $testResults
        
    }

    function global:Test-PSRemoting {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = (pt nodes -online -k),
            [switch]$NoHeader,
            [switch]$Quiet
        )

        $leader = Format-Leader -Length 46 -Adjust ((("  PowerShell Remoting").Length))
        Write-Host+ -Iff $(!$Quiet -and !$NoHeader) -NoTrace "  PowerShell Remoting",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

        $fail = $false
        $testResults = [PSCustomObject]@()
        foreach ($node in $ComputerName) {

            # Write-Host+ -Iff $(!$Quiet) -NoNewline -NoTimestamp -NoTrace "." -ForegroundColor DarkGray

            $message = "    Remote to:$($node)"
            $leader = Format-Leader -Length 39 -Adjust ($message.Length-1)
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoNewLine $message.Split(":")[0], $message.Split(":")[1], $leader, "PENDING" -ForegroundColor Gray,DarkBlue,DarkGray,DarkGray

            $_fail = $false

            try {
                $psSession = New-PSSession+ -ComputerName $node
                Remove-PSSession -Session $psSession
                Write-Host+ -Iff $(!$Quiet) -NoTimestamp -NoTrace -NoIndent "$($emptyString.PadLeft(8,"`b")) PASS   " -ForegroundColor DarkGreen 
            }
            catch {
                Write-Host+ -Iff $(!$Quiet) -NoTimestamp -NoTrace -NoIndent "$($emptyString.PadLeft(8,"`b")) FAIL   " -ForegroundColor DarkRed
                Write-Log -Action "Test" -Target "PowerShell-Remoting" -Status "Fail" -EntryType "Error" -Message "PowerShell-Remoting to $($node) failed"
                $_fail = $fail = $true
            }

            $testResults += [PSCustomObject]@{
                Test = "PSRemoting"
                ComputerName = $node
                Result = $_fail ? "Fail" : "Pass"
                Pass = !$_fail
                Fail = $_fail
                Timestamp = Get-Date -AsUTC
            }

        }

        $message = "  PowerShell Remoting"
        $leader = Format-Leader -Length 46 -Adjust $message.Length
        Write-Host+ -Iff $(!$Quiet -and !$NoHeader) -NoTrace $message,$leader,($fail ? "FAIL" : "PASS") -ForegroundColor Gray,DarkGray,($fail ? "DarkRed" : "DarkGreen")        

        return $testResults

    }

    function global:Test-ServerStatus {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string[]]$ComputerName,
            [switch]$Quiet
        )

        Write-Host+ -ResetIndentGlobal

        $leader = Format-Leader -Length 46 -Adjust ((("  Server Status").Length))
        Write-Host+ -Iff $(!$Quiet) -NoTrace "  Server Status",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray
    
        $results = [PSCustomObject]@()
    
        Write-Host+ -SetIndentGlobal 2

        $results += Test-NetConnection+ -ComputerName $ComputerName -Quiet:$Quiet.IsPresent
        $results += Test-PSRemoting -ComputerName $ComputerName -Quiet:$Quiet.IsPresent
        
        Write-Host+ -ResetIndentGlobal
    
        $groupedResults = $results | Group-Object -Property ComputerName
        foreach ($node in $groupedResults.Name) {        
    
            $nodeResults = $groupedResults | Where-Object {$_.Name -eq $node}
            $pass = ($nodeResults.Group.Pass | Select-Object -Unique) -eq $true
    
            $results += [PSCustomObject]@{
                Test = "Summary"
                ComputerName = $node
                Result = $pass ? "Pass" : "Fail"
                Pass = $pass
                Fail = !$pass
                Timestamp = Get-Date -AsUTC
            }
    
        }
        $_results = $results | Where-Object {$_.Test -eq "Summary" -and $_.Pass} | Select-Object -ExcludeProperty Test
        $results = [PSCustomObject]@()
        $results += $_results

        if ((Get-Cache serverstatus).Exists) {
            $cachedResults = Read-Cache serverstatus | Where-Object {$_.ComputerName -notin $results.ComputerName}
            if ($cachedResults) { $results += $cachedResults }
        }

        $results = $results | Where-Object {$_.ComputerName -in $ComputerName}
        $results | Write-Cache serverstatus

        $alertResults = @()
        foreach ($result in $results) {
            $duration = New-TimeSpan -Start $result.Timestamp
            if ($duration -gt $global:PlatformShutdownMax) {
                $result | Add-Member -Force -NotePropertyName "AlertTimestamp" -NotePropertyValue (Get-Date -AsUTC)
                $result | Add-Member -Force -NotePropertyName "AlertReason" -NotePropertyValue "$($result.ComputerName.ToUpper()) has been offline for $($duration.ToString("h'h 'm'm 'ss's'"))" 
                $alertResults += $result
            }
        }

        $leader = Format-Leader -Length 46 -Adjust ((("    Last Seen").Length))
        Write-Host+ -Iff $(!$Quiet) -NoTrace "    Last Seen",$leader,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray

        foreach ($result in (Read-Cache serverstatus | Where-Object {$_.ComputerName -in $ComputerName})) {
            $duration = New-TimeSpan -Start $result.Timestamp
            $durationText = $duration.TotalMinutes -lt 1 ? "NOW" : "-$($duration.ToString("m'm 'ss's'"))"
            $message = "      $($result.ComputerName)"
            $leader = Format-Leader -Length 39 -Adjust ($message.Length-1)
            Write-Host+ -Iff $(!$Quiet) -NoTrace $message, $leader, $durationText -ForegroundColor DarkBlue, DarkGray, ($duration -gt $global:PlatformShutdownMax ? "Red" : "DarkGray")
        }

        $message = "    Last Seen"
        $leader = Format-Leader -Length 46 -Adjust $message.Length
        Write-Host+ -Iff $(!$Quiet) -NoTrace $message,$leader,($fail ? "FAIL" : "PASS") -ForegroundColor Gray,DarkGray,($fail ? "DarkRed" : "DarkGreen")                

        foreach ($alertResult in $alertResults) {
            Write-Host+ -NoTrace $alertResult.AlertReason -ForegroundColor DarkYellow
            Send-ServerInterventionMessage -ComputerName $alertResult.ComputerName -Message $alertResult.AlertReason -MessageType $global:PlatformMessageType.Intervention | Out-Null
        }

        $message = "  Server Status"
        $leader = Format-Leader -Length 46 -Adjust $message.Length
        Write-Host+ -Iff $(!$Quiet) -NoTrace $message,$leader,($fail ? "FAIL" : "PASS") -ForegroundColor Gray,DarkGray,($fail ? "DarkRed" : "DarkGreen")           
    
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
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $messagePart[0],"[",$messagePart[1],"] ",(Format-Leader -Length 47 -Adjust ((($messagePart -join " ").Length+2)))," PENDING" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,DarkGray
            # Write-Host+ -Iff (!$PassFailOnly)

            $now = Get-Date -AsUTC
            $30days = New-TimeSpan -days 30
            # $emptyString = ""
            $fail = $false
            $warn = $false

            $protocolNames = [System.Security.Authentication.SslProtocols] |
                Get-Member -Static -MemberType Property |
                Where-Object -Filter { $_.Name -notin @("Default","None") } |
                Foreach-Object { $_.Name }
    
            # $supportedProtocols = $global:TlsBestPractices.protocols.Keys | Sort-Object

        }

        process {

            $protocolStatus = [Ordered]@{}
            $protocolStatus.Add("ComputerName", $ComputerName)
            $protocolStatus.Add("Port", $Port)
            $protocolStatus.Add("KeyLength", $null)
            # $protocolStatus.Add("SignatureAlgorithm", $null)
            $protocolStatus.Add("SupportedProtocols",@())

            $protocolNames | ForEach-Object {
                $protocolName = $_
                $socket = New-Object System.Net.Sockets.socket( `
                    [System.Net.Sockets.SocketType]::Stream,
                    [System.Net.Sockets.ProtocolType]::Tcp)
                $socket.Connect($ComputerName, $Port)
                try {
                    $netStream = New-Object System.Net.Sockets.NetworkStream($socket, $true)
                    $sslStream = New-Object System.Net.Security.sslStream($netStream, $true)
                    $sslStream.AuthenticateAsClient($ComputerName,  $null, $protocolName, $false )
                    $remoteCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]$sslStream.remoteCertificate
                    $protocolStatus["KeyLength"] = $remoteCertificate.PublicKey.Key.KeySize
                    # $protocolStatus["SignatureAlgorithm"] = $remoteCertificate.SignatureAlgorithm.FriendlyName
                    $protocolStatus["Certificate"] = $remoteCertificate
                    $protocolStatus.Add($protocolName, $true)
                } catch  {
                    $protocolStatus.Add($protocolName, $false)
                } finally {
                    $sslStream.Close()
                }
            }

        }

        end {

            $thisWarn = $false
            $thisFail = $false

            $expiresInDays = $protocolStatus.Certificate.NotAfter - $now
            
            $thisWarn = $expiresInDays -le $30days
            $warn = $warn -or $thiswarn
            $thisFail = $expiresInDays -le [timespan]::Zero
            $fail = $fail -or $thisFail

            $expiryColor = $thisFail ? "DarkRed" : ($thisWarn ? "DarkYellow" : "DarkGray")
            
            $message = "<    Certificate <.>41> PENDING"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

            $message = "      Subject:      $($protocolStatus.Certificate.Subject)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Issuer:       $($protocolStatus.Certificate.Issuer.split(",")[0])"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Serial#:      $($protocolStatus.Certificate.SerialNumber)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Thumbprint:   $($protocolStatus.Certificate.Thumbprint)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Expiry:      | $($protocolStatus.Certificate.NotAfter)"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor DarkGray,$expiryColor
            $message = "      Status:      | $($thisFail ? "Expired" : ($thisWarn ? "Expires in $([math]::round($expiresInDays.TotalDays,1)) days" : "Valid"))"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor DarkGray,$expiryColor

            # change expireColor success from darkgray to darkgreen for PASS indicators
            $expiryColor = $thisFail ? "DarkRed" : ($thisWarn ? "DarkYellow" : "DarkGreen")

            $message = "<    Certificate <.>41> $($thisFail ? "FAIL" : ($thisWarn ? "WARN" : "PASS"))"
            Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,$expiryColor

            if ($thisWarn -or $thisFail) {
                Send-SSLCertificateExpiryMessage -Certificate $protocolStatus.Certificate | Out-Null
            }

            $thisWarn = $false
            $thisFail = $false

            foreach ($signatureAlgorithm in $global:TlsBestPractices.signatureAlgorithms) {
                $thisFail = $protocolStatus.SignatureAlgorithm -ne $signatureAlgorithm
                $fail = $fail -or $thisFail
                $message = "<    Signature Algorithm <.>41> $($thisFail ? "FAIL" : "PASS")"
                Write-Host+ -Iff (!$PassFailOnly) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,($thisFail ? "DarkRed" : "DarkGreen")
            }

            $thisWarn = $false
            $thisFail = $false

            # Write-Host+ -Iff (!$PassFailOnly)

            foreach ($protocol in $protocolNames) {
                $thisFail = $global:TlsBestPractices.protocols.$protocol.state -ne "Optional" ? $protocolStatus.$protocol -ne ($global:TlsBestPractices.protocols.$protocol.state -eq "Enabled") : $false
                $fail = $fail -or $thisFail
                $state = $global:TlsBestPractices.protocols.$protocol.state -ne "Optional" ? $($global:TlsBestPractices.protocols.$protocol.state -eq "Enabled" ? "Enabled" : "Disabled") : $($protocolStatus.$protocol ? "Enabled" : "Disabled")
                $result = $global:TlsBestPractices.protocols.$protocol.state -ne "Optional" ? $($thisFail ? "FAIL": "PASS") : "PASS"
                $message = "<    $($global:TlsBestPractices.protocols.$protocol.displayName) <.>18> "
                $bestPracticeColor = switch($global:TlsBestPractices.protocols.$protocol.state) {
                    "Enabled" {"DarkGreen"}
                    "Disabled" {"DarkRed"}
                    "Optional" {"DarkYellow"}
                }
                $stateColor = $state -eq "Enabled" ? "DarkGreen" : "DarkRed"
                $resultColor = $thisFail ? "DarkRed" : "DarkGreen"
                Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray
                Write-Host+ -Iff (!$PassFailOnly) -NoTrace -NoTimestamp -NoSeparator "BP:",($global:TlsBestPractices.protocols.$protocol.state.ToUpper() + " ").Substring(0,8)," ","S:",($state.ToUpper() + " ").Substring(0,8)," ",$result -ForegroundColor DarkGray,$bestPracticeColor,DarkGray,DarkGray,$stateColor,DarkGray,$resultColor
            }

            Write-Host+ -Iff (!$PassFailOnly) -NoTrace "      * BP:Best Practice, S:Current State" -ForegroundColor DarkGray
            # Write-Host+ -Iff (!$PassFailOnly)

            $thisWarn = $false
            $thisFail = $false

            $messagePart = "  SSL Protocol ","$($ComputerName)"
            Write-Host+ -NoTrace -NoSeparator $messagePart[0],"[",$messagePart[1],"] ",(Format-Leader -Length 47 -Adjust ((($messagePart -join " ").Length+2)))," $($fail ? "FAIL" : ($warn ? "WARN" : "PASS"))" -ForegroundColor Gray,DarkGray,DarkBlue,DarkGray,DarkGray,$expiryColor
            Write-Log -Action "Test" -Target "SSL" -Status $($fail ? "FAIL" : ($warn ? "WARN" : "PASS"))
        
            # return [PSCustomObject]$protocolStatus
        }

    }

    function global:Test-RemoteOverwatchControllers {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = $global:OverwatchRemoteControllers
        )        

        foreach ($node in $ComputerName) {
            
            # is the network interface reachable
            $remoteConnectionStatus = Test-NetConnection -ComputerName $node
            if ($remoteConnectionStatus.Status -contains "Success") {

                Write-Host+ -NoTrace "$($node): Network interface is reachable" -ForegroundColor DarkGray
    
                # is the server reachable via powershell remoting?
                # this is a proxy for "is the o/s up and running?"
                try {
                    $remotePsSession = New-PsSession+ -ComputerName $node
                    Remove-PsSession -Session $remotePsSession

                    Write-Host+ -NoTrace "$($node): Connected via PowerShell remoting" -ForegroundColor DarkGray

                    # is Overwatch Monitor running?
                    try {

                        $monitorPlatformTask = Get-PlatformTask -Id Monitor -ComputerName $node
                        Write-Host+ -NoTrace "$($node): Overwatch Monitor is $($monitorPlatformTask.Status.ToUpper())" -ForegroundColor DarkGray

                        # # is the platform ok/running?
                        # # get the platformstatus cache; if stopped, determine if intervention is required
                        # $platformStatus = Read-Cache platformstatus -ComputerName $node
                        # # $remoteEnviron = Get-EnvironConfig -Key Environ -ComputerName $node
                        # if ($platformStatus.EventStatus -eq $global:PlatformEventStatus.Failed) {
                        #     Write-Host+ -NoTrace "$($node): Platform $($platformStatus.Event.ToUpper()) has $($platformStatus.EventStatus.ToUpper())" -ForegroundColor DarkRed
                        # }
                        # if ($remotePlatformStatus.IsStopped) {
                        #     if ([datetime]::MinValue -ne $platformStatus.EventCreatedAt) {
                        #         $productShutdownTimeout = $(Get-Product -Id $platformStatus.EventCreatedBy -ComputerName $node).ShutdownMax
                        #         $shutdownTimeout = $productShutdownTimeout.TotalMinutes -gt 0 ? $productShutdownTimeout : $global:PlatformShutdownMax
                        #         $stoppedDuration = New-TimeSpan -Start $platformStatus.EventCreatedAt
                        #         if ($stoppedDuration.TotalMinutes -gt $shutdownTimeout.TotalMinutes) {
                        #             Write-Host+ -NoTrace "$($node): Platform $($platformStatus.Event.ToUpper()) duration $([math]::Round($stoppedDuration.TotalMinutes,0)) minutes." -ForegroundColor DarkRed
                        #         }
                        #     }
                        # }

                    }

                    # Get-PlatformTask failed
                    catch {
                        $message = (Get-Error).Exception.Message
                        Write-Host+ -NoTrace "$($node): Unable to get Overwatch Monitor status" -ForegroundColor DarkRed
                        Write-Host+ -NoTrace $message -ForegroundColor DarkRed
                    }

                }
    
                # the server is not reachable via powershell remoting
                # this is a proxy for "is the o/s up and running?"
                catch {
                    Write-Host+ -NoTrace "$($node): Unable to connect via PowerShell remoting" -ForegroundColor DarkRed
                }

            }
    
            # the network interface is not reachable
            else {
                Write-Host+ -NoTrace "$($node): Network interface is unreachable" -ForegroundColor DarkRed
            }
    
        }

    }    

    function global:Test-Prerequisites {

        [CmdletBinding()]
        param (

            [Parameter(Mandatory=$true,ParameterSetName="Uid",Position=0)][ValidatePattern("^(\w*?)\.{1}(\w*?)$")][string]$Uid,
            [Parameter(Mandatory=$true,ParameterSetName="TypeAndId")][string]$Type,
            [Parameter(Mandatory=$true,ParameterSetName="TypeAndId")][string]$Id,
            [Parameter(Mandatory=$false)][ValidateSet("Initialization","Installation")][string]$PrerequisiteType = "Initialization",
            [Parameter(Mandatory=$false)][string]$PrerequisiteFilter,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [switch]$Quiet
        )

        function IsValidVersion {

            param (
                [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyString()][string]$Version,
                [Parameter(Mandatory=$true)][Alias("Package","Module")][object[]]$InputObject
            )

            if ([string]::IsNullOrEmpty($Version)) { return $true }
            if ($InputObject.Count -eq 1) {
                return $Version -eq $InputObject.Version
            }
            if ($InputObject.Count -gt 1) {
                return $Version -ge $InputObject.Version[-1] -and $Version -le $InputObject.Version[0]
            }

            return $false

        }

        $global:PsDefaultModuleRepositoryName = "PSGallery"
        $global:PsDefaultPackageProviderName = "NuGet"

        if (![string]::IsNullOrEmpty($Uid) -and ([string]::IsNullOrEmpty($Type) -or [string]::IsNullOrEmpty($Id))) { 
            $Type = ($Uid -split "\.")[0]
            $Id = ($Uid -split "\.")[1]
        }

        $catalogObject = Get-Catalog -Type $Type -Id $Id
        if (!$catalogObject) {
            Write-Host+ -NoTrace "'$Type.$Id' not found in catalog" -ForegroundColor Red
            return
        }
        $Type = $catalogObject.Type
        $Id = $catalogObject.Id

        Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse "<$Type $Id <.>48> PENDING" -ForegroundColor Gray,DarkGray,DarkGray

        Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse "<  Prerequisites <.>48> PENDING" -ForegroundColor Gray,DarkGray,DarkGray

        $global:Catalog.$Type.$Id.Refresh()

        $results = [ordered]@{
            Type = $Type
            Id = $Id
            Installed = $global:Catalog.$Type.$Id.Installed
            Prerequisites = @()
            Pass = $true
            Installable = $true
        }

        if (!($global:Catalog.$Type.$Id.$PrerequisiteType.Prerequisites)) { 
            return $results 
        }

        $prerequisites = $global:Catalog.$Type.$Id.$PrerequisiteType.Prerequisites | Copy-Object

        # apply prerequisite filter, if specified
        $prerequisiteTypeObjects = $null
        if (![string]::IsNullOrEmpty($PrerequisiteFilter)) {
            if ($prerequisites.$($prerequisites.Type).GetType().Name -eq "Hashtable") {
                $prerequisiteTypeObjects = $prerequisites.$($prerequisites.Type).$($prerequisites.$($prerequisites.Type).Keys)
            }
            $prerequisiteTypeObjects = Invoke-Expression "`$prerequisiteTypeObjects | Where-Object {`$_.$PrerequisiteFilter}"
            if ($prerequisites.$($prerequisites.Type).GetType().Name -eq "Hashtable") {
                Invoke-Expression "`$prerequisites.$($prerequisites.Type).$($prerequisites.$($prerequisites.Type).Keys) = `$prerequisiteTypeObjects"
            }
            elseif ($prerequisites.$($prerequisites.Type).GetType().Name -eq "Array") {
                Invoke-Expression "`$prerequisites.$($prerequisites.Type) = `$prerequisiteTypeObjects"
            }
        }
        $prerequisiteTypeObjects | Out-Null

        foreach ($_prerequisite in $prerequisites) {

            $prerequisite = [ordered]@{}
            $prerequisite += [ordered]@{
                Type = $_prerequisite.Type
                Id = $_prerequisite.$($_prerequisite.Type) # | Copy-Object
            }

            foreach ($key in ($_prerequisite.keys | Where-Object {$_ -notin @("Type",$_prerequisite.Type)} | Sort-Object)) {
                $prerequisite += [ordered]@{ $key = $_prerequisite.$key | Copy-Object }
            }
            
            $prerequisite += [ordered]@{
                Status = $null 
                Pass = $false
                Block = $false
                Tests = @()
            }

            foreach ($prerequisiteId in $prerequisite.Id) {

                $prerequisiteTest = [ordered]@{
                    Type = $prerequisite.Type
                    Id = $prerequisiteId
                    DisplayName = "$($prerequisite.Type) $prerequisiteId"
                    Status = $null
                    Pass = $false
                    Block = $false
                    # Results = $null
                }
                
                # test for prerequisite types which are drivers
                if ($prerequisite.Type -eq "Driver") {
                    $_driverParams = @{ Name = "*$($prerequisite.Driver)*"; ComputerName = $ComputerName }
                    if (![string]::IsNullOrEmpty($prerequisite.Platform)) { $_driverParams += @{ Platform = $prerequisite.Platform } }
                    $_installedDrivers = (Invoke-Expression "Get-$($prerequisite.DriverType)InstalledDrivers @_driverParams")
                    $_isInstalled = $null -ne $_installedDrivers
                    $prerequisiteTest.DisplayName = "$($prerequisite.Driver) $($prerequisite.DriverType) Driver"
                    $prerequisiteTest.Status = $_isInstalled ? "Installed" : "Not Installed"
                    $prerequisiteTest.Pass = $_isInstalled
                    $prerequisiteTest.Block = !$prerequisiteTest.Pass
                    if (!$prerequisiteTest.Pass) {
                        $prerequisiteTest += @{ Reason = "The $($prerequisite.Driver) driver is $($prerequisiteTest.Status)."}
                    }
                }

                # test for prerequisite types which are powershell modules/packages
                if ($prerequisite.Type -eq "PowerShell") {
                    $_isInstalled = $true
                    if (!($prerequisite.Id.Modules -or $prerequisite.Id.Packages)) {
                        $_isInstalled = $false
                    }                    
                    else {
                        if ($prerequisite.Id.Modules) {
                            $prerequisiteTest.DisplayName = "PowerShell Modules"
                            $prerequisiteTest.$($prerequisite.Type) += @{ Modules = @() }
                            $prerequisiteTest.Id = "Modules"
                            foreach ($module in $prerequisite.Id.Modules) {
                                
                                $moduleReason = @()
                                
                                $moduleRequiredVersion = ![string]::IsNullOrEmpty($module.RequiredVersion) ? $module.RequiredVersion : $null
                                $moduleMinimumVersion = [string]::IsNullOrEmpty($moduleRequiredVersion) -and ![string]::IsNullOrEmpty($module.MinimumVersion) ? $module.MinimumVersion : $null
                                $moduleMaximumVersion = [string]::IsNullOrEmpty($moduleRequiredVersion) -and [string]::IsNullOrEmpty($moduleMinimumVersion) -and ![string]::IsNullOrEmpty($module.MaximumVersion) ? $module.MaximumVersion : $null
                                
                                $psModuleRepositoryName = ![string]::IsNullOrEmpty($module.Repository) ? $module.Repository : $global:PsDefaultModuleRepositoryName 
                                $repositoryModule = Find-PSResource -Name $module.Name -Repository $psModuleRepositoryName -Version "[0,]" -ErrorAction SilentlyContinue  | Sort-Object -Property Version -Descending
                                
                                $installedModule = $null # establish scope
                                $requiredVersion = $minimumVersion = $maximumVersion = $null
                                if ($repositoryModule) {

                                    $requiredVersion = ![string]::IsNullOrEmpty($moduleRequiredVersion) ? $moduleRequiredVersion : $null                                    
                                    if (!(IsValidVersion -Version $moduleRequiredVersion -Module $repositoryModule)) {
                                        throw "RequiredVersion $moduleRequiredVersion for module $($module.Name) must be between $($repositoryModule.Version[-1]) and $($repositoryModule.Version[0])."
                                    }
                                    if ([string]::IsNullOrEmpty($moduleRequiredVersion)) {
                                        $minimumVersion = ![string]::IsNullOrEmpty($moduleMinimumVersion) ? $moduleMinimumVersion : $null                                    
                                        if (!(IsValidVersion -Version $moduleMinimumVersion -Module $repositoryModule)) {
                                            throw "MinimumVersion $moduleMinimumVersion for module $($module.Name) must be between $($repositoryModule.Version[-1]) and $($repositoryModule.Version[0])."
                                        }
                                        $maximumVersion = ![string]::IsNullOrEmpty($moduleMaximumVersion) ? $moduleMaximumVersion : $null                                    
                                        if (!(IsValidVersion -Version $moduleMaximumVersion -Module $repositoryModule)) {
                                            throw "MaximumVersion $moduleMaximumVersion for module $($module.Name) must be between $($repositoryModule.Version[-1]) and $($repositoryModule.Version[0])."
                                        }
                                    }

                                    $installedModule = @()
                                    $installedModule += Get-InstalledPSResource -Name $module.Name -Scope AllUsers -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending
                                    $installedModule += Get-InstalledPSResource -Name $module.Name -Scope CurrentUser -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending
                                    $installedModuleVersion = [array]$installedModule.Version # this needs to be an array for the comparisons below to work

                                    if ($installedModule) {
                                        $isModuleInstalled = $true
                                        $isRequiredVersionInstalled = (
                                            ([string]::IsNullOrEmpty($requiredVersion) -and [string]::IsNullOrEmpty($minimumVersion) -and [string]::IsNullOrEmpty($maximumVersion)) -or 
                                            ((![string]::IsNullOrEmpty($requiredVersion) -and $requiredVersion -in $installedModuleVersion) -or 
                                            (![string]::IsNullOrEmpty($minimumVersion) -and $installedModuleVersion[0] -ge $minimumVersion) -or 
                                            (![string]::IsNullOrEmpty($maximumVersion) -and $installedModuleVersion[0] -le $maximumVersion))  
                                        )
                                        $installedVersion = $installedModuleVersion[0]
                                        if (![string]::IsNullOrEmpty($requiredVersion) -and $requiredVersion -in $installedModuleVersion) {
                                            $installedVersion = $requiredVersion
                                        }
                                        $moduleReason += "Module $($module.Name) $($installedVersion)$($installedVersion ? " " : $null)is installed."
                                        if (!$isRequiredVersionInstalled) {
                                            $moduleReason += "Module $($module.Name) $($requiredVersion ?? $minimumVersion ?? $maximumVersion)$(($requiredVersion ?? $minimumVersion ?? $maximumVersion) ? " " : $null)is not installed."
                                        }
                                    }
                                    else {
                                        $isModuleInstalled = $false
                                        $isRequiredVersionInstalled = $false
                                        $moduleReason += "Module $($module.Name) $($installedVersion)$($installedVersion ? " " : $null)is not installed."
                                    }

                                    if (!$module.DoNotImport) {

                                        $importedModule = Get-Module -Name $module.Name -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending
                                        $importedModuleVersion = [array]$importedModule.Version # this needs to be an array for the comparisons below to work

                                        if ($importedModule) {

                                            $isModuleImported = $true
                                            $isRequiredVersionImported = (
                                                ([string]::IsNullOrEmpty($requiredVersion) -and [string]::IsNullOrEmpty($minimumVersion) -and [string]::IsNullOrEmpty($maximumVersion)) -or 
                                                ((![string]::IsNullOrEmpty($requiredVersion) -and $requiredVersion -in $importedModuleVersion) -or 
                                                (![string]::IsNullOrEmpty($minimumVersion) -and $importedModuleVersion[0] -ge $minimumVersion) -or 
                                                (![string]::IsNullOrEmpty($maximumVersion) -and $importedModuleVersion[0] -le $maximumVersion))  
                                            )
                                            $importedVersion = $importedModuleVersion[0]
                                            if (![string]::IsNullOrEmpty($requiredVersion) -and $requiredVersion -in $importedModuleVersion) {
                                                $importedVersion = $requiredVersion
                                            }
                                            $moduleReason += "Module $($module.Name) $($importedVersion)$($importedVersion ? " " : $null)is imported."
                                            if (!$isRequiredVersionImported) {
                                                $moduleReason += "Module $($module.Name) $($requiredVersion ?? $minimumVersion ?? $maximumVersion)$(($requiredVersion ?? $minimumVersion ?? $maximumVersion) ? " " : $null)is not imported."
                                            }
                                        }
                                        else {
                                            $isModuleImported = $false
                                            $isRequiredVersionImported = $false
                                            $moduleReason += "Module $($module.Name) $($importedVersion)$($importedVersion ? " " : $null)is not imported."
                                        }

                                    }

                                }
                                else {
                                    $moduleReason += "Module $($module.Name) $($requiredVersion ?? $minimumVersion ?? $maximumVersion)$(($requiredVersion ?? $minimumVersion ?? $maximumVersion) ? " " : $null)was not found$(![string]::$module.Repository ? " in repository '$($module.Repository)'" : $null)."
                                }

                                $_module = [ordered]@{}
                                $_module += [ordered]@{ 
                                    Name = $module.name
                                    Status = $isModuleInstalled -and $isRequiredVersionInstalled ? "Installed" : "Not Installed"
                                    MinimumVersion = $minimumVersion
                                    MaximumVersion = $maximumVersion
                                    RequiredVersion = $requiredVersion
                                    InstalledVersion = $installedVersion                             
                                    IsInstalled = $isModuleInstalled
                                    IsRequiredVersionInstalled = $isRequiredVersionInstalled
                                    ImportedVersion = $importedVersion                             
                                    IsImported = $isModuleImported
                                    IsRequiredVersionImported = $isRequiredVersionImported
                                    Reason = $moduleReason
                                    Source = "Repository"
                                    Repository = $psModuleRepositoryName
                                    VersionToInstall = $null
                                }

                                # finalize version properties
                                if (![string]::IsNullOrEmpty($minimumVersion)) { 
                                    $_module.VersionToInstall = "MinimumVersion"; $_module.MinimumVersion = $minimumVersion
                                }
                                elseif (![string]::IsNullOrEmpty($maximumVersion)) {
                                    $_module.VersionToInstall = "MaximumVersion"; $_module.MaximumVersion = $maximumVersion
                                }
                                elseif (![string]::IsNullOrEmpty($requiredVersion)) {
                                    $_module.VersionToInstall = "RequiredVersion"; $_module.RequiredVersion = $requiredVersion
                                }
                                if ([string]::IsNullOrEmpty($minimumVersion)) { $_module.Remove("MinimumVersion") }
                                if ([string]::IsNullOrEmpty($maximumVersion)) { $_module.Remove("MaximumVersion") }
                                if ([string]::IsNullOrEmpty($requiredVersion)) { $_module.Remove("requiredVersion") } 
                                
                                # copy other properties from module object
                                foreach ($key in ($module.keys | Where-Object {$_ -notin $_module.keys} | Sort-Object)) {
                                    $_module += [ordered]@{ $key = $module.$key }
                                }

                                $prerequisiteTest.$($prerequisite.Type).Modules += $_module                               
                                $_isInstalled = $_isInstalled -and $isModuleInstalled -and $isRequiredVersionInstalled

                            }

                            if (!$prerequisite.$($prerequisite.Type).Modules) {
                                $prerequisite.$($prerequisite.Type) += @{ Modules = $prerequisiteId.Modules }
                            }
                            else {
                                $prerequisite.$($prerequisite.Type).Modules += $prerequisiteId.Modules
                            }
                            $prerequisite.Id = "Modules"

                        }
                        if ($prerequisite.Id.Packages) {
                            $prerequisiteTest.DisplayName = "PowerShell Packages"
                            $prerequisiteTest.$($prerequisite.Type) += @{ Packages = @() }
                            $prerequisiteTest.Id = "Packages"
                            foreach ($package in $prerequisite.Id.Packages) {

                                $packageReason = @()
                                
                                $packageRequiredVersion = ![string]::IsNullOrEmpty($package.RequiredVersion) ? $package.RequiredVersion : $null
                                $packageMinimumVersion = [string]::IsNullOrEmpty($package.RequiredVersion) -and ![string]::IsNullOrEmpty($package.MinimumVersion) ? $package.MinimumVersion : $null
                                $packageMaximumVersion = [string]::IsNullOrEmpty($package.RequiredVersion) -and [string]::IsNullOrEmpty($package.MinimumVersion) -and ![string]::IsNullOrEmpty($package.MaximumVersion) ? $package.MaximumVersion : $null
                                
                                $psPackageProviderName = ![string]::IsNullOrEmpty($package.ProviderName) ? $package.ProviderName : $global:PsDefaultPackageProviderName
                                $providerPackage = Find-Package -Name $package.Name -ProviderName $psPackageProviderName -AllVersions -ErrorAction SilentlyContinue| Sort-Object -Property Version -Descending
                                
                                $installedPackage = $null # establish scope
                                $requiredVersion = $minimumVersion = $maximumVersion = $null
                                if ($providerPackage) {

                                    $requiredVersion = ![string]::IsNullOrEmpty($packageRequiredVersion) ? $packageRequiredVersion : $null                                    
                                    if (!(IsValidVersion -Version $packageRequiredVersion -Package $providerPackage)) {
                                        throw "RequiredVersion $packageRequiredVersion for package $($package.Name) must be between $($providerPackage.Version[-1]) and $($providerPackage.Version[0])."
                                    }
                                    if ([string]::IsNullOrEmpty($packageRequiredVersion)) {
                                        $minimumVersion = ![string]::IsNullOrEmpty($packageMinimumVersion) ? $packageMinimumVersion : $null                                    
                                        if (!(IsValidVersion -Version $packageMinimumVersion -Package $providerPackage)) {
                                            throw "MinimumVersion $packageMinimumVersion for package $($package.Name) must be between $($providerPackage.Version[-1]) and $($providerPackage.Version[0])."
                                        }
                                        $maximumVersion = ![string]::IsNullOrEmpty($packageMaximumVersion) ? $packageMaximumVersion : $null                                    
                                        if (!(IsValidVersion -Version $packageMaximumVersion -Package $providerPackage)) {
                                            throw "MaximumVersion $packageMaximumVersion for package $($package.Name) must be between $($providerPackage.Version[-1]) and $($providerPackage.Version[0])."
                                        }
                                    }
                                    
                                    $installedPackage = @()
                                    $installedPackage += Get-Package -Name $package.Name -Scope AllUsers -AllVersions -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending
                                    $installedPackage += Get-Package -Name $package.Name -Scope CurrentUser -AllVersions -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending
                                    $installedPackageVersion = [array]$installedPackage.Version # this needs to be an array for the comparisons below to work
                                    
                                    if ($installedPackage) {
                                        $isPackageInstalled = $true
                                        $isRequiredVersionInstalled = (
                                            ([string]::IsNullOrEmpty($requiredVersion) -and [string]::IsNullOrEmpty($minimumVersion) -and [string]::IsNullOrEmpty($maximumVersion)) -or 
                                            ((![string]::IsNullOrEmpty($requiredVersion) -and $requiredVersion -in $installedPackageVersion) -or 
                                            (![string]::IsNullOrEmpty($minimumVersion) -and $installedPackageVersion[0] -ge $minimumVersion) -or 
                                            (![string]::IsNullOrEmpty($maximumVersion) -and $installedPackageVersion[0] -le $maximumVersion))
                                        )
                                        $installedVersion = $installedPackageVersion[0]
                                        if (![string]::IsNullOrEmpty($requiredVersion) -and $requiredVersion -in $installedPackageVersion) {
                                            $installedVersion = $requiredVersion
                                        }
                                        $packageReason = "Package $($package.Name) $($installedVersion)$($installedVersion ? " " : $null)is installed."
                                        if (!$isRequiredVersionInstalled -and $installedVersion -eq $installedPackageVersion[0]) {
                                            $packageReason = "Package $($package.Name) $($requiredVersion ?? $minimumVersion ?? $maximumVersion)$(($requiredVersion ?? $minimumVersion ?? $maximumVersion) ? " " : $null)is required but not installed."
                                        }
                                        elseif ($installedVersion -ne $installedPackageVersion[0]) {
                                            $packageReason = "Package $($package.Name) $installedVersion is required, but package $($package.Name) $($installedPackageVersion[0]) is installed."
                                        }
                                    }
                                    else {
                                        $isPackageInstalled = $false
                                        $isRequiredVersionInstalled = $false
                                        $packageReason = "Package $($package.Name) $($installedVersion)$($installedVersion ? " " : $null)is required but not installed."
                                    }

                                }
                                else {
                                    $packageReason = "Package $($package.Name) $($requiredVersion ?? $minimumVersion ?? $maximumVersion)$(($requiredVersion ?? $minimumVersion ?? $maximumVersion) ? " " : $null)was not found$(![string]::$package.Repository ? " in repository '$($package.Repository)'" : $null)."
                                }
                                $_package = [ordered]@{}
                                $_package += [ordered]@{ 
                                    Name = $package.name
                                    Status = $isPackageInstalled -and $isRequiredVersionInstalled ? "Installed" : "Not Installed"
                                    MinimumVersion = $minimumVersion
                                    MaximumVersion = $maximumVersion
                                    RequiredVersion = $requiredVersion
                                    InstalledVersion = $installedVersion                             
                                    IsInstalled = $isPackageInstalled
                                    IsRequiredVersionInstalled = $isRequiredVersionInstalled
                                    Reason = $packageReason
                                    Source = "ProviderName"
                                    ProviderName = $psPackageProviderName
                                    VersionToInstall = $null
                                    SkipDependencies = $package.SkipDependencies
                                }
                                if (![string]::IsNullOrEmpty($minimumVersion)) { $_package.VersionToInstall = "MinimumVersion"; $_package.MinimumVersion = $minimumVersion }
                                elseif (![string]::IsNullOrEmpty($maximumVersion)) { $_package.VersionToInstall = "MaximumVersion"; $_package.MaximumVersion = $maximumVersion }
                                elseif (![string]::IsNullOrEmpty($requiredVersion)) { $_package.VersionToInstall = "RequiredVersion"; $_package.RequiredVersion = $requiredVersion } 
      
                                if ([string]::IsNullOrEmpty($minimumVersion)) { $_package.Remove("MinimumVersion") }
                                if ([string]::IsNullOrEmpty($maximumVersion)) { $_package.Remove("MaximumVersion") }
                                if ([string]::IsNullOrEmpty($requiredVersion)) { $_package.Remove("requiredVersion") }   
                                $prerequisiteTest.$($prerequisite.Type).Packages += $_package                               
                                $_isInstalled = $_isInstalled -and $isPackageInstalled -and $isRequiredVersionInstalled

                            }

                            if (!$prerequisite.$($prerequisite.Type).Packages) {
                                $prerequisite.$($prerequisite.Type) += [ordered]@{ Packages = $prerequisiteId.Packages }
                            }
                            else {
                                $prerequisite.$($prerequisite.Type).Packages += $prerequisiteId.Packages
                            }
                            $prerequisite.Id = "Packages"

                        }
                    }
                    $prerequisiteTest.Status = $_isInstalled ? "Installed" : "Not Installed"
                    $prerequisiteTest.Pass = $_isInstalled
                    $prerequisiteTest.Block = !$prerequisiteTest.Pass
                }

                # test for prerequisite types which are os or platform services
                if ($prerequisite.Type -in @("Service","PlatformService")) {
                    $_service = switch ($prerequisite.Type) {
                        "Service" {
                            Get-Service+ -ComputerName $ComputerName -Name $prerequisiteId 
                        }
                        "PlatformService" {
                            Get-PlatformService -ComputerName $ComputerName -Name $prerequisiteId 
                        }
                    }
                    $_isInstalled = $_service.Status -eq "Running"
                    $prerequisiteTest.$($prerequisite.Type) = $prerequisiteId 
                    $prerequisiteTest.Status = $_service.Status ?? "Not Running"
                    $prerequisiteTest.Pass = $_isInstalled
                    $prerequisiteTest.Block = !$prerequisiteTest.Pass
                    if (!$prerequisiteTest.Pass) {
                        $prerequisiteTest += @{ Reason = "The $($_service.Name) service is $($_service.Status)."}
                    }
                }

                # test for prerequisites which have the Installation.IsInstalled test defined
                $installationTest = $global:Catalog.$($prerequisite.Type).$prerequisiteId.Installation.IsInstalled
                if ($installationTest) {
                    if ($installationTest.Command) {
                        $_scriptBlock = (Get-Catalog -Type $prerequisite.Type -Id $prerequisiteId -ComputerName $ComputerName).Installation.IsInstalled.Command
                        $_isInstalled = Invoke-Command -ScriptBlock $_scriptBlock #-ComputerName $ComputerName
                    }
                    else {
                        $_service = switch ($installationTest.Type) {
                            "Service" {
                                Get-Service+ -ComputerName $ComputerName -Name $($installationTest.$($installationTest.Type))
                            }
                            "PlatformService" {
                                Get-PlatformService -ComputerName $ComputerName -Name $($installationTest.$($installationTest.Type))
                            }
                        }
                        $_isInstalled = $_service.Status -eq "Running"
                    }
                    $prerequisiteTest.$($prerequisite.Type) = $prerequisiteId 
                    $prerequisiteTest.Status = $_isInstalled ? "Installed" : "Not Installed"
                    $prerequisiteTest.Pass = $_isInstalled
                    $prerequisiteTest.Block = !$prerequisiteTest.Pass
                    if (!$prerequisiteTest.Pass) {
                        $prerequisiteTest += @{ Reason = "The $($prerequisite.Id) $($prerequisite.Type) is $($prerequisiteTest.Status)."}
                    }
                }                

                # test for prerequisite types which are catalog objects
                if (!$installationTest -and $prerequisite.Type -in $global:Catalog.Keys) {
                    $global:Catalog.$($prerequisite.Type).$prerequisiteId.Refresh()
                    $_isInstalled = $global:Catalog.$($prerequisite.Type).$prerequisiteId.Installed
                    $prerequisiteTest.$($prerequisite.Type) = $prerequisiteId 
                    $prerequisiteTest.Pass = $_isInstalled
                    $prerequisiteTest.Status = $prerequisiteTest.Pass ? "Installed" : "Not Installed"
                    # TODO: what about testing prerequisites of prerequisites?  for example:  the Portable.BouncyCastle package is required by the MimeKit package
                    # right now, prerequisites and their prerequistes are all tested at the same level
                    # tried testing prerequisites of prerequisites, but it went cray-cray
                    # $prerequisiteTest.Results = Test-Prerequisites -Type $prerequisite.Type -Id $prerequisiteId -PrerequisiteType Installation -Quiet:$Quiet
                    if (!$prerequisiteTest.Pass) {
                        $prerequisiteTest.Block = $true
                        if ($global:Catalog.$($prerequisite.Type).$prerequisiteId.Installation.Flag) {
                            if (Compare-Object $global:Catalog.$($prerequisite.Type).$prerequisiteId.Installation.Flag @("AlwaysInstall","NoPrompt") -ExcludeDifferent -PassThru) {
                                $prerequisiteTest.Block = $false
                            }
                        }
                        $prerequisiteTest += @{ Reason = "The $($prerequisite.Id) $($prerequisite.Type) is $($prerequisiteTest.Status)."}
                    }
                }

                $prerequisite.Pass = $prerequisite.Pass -or $prerequisiteTest.Pass
                $prerequisite.Block = $prerequisite.Block -or $prerequisiteTest.Block
                $prerequisite.Tests += $prerequisiteTest

                $statusMessage = $prerequisiteTest.Pass ? "INSTALLED" : "NOT INSTALLED"
                $blockMessage = $prerequisiteTest.Pass ? "" : $($prerequisiteTest.Block ? "" : "NON-BLOCKING") 
                Write-Host+ -Iff $(!$Quiet) -NoTrace -NoSeparator "    $($prerequisiteTest.DisplayName) ", $statusMessage, $(![string]::IsNullOrEmpty($blockMessage) ? ", " : ""), $blockMessage -ForegroundColor Gray,($prerequisiteTest.Pass ? "DarkGreen" : "Red"),DarkGray,($prerequisiteTest.Block ? "Red" : "DarkGreen")

            }
            $prerequisite.Tests = $prerequisite.Tests
            $prerequisite.Status = $prerequisite.Pass ? "Installed" : "Not Installed"

            $results.Pass = $results.Pass -and $prerequisite.Pass
            $results.Installable = $results.Installable -and !$prerequisite.Block
            $results.Prerequisites += $prerequisite

        }

        Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse "<  Prerequisites <.>48> COMPLETED" -ForegroundColor Gray,DarkGray,DarkGreen
        Write-Host+ -Iff $(!$Quiet) -NoTrace -Parse "<$Type $Id <.>48> $($results.Pass ? "SUCCESS" : "FAIL" )" -ForegroundColor Gray,DarkGray,($results.Pass ? "DarkGreen" : "Red")

        return $results

    }    

    function global:Wait-Prerequisites {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,ParameterSetName="Uid",Position=0)][ValidatePattern("^(\w*?)\.{1}(\w*?)$")][string]$Uid,
            [Parameter(Mandatory=$true,ParameterSetName="TypeAndId")][string]$Type,
            [Parameter(Mandatory=$true,ParameterSetName="TypeAndId")][string]$Id,
            [Parameter(Mandatory=$false)][ValidateSet("Initialization","Installation")][string]$PrerequisiteType = "Initialization",
            [Parameter(Mandatory=$false)][string]$PrerequisiteFilter,
            [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
            [switch]$Quiet
        )
    
        $loopSecondsToWait = 15
        $timeout = New-TimeSpan -Minutes 10
    
        $prerequisiteTestResults = Test-Prerequisites -Type $Type -Id $Id -PrerequisiteType $PrerequisiteType -PrerequisiteFilter $PrerequisiteFilter -ComputerName $ComputerName -Quiet:$($Quiet.IsPresent)
        if (!$prerequisiteTestResults.Pass) {
            Write-Host+ -NoTrace $prerequisiteTestResults.Prerequisites[0].Tests.Reason -ForegroundColor Red
            Write-Host+ -NoTrace "Waiting for $Type $Id" -ForegroundColor DarkGray
            $timer = [Diagnostics.Stopwatch]::StartNew()
            do {
                if ([math]::Round($timer.Elapsed.TotalSeconds,0) -ge $loopSecondsToWait) {
                    Write-Host+ -NoTrace "Waiting for $Type $Id ($([math]::Round($timer.Elapsed.TotalSeconds,0)) seconds)" -ForegroundColor DarkGray
                }
                Start-Sleep -Seconds $loopSecondsToWait
                $prerequisiteTestResults = Test-Prerequisites -Type $Type -Id $Id -Quiet
            } until (
                $prerequisiteTestResults.Pass -or [math]::Round($timer.Elapsed.TotalSeconds,0) -gt $timeout.TotalSeconds
            )
            $timer.Stop()
            if (!$prerequisiteTestResults.Pass) {
                Write-Host+ -NoTrace "Timeout waiting for $Type $Id for $([math]::Round($timer.Elapsed.TotalSeconds,0)) seconds" -ForegroundColor Red
            }
            else {
                Write-Host+ -NoTrace "$Type $Id available" -ForegroundColor Red
            }
        }
    
    }    

#endregion TESTS
#region MISC

    function global:Get-PlatformCimInstance {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$View
        )

        $PlatformServices = Get-PlatformServices -ErrorAction SilentlyContinue
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
                    $outputObject
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
                foreach ($pkey in $InputObject.Keys) {
                    $ht.$pkey = ConvertFrom-XmlElement -InputObject $InputObject.$pkey
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
            Write-Host+ -IfVerbose "calling with $($node.LocalName)" -ForegroundColor DarkYellow
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
                Write-Host+ -IfVerbose "pseudo-Array $($_.Name)" -ForegroundColor DarkYellow
                $oHash.($_.Name) = @() <# create an empty array for each one#>
            };
            foreach ($child in $node.ChildNodes)
            {#now we look at each node in turn.
                Write-Host+ -IfVerbose "processing the '$($child.LocalName)'" -ForegroundColor DarkYellow
                $childName = $child.LocalName
                if ($child -is [system.xml.xmltext])
                # if it is simple XML text 
                {
                    Write-Host+ -IfVerbose "simple xml $childname"; -ForegroundColor DarkYellow
                    $oHash.$childname += $child.InnerText
                }
                # if it has a #text child we may need to cope with attributes
                elseif ($child.FirstChild.Name -eq '#text' -and $child.ChildNodes.Count -eq 1)
                {
                    Write-Host+ -IfVerbose "text"; -ForegroundColor DarkYellow
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
                    Write-Host+ -IfVerbose "cdata section"; -ForegroundColor DarkYellow
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

    function global:ConvertTo-PowerShell {

        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline)][object]$InputObject,
            [Parameter(Mandatory=$false)][int]$Indent = 0
        )
        begin {}
        process {
            
            $OutputObject = $InputObject | ConvertTo-Json -Depth 10

            $OutputObject = $OutputObject -replace """(.*)"":",'$1:' 
            $OutputObject = $OutputObject -replace ": \{",' = @{'
            $OutputObject = $OutputObject -replace ": \[",' = @('
            $OutputObject = $OutputObject -replace "\]",")"
            $OutputObject = $OutputObject -replace ": ",' = '
            $OutputObject = $OutputObject -replace "\},",'}'
            $OutputObject = $OutputObject -replace "\),",')'
            $OutputObject = $OutputObject -replace "null",'$null'
            $OutputObject = $OutputObject -replace "true",'$true'
            $OutputObject = $OutputObject -replace "false",'$false'

            foreach ($match in ([regex]::Matches($OutputObject,"@\(.*?\)",[System.Text.RegularExpressions.RegexOptions]::SingleLine).Groups.Value)) {
                $substitution = $match -replace ",","__,__"
                $OutputObject = $OutputObject -replace [regex]::Escape($match), $substitution
            }

            # foreach ($match in ([regex]::Matches($OutputObject,"@\{.*?\}",[System.Text.RegularExpressions.RegexOptions]::SingleLine).Groups.Value)) {
            #     $substitution = $match -replace ",",""
            #     $OutputObject = $OutputObject -replace [regex]::Escape($match), $substitution
            # }

            $OutputObject = $OutputObject -replace ",",""

            foreach ($match in ([regex]::Matches($OutputObject,"@\(.*?\)",[System.Text.RegularExpressions.RegexOptions]::SingleLine).Groups.Value)) {
                $substitution = $match -replace "__,__",","
                $OutputObject = $OutputObject -replace [regex]::Escape($match), $substitution
            }

            # get rid of outer curly brackets
            $OutputObject = ([regex]::Matches($OutputObject,"^\{\s*\n(.*)\n\s*\}$",[System.Text.RegularExpressions.RegexOptions]::SingleLine)).Groups[1].Value

            # replace two-space indent to four-space indent
            $OutputObject = $OutputObject -replace "  ", "    "

            # if $Indent, prepend $Indent number of spaces (minus the four already there)
            $outputObject = ($outputObject -split '\r?\n' | Foreach-Object {"$($emptyString.PadLeft($Indent-4," "))$_"}) | Out-String

        }
        end {
            return $OutputObject
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

#endregion MISC
#region POSTINSTALLATION

function global:Show-PostInstallation {

    $templateFiles = @()
    $manualConfigFiles = @()
    $templateFiles += Get-Item -Path "definitions\definitions-*.ps1"
    $templateFiles += Get-Item -Path "initialize\initialize*.ps1"
    $templateFiles += Get-Item -Path "preflight\preflight*.ps1"
    $templateFiles += Get-Item -Path "postflight\postflight*.ps1"
    $templateFiles += Get-Item -Path "install\install*.ps1"
    foreach ($templateFile in $templateFiles) {
        if (Select-String $templateFile -Pattern "Manual Configuration > " -SimpleMatch -Quiet) {
            $manualConfigFiles += $templateFile
        }
    }

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace -NoTimestamp "Post-Installation" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "-----------------" -ForegroundColor DarkGray

    $postInstallConfig = $false
    $disabledPlatformTasks = Get-PlatformTask -Disabled
    if ($disabledPlatformTasks.Count -gt 0) {
        Write-Host+ -NoTrace -NoTimeStamp "Product > All > Task > Enable disabled tasks"
        Write-Host+ -SetIndentGlobal 0 -SetTimeStampGlobal Exclude -SetTraceGlobal Exclude
        Get-PlatformTask | Show-PlatformTasks
        Write-Host+ -SetIndentGlobal $_indent -SetTimeStampGlobal Ignore -SetTraceGlobal Ignore
        $postInstallConfig = $true
    }

    if ($manualConfigFiles) {
        foreach ($manualConfigFile in $manualConfigFiles) {
            $manualConfigStrings = Select-String $manualConfigFile -Pattern "Manual Configuration > " -SimpleMatch -NoEmphasis -Raw
            foreach ($manualConfigString in $manualConfigStrings) {
                $manualConfigMeta = $manualConfigString -split " > "
                if ($manualConfigMeta) {
                    $manualConfigObjectType = $manualConfigMeta[1]
                    $manualConfigObjectId = $manualConfigMeta[2]
                    $manualConfigAction = $manualConfigMeta[3]
                    if ($manualConfigObjectType -in ("Product","Provider")) {
                        # if the file belongs to a Product or Provider that is NOT installed, ignore the post-installation configuration
                        if (!(Invoke-Expression "Get-$manualConfigObjectType $manualConfigObjectId")) { continue }
                    }
                    $postInstallConfig = $true
                    $message = "$manualConfigObjectType > $manualConfigObjectId > $manualConfigAction > Edit $($manualConfigFile.FullName)"
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor Gray,DarkGray,Gray
                }
            }
        }
    }

    #region FILES NOT IN SOURCE

        $allowList = @()
        $allowListFile = "$($global:Location.Data)\fileAllowList.csv"
        if (Test-Path -Path $allowListFile) {
            $allowList += Import-csv -Path $allowListFile
        }
        $source = (Get-ChildItem -Path $global:Location.Source -Recurse -File -Name | Split-Path -Leaf) -Replace "-template",""  | Sort-Object
        $prod = $(foreach ($dir in (Get-ChildItem -Path $global:Location.Root -Directory -Exclude data,logs,temp,source,.*).FullName) {(Get-ChildItem -Path $dir -Name -File -Exclude LICENSE,README.md,install.ps1,.*) }) -Replace $global:Platform.Instance, $global:Platform.Id | Sort-Object
        $obsolete = foreach ($file in $prod) {if ($file -notin $source) {$file}}
        $obsolete = $(foreach ($dir in (Get-ChildItem -Path $global:Location.Root -Directory -Exclude data,logs,temp,source).FullName) {(Get-ChildItem -Path $dir -Recurse -File -Exclude LICENSE,README.md,install.ps1,.*) | Where-Object {$_.name -in $obsolete}}).FullName
        $obsolete = $obsolete | Where-Object {$_ -notin $allowList.Path}

        if ($obsolete) {
            foreach ($file in $obsolete) {
                Write-Host+ -NoTrace -NoTimestamp "File > Obsolete/Extraneous > Remove/AllowList* $file" -ForegroundColor Gray
            }
            $postInstallConfig = $true
        }

    #endregion FILES NOT IN SOURCE

    if (!$postInstallConfig) {
        Write-Host+ -NoTrace -NoTimeStamp "No post-installation configuration required."
    }
    elseif ($obsolete) {
        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "*AllowList: $($global:Location.Data)\fileAllowList.csv" -ForegroundColor DarkGray
    }

    Write-Host+
    # Write-Host+ -ResetAll

}
Set-Alias -Name postInstall -Value Show-PostInstallation -Scope Global

#endregion POSTINSTALLATION
#region LOCAL ADMIN/RUNAS

    function global:Test-LocalAdmin {
        return Test-Credentials "localadmin-$($global:Platform.Instance)" -NoValidate
    }

    function global:Set-LocalAdmin {

        [CmdletBinding()]
        param (
            [switch]$Force
        )

        # get the current local admin username from the "localadmin-$($global:Platform.Instance)" credentials
        # if the credentials haven't been set or -Force has been specified, prompt for and set/replace credentials
        if (!(Test-Credentials "localadmin-$($global:Platform.Instance)" -NoValidate) -or $Force) {
            if (!$global:WriteHostPlusEndOfLine) { Write-Host+ } # close any pending newline
            Write-Host+
            if ((Test-Credentials "localadmin-$($global:Platform.Instance)" -NoValidate) -and $Force) {
                $localAdminCredentials = Get-Credentials "localadmin-$($global:Platform.Instance)"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Replace $($localAdminCredentials.Username) as the local admin (Y/N)? ", "[N]", ": " -ForegroundColor Gary, Blue, Gray
                if ((Read-Host).ToUpper() -ne "Y") { return }
            }
            do {
                Request-Credentials -Title "  Overwatch Local Admin Credentials" -Prompt1 "  Username" -Prompt2 "  Password" | Set-Credentials "localadmin-$($global:Platform.Instance)" | Out-Null
            } until (
                Test-Credentials -NoValidate "localadmin-$($global:Platform.Instance)"
            )
            Write-Host+
        }
        $localAdminCredentials = Get-Credentials "localadmin-$($global:Platform.Instance)"

        # what type of username?  (Local, AD, AzureAD)
        if ([Regex]::IsMatch($localAdminCredentials.Username,$global:RegexPattern.Username.DownLevelLogonName)) {
            $username = ([Regex]::Matches($localAdminCredentials.Username,$global:RegexPattern.Username.DownLevelLogonName))[0].Groups["Username"].Value
            $localAdmin = Get-LocalUser+ -Name $username
            Remove-Variable username
        }
        elseif ([Regex]::IsMatch($localAdminCredentials.Username,$global:RegexPattern.Username.AzureAD)) {
            Write-Host+
            Write-Host+ "  AzureAD security principals are not yet supported." -ForegroundColor DarkRed
            Write-Host+
            return
        }
        elseif ([Regex]::IsMatch($localAdminCredentials.Username,$global:RegexPattern.Username.AD)) {
            Write-Host+
            Write-Host+ "  AD security principals are not yet supported." -ForegroundColor DarkRed
            Write-Host+
            return
        }

        # ensure the local admin/runas user exists and, if not, create it
        if (!$localAdmin) {
            if ([Regex]::IsMatch($localAdminCredentials.Username,$global:RegexPattern.Username.DownLevelLogonName)) {
                $localAdmin = New-LocalUser+ -Name $username -Password $localAdminCredentials.GetNetworkCredential().Password -PasswordNeverExpires $true -Description "Overwatch LocalMachine Admin"
            }
        }

        # ensure the local admin/runas user is a member of the local administrators group
        if ((Get-LocalGroup+ -Name "Administrators").Members.Name -notcontains $localAdmin.username ) {
            # add user to local Administrators group
            $localAdministrators = Add-LocalGroupMember+ -Name "Administrators" -Member $localAdmin.Name
            $localAdministrators | Out-Null
        }

        # find/get the overwatch installation [root] directory object
        $catalogFileContent = Get-Content -Path $global:Location.Catalog -Raw
        $result = [regex]::Matches($catalogFileContent, $global:RegexPattern.Overwatch.Registry.Path)
        $overwatchRegistryPath = $result[0].Groups['OverwatchRegistryPath'].Value
        $overwatchRegistryKey = "InstallLocation"
        $overwatchInstallLocation = (Get-ItemProperty -Path $overwatchRegistryPath -Name $overwatchRegistryKey).InstallLocation
        $overwatchDirectory = Get-Files -Path $overwatchInstallLocation

        # grant FullControl file system rights to user for Overwatch directory (including all subdirectories and files)
        $localAdminACE = $overwatchDirectory.GetAcl().Access | Where-Object {$_.IdentityReference -eq $localAdmin.Username}
        if (!$localAdminACE -or ($localAdminACE -and $localAdminACE.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl)) {
            $overwatchDirectoryACL = $overwatchDirectory.SetAcl($localAdmin.Name,"FullControl",3,0,"Allow")
            $overwatchDirectoryACL | Out-Null
        }

    }

#endregion LOCAL ADMIN/RUNAS