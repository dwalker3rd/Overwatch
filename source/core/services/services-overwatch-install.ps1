function Copy-File {

    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [Parameter(Mandatory=$false)][string]$Component,
        [Parameter(Mandatory=$false)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Family,
        [switch]$Quiet,
        [switch]$ConfirmOverwrite,
        [switch]$ConfirmCopy,
        [switch]$QueueCopy
    )

    if ($ConfirmCopy -and $QueueCopy) {
        throw "ConfirmCopy and QueueCopy cannot be used together."
        return
    }
    # if ($PSBoundParameters.ContainsKey('WhatIf') -and !$Component) {
    #     throw "Component must be specified when using WhatIf"
    # }
    # if (!$PSBoundParameters.ContainsKey('WhatIf') -and $Component) {
    #     throw "Component can only be used with WhatIf"
    # }

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
                $families = @()

                if ($Component) {

                    $components += $Component
                    $names += ![string]::IsNullOrEmpty($Name) ? $Name : @()
                    $families += ![string]::IsNullOrEmpty($Family) ? $Family : @()

                }
                else {

                    # parse $pathFile for source subdirectories indicating component and name                
                    $pathKeys = @()
                    $pathKeys += ($pathFile | Split-Path -Parent).Replace("$($global:Location.Scripts)\source\","",1) -Split "\\"
                    $pathKeys += ($pathFile | Split-Path -LeafBase).Replace("-template","")

                    # if the subdirectory is "services", then search the catalog for the component and name/family
                    if (("services") -icontains $pathKeys[0]) {
                        foreach ($key in $global:Catalog.Keys) {
                            foreach ($subkey in $global:Catalog.$key.Keys) {
                                # if ($subkey -in $global:Environ.$key) {
                                    foreach ($service in $global:Catalog.$key.$subkey.Installation.Prerequisite.Service) {
                                        if ($service -eq $pathKeys[1]) {
                                            $components += $global:Catalog.Keys | Where-Object {$_ -eq $key}
                                            $names += $global:Catalog.$key.Keys | Where-Object {$_ -eq $subKey}
                                            if ($global:Catalog.$key.$subkey.Family) {
                                                $families += $global:Catalog.$key.$subkey.Family
                                            }
                                        }
                                    }
                                # }
                            }
                        }
                    }
                    # otherwise use the parsed $pathFile and capitalize the component and name
                    else {
                        $components = $pathKeys[0]
                        $names = $pathKeys[1] 
                        if ($pathKeys[2]) {
                            $names = 
                                switch ($pathKeys[2]) {
                                    "catalog" { "catalog" }
                                    "environ" { "environ" }
                                    default {$pathKeys[1]}
                                }
                        }
                        # $components += $global:Catalog.Keys | Where-Object {$_ -eq $key}
                        # $names += $global:Catalog.$key.Keys | Where-Object {$_ -eq $subKey}
                    }

                }

                # case and spelling corrections
                $components = 
                    foreach ($component in $components) {
                        switch ($component) { 
                            "Providers" { "Provider" } 
                            default {$_} 
                        }
                    }
                $names = ($global:Environ.OS | Where-Object {$_ -in $names}) ?? $names
                $names = ($global:Environ.Platform | Where-Object {$_ -in $names}) ?? $names
                $names = ($global:Environ.Product | Where-Object {$_ -in $names}) ?? $names
                $names = ($global:Environ.Provider | Where-Object {$_ -in $names}) ?? $names

                # if component/name/family are arrays, sort uniquely and comma-separate
                $Component = ($components | Sort-Object -Unique) -join ","
                $Name = ($names | Sort-Object -Unique) -join ","
                $Family = $families.Count -gt 0 ? ($families | Sort-Object -Unique) -join "," : $null

                $familyOrName = ![string]::IsNullOrEmpty($Family) ? $Family : $Name
                # Write-Host+ -NoTrace -NoTimestamp "[$Component`:$familyOrName] $pathFile" -ForegroundColor DarkGray

            #endregion DETERMINE COMPONENT AND NAME

            if (!(Test-Path -Path $destinationFilePath -PathType Leaf)) {
                if ($PSBoundParameters.ContainsKey('WhatIf')) {
                    $whatIfFiles += @{
                        Source = $pathFile
                        Destination = $destinationFilePath
                        Component = $Component
                        $Component = $Name
                        Family = $Family
                    }
                }
                else {
                    Copy-Item -Path $pathFile $destinationFilePath
                    $copiedFile = $true
                }
                if (!$Quiet) {
                    if ($PSBoundParameters.ContainsKey('WhatIf')) {
                        Write-Host+ -NoTrace -NoTimestamp "  [$Component`:$familyOrName] $pathFile" -ForegroundColor DarkGray
                    }
                    else {
                        Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "  Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
                    }
                }
            }
            else {

                # if hash is different, file contents are different. 
                # but this may be install parameters only, so compare LastWriteTime
                # update pathFile IFF the hash is different and the source file is newer
                $pathHashIsDifferent = (Get-FileHash $pathFile).hash -ne (Get-FileHash $destinationFilePath).hash
                $destinationFile = Get-ChildItem $destinationFilePath
                $pathFileIsNewer = $pathFile.LastWriteTime -gt $destinationFile.LastWriteTime
                $updatePathFile = $pathHashIsDifferent -and $pathFileIsNewer

                if (!$updatePathFile) {
                    # skip copy if the source file contents are identical to the target file contents
                    # or if the source file's LastWriteTime is older than the path file's LastWriteTime
                }
                else {
                    if ($PSBoundParameters.ContainsKey('WhatIf')) {
                        $whatIfFiles += @{
                            Source = $pathFile
                            Destination = $destinationFilePath
                            Component = $Component
                            $Component = $Name
                            Family = $Family
                        }
                    }
                    else {
                        Copy-Item -Path $pathFile $destinationFilePath
                        $copiedFile = $true
                    }
                    if (!$Quiet) {
                        if ($PSBoundParameters.ContainsKey('WhatIf')) {
                            Write-Host+ -NoTrace -NoTimestamp "  [$Component`:$familyOrName] $pathFile" -ForegroundColor DarkGray
                        }
                        else {
                            Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "  Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
                        }
                    }
                }

            }
        }

        return $PSBoundParameters.ContainsKey('WhatIf') ? $whatIfFiles : ($ConfirmCopy ? $copiedFile : $null)

    }
}

# install version
function Remove-File {
    [CmdletBinding(
        SupportsShouldProcess
    )]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [switch]$Quiet
    )
    if (Test-Path -Path $Path) {
        if($PSCmdlet.ShouldProcess($Path)) {
            Remove-Item -Path $Path
            if (!$Quiet) {Write-Host+ -NoTrace -NoTimestamp "Deleted $Path" -ForegroundColor Red}
        }
    }
}

function Install-Product {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context,
        [switch]$UseDefaultResponses,
        [switch]$NoNewLine
    )

    $productToInstall = (Get-Product $Context -ResetCache).Id ?? $Context

    $productLogFile = (Get-Catalog -Name $productToInstall -Type Product).Log ? ((Get-Catalog -Name $productToInstall -Type Product).Log).ToLower() : $Platform.Instance
    if (!(Test-Log -Name $productLogFile)) {
        New-Log -Name $productLogFile | Out-Null
    }

    if (Test-Path -Path "$($global:Location.Scripts)\install\install-product-$($productToInstall).ps1") {. "$($global:Location.Scripts)\install\install-product-$($productToInstall).ps1" -UseDefaultResponses:$UseDefaultResponses.IsPresent -NoNewLine:$NoNewLine.IsPresent}
}

function Disable-Product {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context,
        [switch]$NoNewLine
    )

    $productToStop = Get-Product $Context -ResetCache     
    $Name = $productToStop.Name 
    $Publisher = $productToStop.Publisher

    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

    $productIsStopped = Stop-PlatformTask -Id $productToStop.Id -Quiet
    $productIsDisabled = Disable-PlatformTask -Id $productToStop.Id -Quiet
    $productStatus = (Get-PlatformTask -Id $productToStop.Id).Status

    $message = "$($emptyString.PadLeft(27,"`b"))$($productIsStopped ? "STOPPED" : "$($productStatus.ToUpper())")$($emptyString.PadLeft($($productIsStopped ? 13 : 20-$productStatus.Length)," "))PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor ($productIsStopped ? "Red" : "DarkGreen"),DarkGray

    $message = "$($emptyString.PadLeft(7,"`b"))$($productStatus.ToUpper())"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor ($productIsDisabled ? "Red" : "DarkGreen")
}

function Enable-Product {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context,
        [switch]$NoNewLine
    )

    $productToStart = Get-Product $Context -ResetCache     
    $Name = $productToStart.Name 
    $Publisher = $productToStart.Publisher

    if (!$NoNewLine) {
        $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","INSTALLED$($emptyString.PadLeft(11," "))PENDING"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGreen
    }

    $productIsEnabled = Enable-PlatformTask -Id $productToStart.Id -Quiet
    $productStatus = (Get-PlatformTask -Id $productToStart.Id).Status

    $message = "$($emptyString.PadLeft(28,"`b"))INSTALLED$($emptyString.PadLeft(11," "))PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor ($productIsEnabled ? "DarkGreen" : "Red"),DarkGray

    $message = "$($emptyString.PadLeft(7,"`b"))$($productStatus.ToUpper())$($emptyString.PadLeft(20-$productStatus.Length)," ")"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor ($productIsEnabled ? "DarkGreen" : "Red")
}

function Install-Provider {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context,
        [switch]$UseDefaultResponses
    )

    $providerToInstall = (Get-Provider $Context -ResetCache).Id ?? $Context

    $providerLogFile = (Get-Catalog -Name $providerToInstall -Type Provider).Log ? ((Get-Catalog -Name $providerToInstall -Type Provider).Log).ToLower() : $Platform.Instance
    if (!(Test-Log -Name $providerLogFile)) {
        New-Log -Name $providerLogFile | Out-Null
    }

    if (Test-Path -Path "$($global:Location.Scripts)\install\install-provider-$($providerToInstall).ps1") {. "$($global:Location.Scripts)\install\install-provider-$($providerToInstall).ps1" -UseDefaultResponses:$UseDefaultResponses.IsPresent}
}

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
    if ((Get-PlatformTask).status -contains "Disabled") {
        Write-Host+ -NoTrace -NoTimeStamp "Product > All > Task > Enable disabled tasks"
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
                    $message = "$manualConfigObjectType > $manualConfigObjectId > $manualConfigAction > Edit $(Split-Path $manualConfigFile -Leaf)"
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor Gray,DarkGray,Gray
                }
            }
        }
        $postInstallConfig = $true
    }

    #region FILES NOT IN SOURCE

        $allowList = @()
        $allowListFile = "$($global:Location.Data)\fileAllowList.csv"
        if (Test-Path -Path $allowListFile) {
            $allowList += Import-csv -Path $allowListFile
        }
        $source = (Get-ChildItem -Path f:\overwatch\source -Recurse -File -Name | Split-Path -Leaf) -Replace "-template",""  | Sort-Object
        $prod = $(foreach ($dir in (Get-ChildItem -Path f:\overwatch -Directory -Exclude data,logs,temp,source,.*).FullName) {(Get-ChildItem -Path $dir -Name -File -Exclude LICENSE,README.md,install.ps1,.*) }) -Replace $global:Platform.Instance, $global:Platform.Id | Sort-Object
        $obsolete = foreach ($file in $prod) {if ($file -notin $source) {$file}}
        $obsolete = $(foreach ($dir in (Get-ChildItem -Path f:\overwatch -Directory -Exclude data,logs,temp,source).FullName) {(Get-ChildItem -Path $dir -Recurse -File -Exclude LICENSE,README.md,install.ps1,.*) | Where-Object {$_.name -in $obsolete}}).FullName
        $obsolete = $obsolete | Where-Object {$_ -notin $allowList.Path}

        if ($obsolete) {
            foreach ($file in $obsolete) {
                Write-Host+ -NoTrace -NoTimestamp "File > Obsolete/Extraneous > Remove/AllowList* $file" -ForegroundColor Gray
                # Write-Host+ -NoTrace -NoTimeStamp -NoNewLine "Add $file to allow list (Y/N)? " -ForegroundColor Gray
                # $response = Read-Host
                # if ($response -eq "Y") {
                #     $allowList += @{ Path = $file }
                #     $allowList | Export-Csv -Path $allowListFile -Append -UseQuotes Always -NoTypeInformation
                # }
                # else {
                #     Write-Host+ -NoTrace -NoTimeStamp -NoNewLine "Delete $file (Y/N)? " -ForegroundColor Gray
                #     $response = Read-Host 
                #     if ($response -eq "Y") {
                #         Write-Host+ -SetIndentGlobal -Indent 2
                #         Remove-File -Path $file
                #         Write-Host+ -SetIndentGlobal -Indent -2
                #     }
                # }
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

function Remove-ProviderFiles {

    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Provider
    )

    Remove-Files "$($global:Location.Scripts)\install\install-provider-$($Provider.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\definitions\definitions-provider-$($Provider.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\providers\provider-$($Provider.ToLower()).ps1"

}

function Remove-ProductFiles {

    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Product
    )

    Remove-Files "$($global:Location.Scripts)\config\config-product-$($Product.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\install\install-product-$($Product.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\definitions\definitions-product-$($Product.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\$($Product.ToLower()).ps1"

    $allProductSpecificServices = @()
    foreach ($key in $global:catalog.Product.Keys) {
        if ($global:Catalog.Product.$key.Installation.Prerequisite.Service) {
            if ((Get-Product $global:Catalog.Product.$key.Id).IsInstalled) {
                $allProductSpecificServices += $global:Catalog.Product.$key.Installation.Prerequisite.Service
            }
        }
    }
    # $allProductSpecificServices | Sort-Object -Unique 
    $productSpecificServices = @()
    foreach ($service in $global:catalog.Product.$Product.Installation.Prerequisite.Service) {
        if ($service -notin $allProductSpecificServices) {
            $productSpecificServices += $global:catalog.Product.$Product.Installation.Prerequisite.Service
        }
    }

    $definitionsServices = "$($global:Location.Definitions)\definitions-services.ps1"
    $definitionsServicesFile = Get-Content -Path $definitionsServices
    foreach ($productSpecificService in $productSpecificServices) {
        if (Test-Path "$($global:Location.Definitions)\definitions-service-$($productSpecificService.ToLower()).ps1") {
            Remove-Files "$($global:Location.Definitions)\definitions-service-$($productSpecificService.ToLower()).ps1"
            $contentLine = '. \$definitionsPath\\definitions-service-' + $productSpecificService.Service.ToLower() + '.ps1' # string must be in single quotes b/c of $ character
            foreach ($line in $definitionsServicesFile) {
                if ($line -match $contentLine) {
                    $definitionsServicesFile = $definitionsServicesFile | Where-Object {$_ -ne $line}
                }
            }
        }
        Remove-Files "$($global:Location.Scripts)\services\services-$($productSpecificService.ToLower()).ps1"
        $contentLine = '. \$servicesPath\\services-' + $productSpecificService.ToLower() + '.ps1'  # string must be in single quotes b/c of $ character
        foreach ($line in $definitionsServicesFile) {
            if ($line -match $contentLine) {
                $definitionsServicesFile = $definitionsServicesFile | Where-Object {$_ -ne $line}
            }
        }
        
    }
    $definitionsServicesFile | Set-Content -Path $definitionsServices

}

function Remove-PlatformInstanceFiles {

    Remove-Files "$($global:Location.Scripts)\config\config-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\definitions\definitions-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\initialize\initialize-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\preflight\preflight*-platforminstance-$($global:Environ.Instance.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\postflight\postflight*-platforminstance-$($global:Environ.Instance.ToLower()).ps1"

}

function Remove-PlatformFiles {

    Remove-Files "$($global:Location.Scripts)\config\config-platform-$($global:Environ.Platform.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\definitions\definitions-platform-$($global:Environ.Platform.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\initialize\initialize-platform-$($global:Environ.Platform.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\preflight\preflight*-platform-$($global:Environ.Platform.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\postflight\postflight*-platform-$($global:Environ.Platform.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\services\services-$($global:Environ.Platform.ToLower())*.ps1"

}

function Remove-OSFiles {

    Remove-Files "$($global:Location.Scripts)\config\config-os-$($global:Environ.OS.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\definitions\definitions-os-$($global:Environ.OS.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\initialize\initialize-os-$($global:Environ.OS.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\preflight\preflight*-os-$($global:Environ.OS.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\postflight\postflight*-os-$($global:Environ.OS.ToLower()).ps1"
    Remove-Files "$($global:Location.Scripts)\services\services-$($global:Environ.OS.ToLower())*.ps1"

}

function Remove-CoreFiles {

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

# uninstall version
# function Update-Environ {

#     param(
#         [Parameter(Mandatory=$false)][ValidateSet("Overwatch","Provider","Product")][Alias("Provider","Product")][string]$Type,
#         [Parameter(Mandatory=$false)][string]$Name
#     )

#     if ($Type -eq "Overwatch") {
#         Copy-File "$($global:Location.Scripts)\source\environ\environ-template.ps1" "$($global:Location.Scripts)\environ.ps1" -Component Environ -WhatIf -Quiet
#     }
    
#     $environItems = Select-String "$($global:Location.Scripts)\environ.ps1" -Pattern "$Type = " -Raw
#     $updatedEnvironItems = $environItems.Replace("`"$Name`"","").Replace(", ,",",").Replace("(, ","(").Replace(", )",")")
#     $content = Get-Content "$($global:Location.Scripts)\environ.ps1" 
#     $newContent = $content | Foreach-Object {$_.Replace($environItems,$updatedEnvironItems)}
#     Set-Content "$($global:Location.Scripts)\environ.ps1" -Value $newContent

# }

function Update-Environ {

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$false)][string]$Destination = $Source,
        [Parameter(Mandatory=$false)][ValidateSet("Overwatch","Provider","Product")][Alias("Provider","Product")][string]$Type,
        [Parameter(Mandatory=$false)][string]$Name
    )

    if ([string]::IsNullOrEmpty($Type)) {
        if (!$PSBoundParameters.ContainsKey('WhatIf')) {
            $environFileContent = Get-Content -Path $Source
            $environFileContent = $environFileContent -replace "<operatingSystemId>", ($operatingSystemId -replace " ","")
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

function Uninstall-Provider {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Provider,
        [switch]$Force
    )

    $providerToUninstall = Get-Provider $Provider
    if (!$Force -and $providerToUninstall.Installation.Flag -eq "UninstallProtected") { return }

    $Name = $providerToUninstall.Name ?? $Provider
    $Publisher = $providerToUninstall.Publisher ?? $global:Catalog.Provider.$Provider.Publisher

    $message = "    $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray
    
    if (Test-Path -Path "$($global:Location.Scripts)\install\uninstall-provider-$($providerToUninstall.Id).ps1") {. "$($global:Location.Scripts)\install\uninstall-provider-$($providerToUninstall.Id).ps1"}

    Remove-ProviderFiles $Provider
    Update-Environ -Type Provider -Name $Provider -Source $global:DestinationEnvironFile
    Get-Provider -ResetCache | Out-Null
    
    $message = "$($emptyString.PadLeft(7,"`b"))UNINSTALLED"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

}

function Uninstall-Product {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Product,
        [switch]$Force
    )

    $productToUninstall = Get-Product $Product
    if (!$Force -and $productToUninstall.Installation.Flag -eq "UninstallProtected") { return }
    
    $Name = $productToUninstall.Name ?? $Product
    $Publisher = $productToUninstall.Publisher ?? $global:Catalog.Product.$Product.Publisher

    $message = "    $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

    if (Test-Path -Path "$($global:Location.Scripts)\install\uninstall-product-$($productToUninstall.Id).ps1") {. "$($global:Location.Scripts)\install\uninstall-product-$($productToUninstall.Id).ps1"}

    if ($productToUninstall.HasTask -and $(Get-PlatformTask -Id $Product)) {
        
        $message = "$($emptyString.PadLeft(40,"`b"))STOPPING$($emptyString.PadLeft(12," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor DarkYellow

        $isStopped = Stop-PlatformTask -Id $Product -Quiet
        $isStopped | Out-Null

        $message = "$($emptyString.PadLeft(20,"`b"))STOPPED$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red

        Unregister-PlatformTask -Id $Product

    }
    else {
        $message = "$($emptyString.PadLeft(40,"`b"))STOPPED$($emptyString.PadLeft(13," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red
    }

    $message = "$($emptyString.PadLeft(20,"`b"))DELETED$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine $message -ForegroundColor Red
        
    Remove-ProductFiles $Product
    Update-Environ -Type Product -Name $Product -Source $global:DestinationEnvironFile
    Get-Product -ResetCache | Out-Null

    if ($productToUninstall.HasTask) {
        $message = "UNINSTALLED$($emptyString.PadLeft(9," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }
    else {
        $message = "$($emptyString.PadLeft(20,"`b"))N/A$($emptyString.PadLeft(17," "))","UNINSTALLED"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGray, DarkGreen
    }

}

function Uninstall-Platform {

    [CmdletBinding()]
    Param (
        [switch]$Force
    )

    Remove-PlatformInstanceFiles
    Remove-PlatformFiles
    Remove-Files "$($global:Location.Data)\*.cache"

}

function Uninstall-OS { 

    [CmdletBinding()]
    Param (
        [switch]$Force
    )

    Remove-OSFiles 

}

function Uninstall-Overwatch { 
    
    [CmdletBinding()]
    Param (
        [switch]$Force
    )
    
    Remove-CoreFiles 
    Update-Environ -Type Overwatch -Source $global:DestinationEnvironFile

}

function Set-InstallSettings {

    [CmdletBinding()]
    Param ()

    if (Test-Path -Path $installSettingsFile) { Clear-Content -Path $installSettingsFile }
            
    '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $installSettingsFile
    "Param()" | Add-Content -Path $installSettingsFile
    if (![string]::IsNullOrEmpty($operatingSystemId)) {
        "`$operatingSystemId = ""$operatingSystemId""" | Add-Content -Path $installSettingsFile
    }
    if (![string]::IsNullOrEmpty($platformId)) {
        "`$platformId = ""$platformId""" | Add-Content -Path $installSettingsFile
    }
    if (![string]::IsNullOrEmpty($platformInstallLocation)) {
        "`$platformInstallLocation = ""$platformInstallLocation""" | Add-Content -Path $installSettingsFile
    }
    if (![string]::IsNullOrEmpty($platformInstanceId)) {
        "`$platformInstanceId = ""$platformInstanceId""" | Add-Content -Path $installSettingsFile
    }
    if ($global:Environ.Product.Count -gt 0) {
        "`$productIds = @('$($global:Environ.Product -join "', '")')" | Add-Content -Path $installSettingsFile
    }
    if ($global:Environ.Provider.Count -gt 0) {
        "`$providerIds = @('$($global:Environ.Provider -join "', '")')" | Add-Content -Path $installSettingsFile
    }
    if (![string]::IsNullOrEmpty($imagesUri)) {
        "`$imagesUri = [System.Uri]::new(""$imagesUri"")" | Add-Content -Path $installSettingsFile
    }
    if (![string]::IsNullOrEmpty($platformInstanceUri)) {
        "`$platformInstanceUri = [System.Uri]::new(""$platformInstanceUri"")" | Add-Content -Path $installSettingsFile
    }
    if (![string]::IsNullOrEmpty($platformInstanceDomain)) {
        "`$platformInstanceDomain = ""$platformInstanceDomain""" | Add-Content -Path $installSettingsFile
    }
    if ($platformInstanceNodes.Count -gt 0) {
        "`$platformInstanceNodes = @('$($platformInstanceNodes -join "', '")')" | Add-Content -Path $installSettingsFile
    }
    if ($requiredPythonPackages.Count -gt 0) {
        "`$requiredPythonPackages = @('$($requiredPythonPackages -join "', '")')" | Add-Content -Path $installSettingsFile
    }

}