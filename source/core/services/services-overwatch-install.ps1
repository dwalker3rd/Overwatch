#region LOCAL DEFINTIIONS

$script:ReviewRequiredRegionLabel = "REVIEW-REQUIRED"
$script:ReviewRequiredContent = 
@"
#region $ReviewRequiredRegionLabel

    # Manual Configuration > Definitions File > Template > Review
    # The template for this file has been updated. However, Overwatch was unable to apply those updates.  
    # Review the template and, where necessary, manually apply the updates from the template to this file.
    # TEMPLATE: <templateFilePath>

#endregion $ReviewRequiredRegionLabel

"@

#endregion LOCAL DEFINITIONS
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
                
                $templateFilePath = $null
                $pathFileTemplateUpdate = $false
                if ($pathFile.FullName.EndsWith("-template.ps1")) {
                    $templateFilePath = $pathFile
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
                    Write-Host+ -IfDebug -NoTrace -NoTimestamp "  DEBUG: The source and destination files are different, but the destination file is newer" -ForegroundColor DarkGray
                }

                if (![string]::IsNullOrEmpty($templateFilePath) -and ($pathHashIsDifferent -or $pathFileTemplateUpdate)) {
                    $noClobber = $true
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
                        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoNewLine "  [$_suiteOrComponent`:$_suiteOrName] $destinationFilePath" -ForegroundColor $($noClobber ? "DarkYellow" : "DarkGray")
                        Write-Host+ -Iff $(!$Quiet -and $noClobber) -NoTrace -NoTimestamp " -NOCLOBBER " -ForegroundColor DarkYellow
                        Write-Host+ -Iff $(!$Quiet -and !$noClobber)
                    }
                    else {
                        if (!$noClobber) {
                            Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp "  Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
                        }
                    }

                    if ($noClobber) {
                        $destinationFileContent = Get-Content -Path $destinationFilePath -Raw
                        $destinationFileContent = $destinationFileContent -replace "(?s)(#region $ReviewRequiredRegionLabel.*#endregion $ReviewRequiredRegionLabel)"
                        $destinationFileContent = $destinationFileContent -replace "(?s)^`r`n\s*"
                        $ReviewRequiredContent = $ReviewRequiredContent -replace "<templateFilePath>",$templateFilePath
                        Set-Content -Path $destinationFilePath -Value $ReviewRequiredContent -WhatIf:$false | Out-Null
                        Add-Content -Path $destinationFilePath -Value $destinationFileContent -WhatIf:$false | Out-Null
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

        if (Test-Path -Path $global:InstallSettings) { 

            $lockRetryDelay = New-Timespan -Seconds 1
            $lockRetryMaxAttempts = 5

            $lockRetryAttempts = 0
            $FileStream = $null
            while (!$FileStream.CanWrite -and $lockRetryAttempts -lt $lockRetryMaxAttempts) {
                try {
                    $lockRetryAttempts++
                    $FileStream = [System.IO.File]::Open($global:InstallSettings, 'OpenOrCreate', 'ReadWrite', 'Read')
                }
                catch {
                    Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
                }
            }
            if ($FileStream) {
                $FileStream.Close()
                $FileStream.Dispose()
            }
            else {
                $message = "The process cannot lock the file `'$($global:InstallSettings)`' because it is being used by another process."
                Write-Log -Action "Update-InstallSettings" -Target $global:InstallSettings -Status "Error" -Message $message -EntryType "Error"
                Write-Host+ -NoTimestamp $message -ForegroundColor Red
                $message = "Unable to save install settings to file `'$($global:InstallSettings)`'."
                Write-Host+ -NoTimeStamp $message -ForegroundColor Red
                return
            }
            
            Clear-Content -Path $global:InstallSettings
        
        }
                
        '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $global:InstallSettings
        "Param()" | Add-Content -Path $global:InstallSettings
        "`$overwatchInstallLocation = ""$($global:Location.Root)""" | Add-Content -Path $global:InstallSettings
        "`$operatingSystemId = ""$($global:Environ.OS)""" | Add-Content -Path $global:InstallSettings
        "`$cloudId = ""$($global:Environ.Cloud)""" | Add-Content -Path $global:InstallSettings
        "`$platformId = ""$($global:Environ.Platform)""" | Add-Content -Path $global:InstallSettings
        "`$platformInstanceId = ""$($global:Environ.Instance)""" | Add-Content -Path $global:InstallSettings
        "`$imagesUri = [System.Uri]::new(""$($global:Location.Images)"")" | Add-Content -Path $global:InstallSettings
        "`$platformInstallLocation = ""$($global:Platform.InstallPath)""" | Add-Content -Path $global:InstallSettings

        if ($platformId -notin $unInstallablePlatforms) {
            $_platformInstanceUri = [string]::IsNullOrEmpty($platformInstanceUri) ? [System.Uri]::new($($global:Platform.Uri)) : [System.Uri]::new($platformInstanceUri)
            "`$platformInstanceUri = ""$($_platformInstanceUri)""" | Add-Content -Path $global:InstallSettings
        }
        
        "`$platformInstanceDomain = ""$($global:Platform.Domain)""" | Add-Content -Path $global:InstallSettings
        if ($global:Environ.Product.Count -gt 0) {
            "`$productIds = @('$($global:Environ.Product -join "', '")')" | Add-Content -Path $global:InstallSettings
        }
        if ($global:Environ.Provider.Count -gt 0) {
            "`$providerIds = @('$($global:Environ.Provider -join "', '")')" | Add-Content -Path $global:InstallSettings
        }
        if ($global:PlatformTopologyBase.Nodes.Count -gt 0) {
            "`$platformInstanceNodes = @('$($global:PlatformTopologyBase.Nodes -join "', '")')" | Add-Content -Path $global:InstallSettings
        }
        if ($global:RequiredPythonPackages.Count -gt 0) {
            "`$requiredPythonPackages = @('$($global:RequiredPythonPackages -join "', '")')" | Add-Content -Path $global:InstallSettings
        }

        return

    }

#endregion SETTINGS
#region ENVIRON

    function script:Update-Environ {

        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory=$true)][string]$Source,
            [Parameter(Mandatory=$false)][string]$Destination = $Source,
            [Parameter(Mandatory=$false)][ValidateSet("Environ","Overwatch","Cloud","Provider","Product","Location")][string]$Type,
            [Parameter(Mandatory=$false)][string]$Name,
            [Parameter(Mandatory=$false)][AllowEmptyString()][string]$Expression = "`"`$(`$global:Location.Root)\$($Name.ToLower())`"",
            [Parameter(Mandatory=$false)][ValidateSet("Add","Replace","Remove")][string]$Mode = "Add"
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
            $locationPattern = $Name -eq "Root" ? "(?s)\`$global:Location\s*\=\s*@{\s*(.*?)\s*}" : "(?s)\`$global:Location\s*\+=\s*@{\s*(.*?)\s*}"
            if ($environFileContent -match $locationPattern) {
                $locationContent = $matches[1]
                if ($Mode -in ("Add","Replace") -and $locationContent -match "$Name\s*=\s*(?:@\(|`"|`')([^<>\(\)`"`']*)(?:\)|`"|`')") {
                    $expressionEvaluation = [string]::IsNullOrEmpty($Expression) ? "" : $matches[1]
                    Write-Host+ -NoTrace  "Item has already been added.","Key/Value in dictionary:","$Type.$($matches[0])","  Key/Value being added:","$Type.$Name = `"$expressionEvaluation`"" -ForegroundColor Red,DarkGray,Gray,DarkGray,Gray
                    return
                }
                elseif ($Mode -eq "Replace" -and $locationContent -match "$Name\s*=\s*(?:@\(|`"|`')(<.*>)(?:\)|`"|`')") {
                    $expressionEvaluation = [string]::IsNullOrEmpty($Expression) ? "" : $matches[1]
                    Write-Host+ -IfVerbose -NoTrace "Item replaced.","Key/Value","$Type.$($matches[0])"," replaced by ","$Type.$Name = `"$expressionEvaluation`"" -ForegroundColor DarkGreen,DarkGray,Gray,DarkGray,Gray
                    $environFileContent = $environFileContent.Replace($matches[1],$Expression)
                    $environFileContent | Set-Content -Path $Destination
                }
                elseif ($Mode -eq "Add") {
                    $expressionEvaluation = [string]::IsNullOrEmpty($Expression) ? "" : (Invoke-Expression $matches[1])
                    Write-Host+ -IfVerbose -NoTrace "Item added.","Key/Value","$Type.$Name = `"$expressionEvaluation`"" -ForegroundColor DarkGreen,DarkGray,Gray
                    $newLocationContent = $locationContent + "        " + $Name + " = " + $Expression + "`n"
                    $environFileContent = $environFileContent.Replace($locationContent, $newLocationContent)
                    $environFileContent | Set-Content -Path $Destination
                }
                else {
                    Write-Host+ -NoTrace "$Type update failed for an unknown reason" -ForegroundColor Red
                    Write-Host+ -NoTrace "Type = $Type; Name = $Name; Expression = $Expression; Mode = $Mode" -ForegroundColor DarkGray
                    return
                }                
            }
        }
        elseif ($Type -eq "Environ") {
            $environFileContent = Get-Content -Path $Source -Raw
            $environPattern = "(?s)\`$global:Environ\s*\=\s*@{\s*(.*?)\s*}"
            if ($environFileContent -match $environPattern) {
                $environContent = $matches[1]
                if ($Mode -in ("Add","Replace") -and $environContent -match "$Name\s*=\s*(?:@\(|`"|`')([^<>\(\)`"`']*)(?:\)|`"|`')") {
                    $expressionEvaluation = [string]::IsNullOrEmpty($Expression) ? "" : $matches[1]
                    Write-Host+ -NoTrace  "Item has already been added.","Key/Value in dictionary:","$Type.$($matches[0])","  Key/Value being added:","$Type.$Name = `"$expressionEvaluation`"" -ForegroundColor Red,DarkGray,Gray,DarkGray,Gray
                }
                elseif ($Mode -eq "Replace" -and $environContent -match "$Name\s*=\s*(?:@\(|`"|`')(<.*>)(?:\)|`"|`')") {
                    $expressionEvaluation = [string]::IsNullOrEmpty($Expression) ? "" : (Invoke-Expression $Expression)
                    Write-Host+ -IfVerbose -NoTrace "Item replaced.","Key/Value","$Type.$($matches[0])"," replaced by ","$Type.$Name = `"$expressionEvaluation`"" -ForegroundColor DarkGreen,DarkGray,Gray,DarkGray,Gray
                    $environFileContent = $environFileContent.Replace($matches[1],$Expression)
                    $environFileContent | Set-Content -Path $Destination
                }
                elseif ($Mode -eq "Add") {
                    $expressionEvaluation = [string]::IsNullOrEmpty($Expression) ? "" : $matches[1]
                    Write-Host+ -IfVerbose -NoTrace "Item added.","Key/Value","$Type.$Name = `"$expressionEvaluation`"" -ForegroundColor DarkGreen,DarkGray,Gray
                    $newEnvironContent = $environContent + "        " + $Name + " = " + $Expression + "`n"
                    $environFileContent = $environFileContent.Replace($environContent, $newEnvironContent)
                    $environFileContent | Set-Content -Path $Destination
                }                
                else {
                    Write-Host+ -NoTrace "$Type update failed for an unknown reason" -ForegroundColor Red
                    Write-Host+ -NoTrace "Type = $Type; Name = $Name; Expression = $Expression; Mode = $Mode" -ForegroundColor DarkGray
                    return
                }
            }
        }        
        else {
            # i don't remember why this section is here ... sigh
            # figure out what it does and document it!
            $environItems = Select-String $Destination -Pattern "$Type = " -Raw
            if (!$PSBoundParameters.ContainsKey('WhatIf')) {
                $updatedEnvironItems = $environItems.Replace("`"$Name`"","").Replace(", ,",",").Replace("(, ","(").Replace(", )",")")
                if ($updatedEnvironItems -match "=\s*$") { $updatedEnvironItems += "`"None`""}
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
        $Id = $productToEnable.Id

        if (!$NoNewLine) {
            $message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","INSTALLED$($emptyString.PadLeft(11," "))PENDING$($emptyString.PadLeft(13," "))"
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

        # TODO: automate registration of scheduled tasks from the catalog
        # this is currently handled in the install-product-*.ps1 files

        $customInstallScript = "$($global:Location.Scripts)\install\install-$($Type.ToLower())-$($Id.ToLower()).ps1"
        $hasCustomInstallScript = Test-Path -Path $customInstallScript

        $prerequisiteTestResults = Test-Prerequisites -Type $Type -Id $Id -PrerequisiteType Installation -Quiet
        if (!$prerequisiteTestResults.Pass) {
            foreach ($prerequisite in $prerequisiteTestResults.Prerequisites | Where-Object {!$_.Pass}) {
                # TODO: Prompt user for manual/automatic installation of prerequisites (including children) 
                Install-CatalogObject -Type $prerequisite.Type -Id $prerequisite.Id -UseDefaultResponses:$UseDefaultResponses
                Invoke-Command (Get-Catalog -Type $prerequisite.Type -Id $prerequisite.Id).Installation.Install
            }
        }

        if ($hasCustomInstallScript) {
            . $customInstallScript -UseDefaultResponses:$UseDefaultResponses.IsPresent
        }

    }

function script:Uninstall-CatalogObject {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Type,
        [Parameter(Mandatory=$true,Position=1)][string]$Id,
        [switch]$Force,
        [switch]$DeleteAllData,
        [switch]$Quiet
    )

    $Type = $global:Catalog.Keys | Where-Object {$_ -eq $Type}
    $Id = $global:Catalog.$Type.$Id.Id
    $catalogObject = Get-Catalog -Type $Type -Id $Id

    if (!$Force -and $catalogObject.Installation.Flag -eq "UninstallProtected") { return }

    $customUninstallScript = "$($global:Location.Scripts)\install\uninstall-$($Type.ToLower())-$($Id.ToLower()).ps1"
    $hasCustomUninstallScript = Test-Path -Path $customUninstallScript

    if ($catalogObject.HasTask) {
        $message = "    $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    }
    else {
        $message = "    $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))"
        Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    }
    
    if ($hasCustomUninstallScript) { 

        # execute the custom uninstall script
        $interaction = . $customUninstallScript 

        # rewrite headers if there was user interaction in the custom uninstall script
        if ($interaction) {
            if ($catalogObject.HasTask) {
                $message = "    $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
                Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
            }
            else {
                $message = "    $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))"
                Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
            }
        }

    }

    if ($catalogObject.HasTask) {
            
        $platformTask = Get-PlatformTask -Id $Id

        if ($platformTask) {

            $message = "$($emptyString.PadLeft(40,"`b"))STOPPING$($emptyString.PadLeft(12," "))PENDING$($emptyString.PadLeft(13," "))"
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message -ForegroundColor DarkYellow

            $platformTask = Stop-PlatformTask -PlatformTask $platformTask -OutputType PlatformTask

            $message = "$($emptyString.PadLeft(40,"`b"))STOPPED$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
            Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message -ForegroundColor Red

            Unregister-PlatformTask -Id $Id | Out-Null

        }

    }

    Remove-CatalogObjectFiles -Type $Type -Id $Id -DeleteAllData:$DeleteAllData.IsPresent
    Update-Environ -Type $Type -Name $Id -Source "$($global:Location.Scripts)\environ.ps1"
    Update-InstallSettings

    if ((Get-Command "Get-$($Type)").Parameters.Keys -contains "ResetCache") {
        $resetCacheResult = Invoke-Expression "Get-$($Type) $Id -ResetCache"
        $resetCacheResult | Out-Null
    }

    $catalogObject.Refresh()

    $message = "$($emptyString.PadLeft(20,"`b"))UNINSTALLED$($emptyString.PadLeft(9," "))"
    Write-Host+ -Iff $(!$Quiet) -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGreen

    # TODO: Prompt for manual/automatic uninstall of catalogobject dependencies which no longer have dependents

}

function script:Remove-CatalogObjectFiles {

    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Type,
        [Parameter(Mandatory=$true,Position=1)][string]$Id,
        [switch]$DeleteAllData
    )

    $typeArchiveFolder = ($Type -in @("Provider") ? "$($Type)s" : $Type).ToLower()
    $idArchiveFolder = $Id.ToLower()
    $archivePath = "$($global:Location.Archive)\$typeArchiveFolder\$idArchiveFolder"

    New-Item -ItemType Directory $archivePath -ErrorAction SilentlyContinue | Out-Null

    if ($DeleteAllData) {
        New-Item -ItemType Directory "$archivePath\data" -ErrorAction SilentlyContinue | Out-Null
        Move-Files -Path "$($global:Location.Data)\$($Id.ToLower())\*.*" -Destination "$archivePath\data" -Recurse -Overwrite
    }

    # copy to archive folder (don't delete in case the catalog object is reinstalled)
    Copy-Files -Path "$($global:Location.Scripts)\install\data\$($Id.ToLower())InstallSettings.ps1" -Destination $archivePath -Quiet
    # move the definitions file to the archive folder (for reference purposes)
    Move-Files -Path "$($global:Location.Scripts)\definitions\definitions-$($Type.ToLower())-$($Id.ToLower()).ps1" -Destination $archivePath -Quiet -Overwrite

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