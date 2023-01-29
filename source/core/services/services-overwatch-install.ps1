#region FILE MANAGEMENT

function script:Copy-File {

    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [Parameter(Mandatory=$false)][string]$Component,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Suite,
        [switch]$Quiet,
        [switch]$ConfirmOverwrite,
        [switch]$ConfirmCopy
    )

    if (Test-Path -Path $Path) { 

        $pathFiles = Get-ChildItem $Path
        $destinationIsDirectory = !(Split-Path $Destination -Extension)

        $copiedFile = $false
        $whatIfFiles = @()
        foreach ($pathFile in $pathFiles) {

            $destinationFilePath = $destinationIsDirectory ? "$Destination\$(Split-Path $pathFile -Leaf -Resolve)" : $Destination

            #region DETERMINE COMPONENT AND NAME

                $components = @()
                $names = @()
                $suites = @()

                if (![string]::IsNullOrEmpty($Component)) {

                    $components += $Component
                    $names += ![string]::IsNullOrEmpty($Name) ? $Name : @()
                    $suites += ![string]::IsNullOrEmpty($Suite) ? $Suite : @()

                }
                else {

                    # parse $pathFile for source subdirectories indicating component and name                
                    $pathKeys = @()
                    $pathKeys += ($pathFile | Split-Path -Parent).Replace("$($global:Location.Scripts)\","",1).Replace("source\","",1) -Split "\\"
                    $pathKeys += ($pathFile | Split-Path -LeafBase).Replace("-template","")

                    # if the subdirectory is "services", then search the catalog for the component and name/suite
                    if (("services") -icontains $pathKeys[0]) {
                        foreach ($_key in $global:Catalog.Keys | Where-Object {$_ -ne "Overwatch"}) {
                            foreach ($_subKey in $global:Catalog.$_key.Keys) {
                                # if $_key is OS or Platform, then $_subKey must be the OS or Platform installed
                                if ($_key -in ("OS","Platform") -and $_subKey -notin $global:Environ.$_key) {
                                    # ignore
                                }
                                else {
                                    foreach ($service in $global:Catalog.$_key.$_subKey.Installation.Prerequisite.Service) {
                                        if ($service -eq $pathKeys[1]) {
                                            $components += $global:Catalog.Keys | Where-Object {$_ -eq $_key}
                                            $names += $global:Catalog.$_key.Keys | Where-Object {$_ -eq $_subKey}
                                            if ($global:Catalog.$_key.$_subKey.Suite) {
                                                $suites += $global:Catalog.$_key.$_subKey.Suite
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    # otherwise use the parsed $pathFile and capitalize the component and name
                    else {
                        $components = (Get-Culture).TextInfo.ToTitleCase($pathKeys[0])
                        if ($components -eq "Providers") { $components = "Provider" }
                        $names = (Get-Culture).TextInfo.ToTitleCase($pathKeys[1]) 
                        foreach ($_key in $global:Catalog.Keys) {
                            if ($components -eq $_key) { 
                                $components = $_key
                                $names = $global:Catalog.$_key.$names.Id
                            }

                        }
                    }

                }

                # if component/name/suite are arrays, sort uniquely and comma-separate
                $_component = ($components | Sort-Object -Unique) -join ","
                $_name = ($names | Sort-Object -Unique) -join ","
                $_suite = $suites.Count -gt 0 ? ($suites | Sort-Object -Unique) -join "," : $null

                $_suiteOrComponent = ![string]::IsNullOrEmpty($_suite) ? "$_component Suite" : $_component
                $_suiteOrName = ![string]::IsNullOrEmpty($_suite) ? $_suite : $_name

            #endregion DETERMINE COMPONENT AND NAME

            if (!(Test-Path -Path $destinationFilePath -PathType Leaf)) {

                if ($PSBoundParameters.ContainsKey('WhatIf')) {
                    $whatIfFiles += @{
                        Source = $pathFile
                        Destination = $destinationFilePath
                        Component = $_component
                        $_component = $_name
                        Suite = $_suite
                    }
                }
                else {
                    Copy-Item -Path $pathFile $destinationFilePath
                    $copiedFile = $true
                }

                if ($PSBoundParameters.ContainsKey('WhatIf')) {
                    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp "  [$_suiteOrComponent`:$_suiteOrName] $pathFile" -ForegroundColor DarkGray
                }
                else {
                    Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp "  Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
                }

            }
            else {

                $noClobber = $destinationFilePath -in $global:Catalog.$_component.$_name.Installation.NoClobber
                
                # if hash is different, file contents are different. 
                # but this may be install parameters only, so compare LastWriteTime
                # update pathFile IFF the hash is different and the source file is newer
                $pathHashIsDifferent = (Get-FileHash $pathFile).hash -ne (Get-FileHash $destinationFilePath).hash
                $destinationFile = Get-ChildItem $destinationFilePath
                $pathFileIsNewer = $pathFile.LastWriteTime -gt $destinationFile.LastWriteTime
                
                $pathFileTemplateUpdate = $false
                if ($pathFile.FullName.EndsWith("-template.ps1")) {
                    $pathFileTemplateVariables = [regex]::Matches((Get-Content $pathFile), "((?'key'\S*?)\s*\=\s*)`"(?'value'<[a-zA-z]*?>)`"", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object {$_.Groups["value"].Value}
                    if ($pathFileTemplateVariables) {
                        $destinationFilePathTemplateVariables = $pathFileTemplateVariables | ForEach-Object { [regex]::Matches((Get-Content $destinationFilePath), $_, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
                        if ($destinationFilePathTemplateVariables) { 
                            $pathFileTemplateUpdate = $true 
                        }
                    }
                }

                $updatePathFile = ($pathHashIsDifferent -and $pathFileIsNewer) -or $pathFileTemplateUpdate

                if ($pathHashIsDifferent -and !$pathFileNewer) {
                    Write-Host+ -IfDebug -NoTrace -NoTimestamp "  DEBUG: $pathFile is different from $destinationFile, but $destinationFile is newer." -ForegroundColor DarkGray
                }

                if (!$updatePathFile) {
                    # skip copy if the source file contents are identical to the target file contents
                    # or if the source file's LastWriteTime is older than the path file's LastWriteTime
                }
                else {

                    
                    if ($PSBoundParameters.ContainsKey('WhatIf')) {
                        $whatIfFiles += @{
                            Source = $pathFile
                            Destination = $destinationFilePath
                            Component = $_component
                            $_component = $_name
                            Suite = $_suite
                            NoClobber = $noClobber
                        }
                    }
                    elseif (!$noClobber) {
                        Copy-Item -Path $pathFile $destinationFilePath
                        $copiedFile = $true
                    }

                    if ($PSBoundParameters.ContainsKey('WhatIf')) {
                        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoNewLine "  [$_suiteOrComponent`:$_suiteOrName] $pathFile" -ForegroundColor $($noClobber ? "DarkYellow" : "DarkGray")
                        Write-Host+ -Iff $(!$Quiet -and $noClobber) -NoTrace -NoTimestamp " -NOCLOBBER " -ForegroundColor DarkYellow
                        Write-Host+ -Iff $(!$Quiet -and !$noClobber)
                    }
                    else {
                        if (!$noClobber) {
                            Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp "  Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
                        }
                    }

                }

            }
        }

        return $PSBoundParameters.ContainsKey('WhatIf') ? $whatIfFiles : ($ConfirmCopy ? $copiedFile : $null)

    }
}

#endregion FILE MANAGEMENT
#region SETTINGS

    function script:Update-InstallSettings {

        [CmdletBinding()]
        Param ()

        . "$($global:Location.Scripts)\environ.ps1"

        if (Test-Path -Path $($global:InstallSettings)) { Clear-Content -Path $($global:InstallSettings) }
                
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $($global:InstallSettings)
        "Param()" | Add-Content -Path $($global:InstallSettings)
        if (![string]::IsNullOrEmpty($overwatchInstallLocation)) {
            "`$overwatchInstallLocation = ""$overwatchInstallLocation""" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($operatingSystemId)) {
            "`$operatingSystemId = ""$operatingSystemId""" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($cloudId)) {
            "`$cloudId = ""$cloudId""" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($platformId)) {
            "`$platformId = ""$platformId""" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($platformInstallLocation)) {
            "`$platformInstallLocation = ""$platformInstallLocation""" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($platformInstanceId)) {
            "`$platformInstanceId = ""$platformInstanceId""" | Add-Content -Path $($global:InstallSettings)
        }
        if ($global:Environ.Product.Count -gt 0) {
            "`$productIds = @('$($global:Environ.Product -join "', '")')" | Add-Content -Path $($global:InstallSettings)
        }
        if ($global:Environ.Provider.Count -gt 0) {
            "`$providerIds = @('$($global:Environ.Provider -join "', '")')" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($imagesUri)) {
            "`$imagesUri = [System.Uri]::new(""$imagesUri"")" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($platformInstanceUri)) {
            "`$platformInstanceUri = [System.Uri]::new(""$platformInstanceUri"")" | Add-Content -Path $($global:InstallSettings)
        }
        if (![string]::IsNullOrEmpty($platformInstanceDomain)) {
            "`$platformInstanceDomain = ""$platformInstanceDomain""" | Add-Content -Path $($global:InstallSettings)
        }
        if ($platformInstanceNodes.Count -gt 0) {
            "`$platformInstanceNodes = @('$($platformInstanceNodes -join "', '")')" | Add-Content -Path $($global:InstallSettings)
        }
        if ($requiredPythonPackages.Count -gt 0) {
            "`$requiredPythonPackages = @('$($requiredPythonPackages -join "', '")')" | Add-Content -Path $($global:InstallSettings)
        }

    }

#endregion SETTINGS
#region ENVIRON

    function script:Update-Environ {

        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory=$true)][string]$Source,
            [Parameter(Mandatory=$false)][string]$Destination = $Source,
            [Parameter(Mandatory=$false)][ValidateSet("Overwatch","Provider","Product","Location")][string]$Type,
            [Parameter(Mandatory=$false)][string]$Name,
            [Parameter(Mandatory=$false)][string]$Expression = "`"`$(`$global:Location.Root)\$($Name.ToLower())`""
        )

        if ([string]::IsNullOrEmpty($Type)) {
            if (!$PSBoundParameters.ContainsKey('WhatIf')) {
                $environFileContent = Get-Content -Path $Source
                $environFileContent = $environFileContent -replace "<operatingSystemId>", ($operatingSystemId -replace " ","")
                $environFileContent = $environFileContent -replace "<cloudId>", ($cloudId -replace " ","")
                $environFileContent = $environFileContent -replace "<platformId>", ($platformId -replace " ","")
                $environFileContent = $environFileContent -replace "<overwatchInstallLocation>", $overwatchInstallLocation
                $environFileContent = $environFileContent -replace "<platformInstanceId>", $platformInstanceId
                $environProductIds = $global:Environ.Product + $productIds | Sort-Object -Unique
                $environProviderIds = $global:Environ.Provider + $providerIds | Sort-Object -Unique
                $environFileContent = ($environFileContent -replace "<productIds>", "'$($environProductIds -join "', '")'") -replace "'",'"'
                $environFileContent = ($environFileContent -replace "<providerIds>", "'$($environProviderIds -join "', '")'") -replace "'",'"'
                $environFileContent = $environFileContent -replace "<imagesUri>", $imagesUri
                $environFileContent | Set-Content -Path $Destination
            }
            return $PSBoundParameters.ContainsKey('WhatIf') ? $true : $null
        }
        elseif ($Type -eq "Overwatch") {
            if (!$PSBoundParameters.ContainsKey('WhatIf')) {
                Copy-File $Source $Destination -Component Environ -WhatIf -Quiet
            }
            return $PSBoundParameters.ContainsKey('WhatIf') ? $true : $null
        }
        elseif ($Type -eq "Location") {
            $environFileContent = Get-Content -Path $Source -Raw
            if ($environFileContent -match "(?s)\`$global:Location\s*\+=\s*@{(.*)}") {
                $locationContent = $matches[1]
                Write-Host+ -NoTrace -NoTimestamp "  [Environ] `$global:Location.$Name = `"$(Invoke-Expression $Expression)`"" -ForegroundColor DarkGray
                if ($locationContent -match "$Name\s*=\s*`"(.*)`"") {
                    Write-Host+ -NoTrace -NoTimestamp "  [Environ] `$global:Location.$Name = `"$(Invoke-Expression $matches[1])`"" -ForegroundColor DarkGray
                    Write-Host+ -NoTrace -NoTimestamp "  [Environ] Unable to add `"`$global:Location.$Name`"" -ForegroundColor Red
                    return
                }
                elseif (![string]::IsNullOrEmpty($global:Location.$Name) -and$global:Location.$Name -ne $Expression) {
                    Write-Host+ -NoTrace -NoTimestamp "  [Location] `$global:Location.$Name = `"$($global:Location.$Name)`"" -ForegroundColor DarkGray
                    Write-Host+ -NoTrace -NoTimestamp "  [Environ] Unable to add `"`$global:Location.$Name`"" -ForegroundColor Red
                    return
                }
                else {
                    $newLocationContent = $locationContent + "        " + $Name + " = " + $Expression + "`n"
                    $environFileContent = $environFileContent.Replace($locationContent, $newLocationContent)
                    $environFileContent | Set-Content -Path $Destination
                }
            }
        }
        else {
            $environItems = Select-String $Destination -Pattern "$Type = " -Raw
            if (!$PSBoundParameters.ContainsKey('WhatIf')) {
                $updatedEnvironItems = $environItems.Replace("`"$Name`"","").Replace(", ,",",").Replace("(, ","(").Replace(", )",")")
                $content = Get-Content $Destination 
                $newContent = $content | Foreach-Object {$_.Replace($environItems,$updatedEnvironItems)}
                Set-Content $Destination -Value $newContent
            }
            return $PSBoundParameters.ContainsKey('WhatIf') ? $true : $null
        }

        return $PSBoundParameters.ContainsKey('WhatIf') ? $false : $null

    }

#endregion ENVIRON
#region OVERWATCH

    function script:Remove-CoreFiles {

        $files = (Get-ChildItem "$($global:Location.Scripts)\source\core" -File -Recurse -Exclude "uninstall.ps1").VersionInfo.FileName
        foreach ($file in $files) { Remove-Files $file.replace("\source\core","")}
        
        $coreDirectories = @("config","definitions","docs","img","initialize","logs","preflight","postflight","providers","services","temp")
        foreach ($coreDirectory in $coreDirectories) {
            if (Test-Path "$($global:Location.Scripts)\$coreDirectory") {
                Remove-Item "$($global:Location.Scripts)\$coreDirectory" -Recurse}
        }

        Remove-Files "$($global:Location.Scripts)\environ.ps1"
        Remove-Files "$($global:Location.Scripts)\uninstall.ps1"

    }

    function script:Uninstall-Overwatch { 
        
        [CmdletBinding()]
        Param (
            [switch]$Force
        )
        
        Remove-CoreFiles 
        Update-Environ -Type Overwatch -Source "$($global:Location.Scripts)\environ.ps1"

    }

#endregion OVERWATCH
#region OS

    # function script:Uninstall-OS { 

    #     [CmdletBinding()]
    #     Param (
    #         [switch]$Force
    #     )

    #     Remove-OSFiles 

    # }

    # function script:Remove-OSFiles {

    #     Remove-Files "$($global:Location.Scripts)\config\config-os-$($global:Environ.OS.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\definitions\definitions-os-$($global:Environ.OS.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\initialize\initialize-os-$($global:Environ.OS.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\preflight\preflight*-os-$($global:Environ.OS.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\postflight\postflight*-os-$($global:Environ.OS.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\services\services-$($global:Environ.OS.ToLower())*.ps1"

    # }

#endregion OS

#region PLATFORM

    # function script:Uninstall-Platform {

    #     [CmdletBinding()]
    #     Param (
    #         [switch]$Force
    #     )

    #     Remove-PlatformInstanceFiles
    #     Remove-PlatformFiles
    #     Remove-Files "$($global:Location.Data)\*.cache"

    # }

    # function script:Remove-PlatformInstanceFiles {

    #     Remove-Files "$($global:Location.Scripts)\config\config-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\definitions\definitions-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\initialize\initialize-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\preflight\preflight*-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\postflight\postflight*-platforminstance-$($global:Environ.Instance.ToLower()).ps1"

    # }

    # function script:Remove-PlatformFiles {

    #     Remove-Files "$($global:Location.Scripts)\config\config-platform-$($global:Environ.Platform.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\definitions\definitions-platform-$($global:Environ.Platform.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\initialize\initialize-platform-$($global:Environ.Platform.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\preflight\preflight*-platform-$($global:Environ.Platform.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\postflight\postflight*-platform-$($global:Environ.Platform.ToLower()).ps1"
    #     Remove-Files "$($global:Location.Scripts)\services\services-$($global:Environ.Platform.ToLower())*.ps1"

    # }

#endregion PLATFORM
#region PRODUCT

    function script:Disable-Product {

        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$true,Position=0)][string]$Context,
            [switch]$NoNewLine
        )

        if ($Context -match "\.") {
            if ($Context -imatch "Product\.") {
                $Context = $Context -ireplace "Product\.",""
            }
            else {
                throw "`"$Context`" is not a valid product id."
            }
        }

        $productToEnable = Get-Product $Context -ResetCache     
        $Name = $productToEnable.Name

        if (!$NoNewLine) {
            $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray
        }

        $platformTask = Disable-PlatformTask -Id $productToEnable.Id -OutputType PlatformTask 
        $productIsStopped = $platformTask.Status -in $global:PlatformTaskState.Stopped
        $productIsDisabled = $platformTask.Status -in $global:PlatformTaskState.Disabled
        $productStatus = $platformTask.Status

        $message = "$($emptyString.PadLeft(40,"`b"))$($productIsStopped ? "STOPPED" : "$($productStatus.ToUpper())")$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor ($productIsStopped ? "Red" : "DarkGreen"),DarkGray

        $message = "$($emptyString.PadLeft(20,"`b"))$($productStatus.ToUpper())$($emptyString.PadLeft(20-$productStatus.Length)," ")"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($productIsDisabled ? "Red" : "DarkGreen")

    }

    function script:Enable-Product {

        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$true,Position=0)][string]$Context,
            [switch]$NoNewLine
        )

        if ($Context -match "\.") {
            if ($Context -imatch "Product\.") {
                $Context = $Context -ireplace "Product\.",""
            }
            else {
                throw "`"$Context`" is not a valid product id."
            }
        }

        $productToEnable = Get-Product $Context -ResetCache     
        $Name = $productToEnable.Name

        if (!$NoNewLine) {
            $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))","INSTALLED$($emptyString.PadLeft(11," "))PENDING$($emptyString.PadLeft(13," "))"
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGreen
        }

        $platformTask = Enable-PlatformTask -Id $productToEnable.Id -OutputType PlatformTask
        $productIsEnabled = $platformTask.Status -in $global:PlatformTaskState.Enabled
        $productStatus = $platformTask.Status

        $message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor ($productIsEnabled ? "DarkGreen" : "Red"),DarkGray

        $message = "$($emptyString.PadLeft(20,"`b"))$($productStatus.ToUpper())$($emptyString.PadLeft(20-$productStatus.Length)," ")"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($productIsEnabled ? "DarkGreen" : "Red")

    }

#region CATALOG OBJECT

    function script:Install-CatalogObject {
        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$true,Position=0)][string]$Type,
            [Parameter(Mandatory=$true,Position=1)][string]$Id,
            [switch]$UseDefaultResponses,
            [switch]$NoNewLine
        )

        $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}
        $Id = $global:Catalog.$Type.$Id.Id
        $catalogObject = Get-Catalog -Type $Type -Id $Id

        $logFile = $catalogObject.Log ? $catalogObject.Log.ToLower() : $Platform.Instance
        if (!(Test-Log -Name $logFile)) { New-Log -Name $logFile | Out-Null }

        if (Test-Path -Path "$($global:Location.Scripts)\install\install-$($Type.ToLower())-$($Id.ToLower()).ps1") {. "$($global:Location.Scripts)\install\install-$($Type.ToLower())-$($Id.ToLower()).ps1" -UseDefaultResponses:$UseDefaultResponses.IsPresent -NoNewLine:$NoNewLine.IsPresent}

        # $global:Catalog.$Type.$Id.IsInstalled = $false
    }

function script:Uninstall-CatalogObject {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Type,
        [Parameter(Mandatory=$true,Position=1)][string]$Id,
        [switch]$Force,
        [switch]$DeleteAllData
    )

    $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}
    $Id = $global:Catalog.$Type.$Id.Id
    $catalogObject = Get-Catalog -Type $Type -Id $Id

    if (!$Force -and $catalogObject.Installation.Flag -eq "UninstallProtected") { return }

    if ($catalogObject.HasTask) {
        $message = "    $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    }
    else {
        $message = "    $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    }
    
    if (Test-Path -Path "$($global:Location.Scripts)\install\uninstall-$($Type.ToLower())-$($Id.ToLower()).ps1") {. "$($global:Location.Scripts)\install\uninstall-$($Type.ToLower())-$($Id.ToLower()).ps1"}

    if ($catalogObject.HasTask) {
            
        $platformTask = Get-PlatformTask -Id $Id

        $message = "$($emptyString.PadLeft(40,"`b"))STOPPING$($emptyString.PadLeft(12," "))PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkYellow

        $platformTask = Stop-PlatformTask -PlatformTask $platformTask -OutputType PlatformTask

        $message = "$($emptyString.PadLeft(40,"`b"))STOPPED$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red

        Unregister-PlatformTask -Id $Id | Out-Null

    }

    Remove-CatalogObjectFiles -Type $Type -Id $Id -DeleteAllData:$DeleteAllData.IsPresent
    Update-Environ -Type $Type -Name $Id -Source "$($global:Location.Scripts)\environ.ps1"

    $resetCacheResult = Invoke-Expression "Get-$($Type) $Id -ResetCache"
    $resetCacheResult | Out-Null

    $catalogObject.Refresh()

    $message = "$($emptyString.PadLeft(20,"`b"))UNINSTALLED$($emptyString.PadLeft(9," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

}

function script:Remove-CatalogObjectFiles {

    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Type,
        [Parameter(Mandatory=$true,Position=1)][string]$Id,
        [switch]$DeleteAllData
    )

    if ($DeleteAllData) {
        Remove-Files "$($global:Location.Data)\$($Id.ToLower())\*.*" -Recurse -Force
        Remove-Files "$($global:Location.Scripts)\definitions\definitions-$($Type.ToLower())-$($Id.ToLower()).ps1"
        Remove-Files "$($global:Location.Scripts)\install\data\$($Id.ToLower())InstallSettings.ps1"
    }

    Remove-Files "$($global:Location.Scripts)\config\config-$($Type.ToLower())-$($Id.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\initialize\initialize-$($Type.ToLower())-$($Id.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\install\install-$($Type.ToLower())-$($Id.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\preflight\preflight*-$($Type.ToLower())-$($Id.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\postflight\postflight*-$($Type.ToLower())-$($Id.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\services\services-$($Type.ToLower())-$($Id.ToLower()).ps1"

    if (![string]::IsNullOrEmpty($global:Catalog.$Type.$Id.Log)) {
        Remove-Files "$($global:Location.Logs)\$($global:Catalog.$Type.$Id.Log.ToLower()).log"
    }

    switch ($Type) {
        "Product" {
            Remove-Files "$($global:Location.Scripts)\$($Id.ToLower()).ps1"
        }
        "Provider" { 
            Remove-Files "$($global:Location.Scripts)\providers\provider-$($Id.ToLower()).ps1"
        }
    }
    

}

#endregion CATALOG OBJECT
#region POST-INSTALL

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
            Write-Host+ -SetIndentGlobal $_indent -SetTimeStampGlobal Include -SetTraceGlobal Include
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
                        $message = "$manualConfigObjectType > $manualConfigObjectId > $manualConfigAction > Edit $(Split-Path $manualConfigFile -Leaf)"
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

    }
    Set-Alias -Name postInstallConfig -Value Show-PostInstallation -Scope Global

#endregion POST-INSTALL
