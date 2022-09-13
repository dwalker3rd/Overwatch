#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param (
    [switch]$SkipProductStart,
    [switch]$UseDefaultResponses,
    [switch][Alias("PostInstallConfig")]$PostInstallationConfiguration
)

$global:WriteHostPlusPreference = "Continue"

$emptyString = ""

. $PSScriptRoot\source\core\definitions\classes.ps1
. $PSScriptRoot\source\core\definitions\catalog.ps1
. $PSScriptRoot\source\core\services\services-overwatch-loadearly.ps1

Write-Host+ -ResetAll

function Copy-File {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [switch]$Quiet,
        [switch]$ConfirmOverwrite,
        [switch]$ConfirmCopy
    )

    if (Test-Path -Path $Path) {

        $pathFiles = Get-ChildItem $Path
        $destinationIsDirectory = !(Split-Path $Destination -Extension)

        $copiedFile = $false
        foreach ($pathFile in $pathFiles) {
            $destinationFilePath = $destinationIsDirectory ? "$Destination\$(Split-Path $pathFile -Leaf -Resolve)" : $Destination
            if (!(Test-Path -Path $destinationFilePath -PathType Leaf)) {
                Copy-Item -Path $pathFile $destinationFilePath
                if (!$Quiet) {
                    Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
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
                    Copy-Item -Path $pathFile $destinationFilePath
                    if (!$Quiet) {
                        Split-Path -Path $pathFile -Leaf -Resolve | Foreach-Object {Write-Host+ -NoTrace -NoTimestamp "Copied $_ to $destinationFilePath" -ForegroundColor DarkGray}
                    }
                    $copiedFile = $true
                }

            }
        }

        # return bool indicating that one or more of the source files were copies to the destination
        return $ConfirmCopy ? $copiedFile : $null

    }
}

function Remove-File {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [switch]$Quiet
    )
    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path
        if (!$Quiet) {Write-Host+ -NoTrace -NoTimestamp "Deleted $Path" -ForegroundColor Red}
    }
}

function Install-Product {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)][string]$Context,
        [switch]$NoNewLine
    )

    $productToInstall = Get-Product $Context -ResetCache

    $productLogFile = ((Get-Catalog $productToInstall.Id -Type "Product").Log).ToLower()
    if (!(Test-Log -Name $productLogFile)) {
        New-Log -Name $productLogFile | Out-Null
    }

    if (Test-Path -Path $PSScriptRoot\install\install-product-$($productToInstall.Id).ps1) {. $PSScriptRoot\install\install-product-$($productToInstall.Id).ps1 -UseDefaultResponses:$UseDefaultResponses.IsPresent -NoNewLine:$NoNewLine.IsPresent}
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
        [Parameter(Mandatory=$true,Position=0)][string]$ProviderName
    )

    $providerToInstall = Get-Provider $ProviderName -ResetCache

    $providerLogFile = ((Get-Catalog $providerToInstall.Id -Type "Provider").Log).ToLower()
    if (!(Test-Log -Name $providerLogFile)) {
        New-Log -Name $providerLogFile | Out-Null
    }

    if (Test-Path -Path $PSScriptRoot\install\install-provider-$($providerToInstall.Id).ps1) {. $PSScriptRoot\install\install-provider-$($providerToInstall.Id).ps1 -UseDefaultResponses:$UseDefaultResponses.IsPresent}
}

function Update-Environ {

    param(
        [Parameter(Mandatory=$false)][ValidateSet("Provider","Product")][Alias("Provider","Product")][string]$Type,
        [Parameter(Mandatory=$false)][string]$Name
    )
    
    $environItems = Select-String $PSScriptRoot\environ.ps1 -Pattern "$Type = " -Raw
    if (!($environItems | Select-String -Pattern $Name -Quiet)) {
        $updatedEnvironItems = $environItems.Replace(")",", `"$Name`")")
        $content = Get-Content $PSScriptRoot\environ.ps1 
        $newContent = $content | Foreach-Object {$_.Replace($environItems,$updatedEnvironItems)}
        Set-Content $PSScriptRoot\environ.ps1 -Value $newContent
    }

}

function global:Show-PostInstallationConfiguration {

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

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Post-Installation Configuration" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "-------------------------------" -ForegroundColor DarkGray

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

    if (!$postInstallConfig) {
        Write-Host+ -NoTrace -NoTimeStamp "No post-installation configuration required."
    }
    
    Write-Host+

}
Set-Alias -Name postInstallConfig -Value Show-PostInstallationConfiguration -Scope Global

if ($PostInstallationConfiguration -and $PSBoundParameters.Keys.Count -gt 1) {
    throw "The PostInstallationConfiguration switch cannot be used with other switches."
}

if ($PostInstallationConfiguration) {
    Show-PostInstallationConfiguration
    return
}

pspref -Quiet
Clear-Host

#region DISCOVERY

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Discovery" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "---------" -ForegroundColor DarkGray

    $overwatchInstallLocation = $PSScriptRoot

    $installedProducts = @()
    $installedProviders = @()
    $installOverwatch = $true
    try {

        $message = "<Control <.>24> SEARCHING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        try{
            psPref -xpref -xpostf -xwhp -Quiet
            $global:Product = @{Id="Command"}
            . $PSScriptRoot\definitions.ps1
        }
        catch {}
        finally {
            psPref -Quiet
        }

        $message = "$($emptyString.PadLeft(9,"`b"))$($Overwatch.DisplayName) "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Blue

        $installedProducts = Get-Product -ResetCache
        $installedProviders = Get-Provider -ResetCache
        $installOverwatch = $false
        # $updateOverwatch = $true
    }
    catch {
        $message = "$($emptyString.PadLeft(9,"`b"))None"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
    }

    if ($installOverwatch) {
        Write-Host+ -NoTrace -NoTimestamp -Parse "<Mode <.>24> Install" -ForegroundColor Gray,DarkGray,Blue
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp -Parse  "<Mode <.>24> Update" -ForegroundColor Gray,DarkGray,Blue
    }

    $installedOperatingSystem = $((Get-CimInstance -ClassName Win32_OperatingSystem).Name -split "\|")[0]
    if ($installedOperatingSystem -like "*Windows Server*") {
        $installedOperatingSystem = "WindowsServer"
    }
    else {
        throw "$installedOperatingSystem is not an Overwatch-supported operating system."
    }
    Write-Host+ -NoTrace -NoTimestamp -Parse "<Operating System <.>24> $installedOperatingSystem" -ForegroundColor Gray,DarkGray,Blue
    $operatingSystemId = $installedOperatingSystem

    $installedPlatforms = @()
    $services = Get-Service
    foreach ($key in $global:Catalog.Platform.Keys) { 
        if ($services.Name -contains $global:Catalog.Platform.$key.Installation.Discovery.Service) {
            $installedPlatforms += $key
        }
    }
    # if ($services.Name -contains "tabsvc_0") {$installedPlatforms += "TableauServer"}
    # if ($services.Name -contains "AlteryxService") {$installedPlatforms += "AlteryxServer"}
    Write-Host+ -NoTrace -NoTimestamp -Parse "<Platform <.>24> $($installedPlatforms -join ", ")" -ForegroundColor Gray,DarkGray,Blue

#endregion DISCOVERY
#region LOAD SETTINGS

    Write-Host+ -MaxBlankLines 1
    $settingsFileMissing = $false

    $defaultSettings = "$PSScriptRoot\install\data\defaultSettings.ps1"
    if (Test-Path -Path $defaultSettings) {
        . $defaultSettings
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp "No default settings in $defaultSettings" -ForegroundColor DarkGray
        $settingsFileMissing = $true
    }

    $installSettings = "$PSScriptRoot\install\data\installSettings.ps1"
    if (Test-Path -Path $installSettings) {
        . $installSettings
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        $settingsFileMissing = $true
    }    

    if ($settingsFileMissing) {Write-Host+}

#endregion LOAD SETTINGS

Write-Host+ -MaxBlankLines 1
Write-Host+ -NoTrace -NoTimestamp "Installation Questions" -ForegroundColor DarkGray
Write-Host+ -NoTrace -NoTimestamp "----------------------" -ForegroundColor DarkGray

#region PLATFORM ID

    # if ($installedPlatforms.count -eq 1) {
        $platformId = $installedPlatforms[0]
    # }
    # else {
        do {
            $platformIdResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Select Platform ", "$($installedPlatforms ? "[$($installedPlatforms -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray 
            if (!$UseDefaultResponses) {
                $platformIdResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $platformId = ![string]::IsNullOrEmpty($platformIdResponse) ? $platformIdResponse : $platformId
            Write-Host+ -NoTrace -NoTimestamp "Platform ID: $platformId" -IfDebug -ForegroundColor Yellow
            if ($installedPlatforms -notcontains $platformId) {
                Write-Host+ -NoTrace -NoTimestamp "Platform must be one of the following: $($installedPlatforms -join ", ")" -ForegroundColor Red
            }
        } until ($installedPlatforms -contains $platformId)
    # }

#endregion PLATFORM ID
#region PLATFORM INSTALL LOCATION

    do {
        $platformInstallLocationResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Install Location ", "$($platformInstallLocation ? "[$platformInstallLocation]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstallLocationResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformInstallLocation = ![string]::IsNullOrEmpty($platformInstallLocationResponse) ? $platformInstallLocationResponse : $platformInstallLocation
        Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow
        if (!(Test-Path -Path $platformInstallLocation)) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find path '$platformInstallLocation' because it does not exist." -ForegroundColor Red
            $platformInstallLocation = $null
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The path '$platformInstallLocation' is valid." -IfVerbose -ForegroundColor DarkGreen
        }
    } until ($platformInstallLocation)
    Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTALL LOCATION
#region PLATFORM INSTANCE URL

do {
    try {
        $platformInstanceUriResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance URI ", "$($platformInstanceUri ? "[$platformInstanceUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstanceUriResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformInstanceUri = ![string]::IsNullOrEmpty($platformInstanceUriResponse) ? $platformInstanceUriResponse : $platformInstanceUri
        $platformInstanceUri = [System.Uri]::new($platformInstanceUri)
    }
    catch {
        Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid URI format" -ForegroundColor Red
        $platformInstanceUri = $null
    }
    if ($platformInstanceUri) {
        try {
            Invoke-WebRequest $platformInstanceUri -Method Head | Out-Null
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] Response from '$platformInstanceUri'" -IfVerbose -ForegroundColor DarkGreen
        }
        catch
        {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] No response from '$platformInstanceUri'" -ForegroundColor Red
            $platformInstanceUri = $null
        }
    }
} until ($platformInstanceUri)
Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceUri" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE URL
#region PLATFORM INSTANCE DOMAIN

    $platformInstanceDomain ??= $platformInstanceUri.Host.Split(".",2)[1]
    do {
        $platformInstanceDomainResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Domain ", "$($platformInstanceDomain ? "[$platformInstanceDomain]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstanceDomainResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformInstanceDomain = ![string]::IsNullOrEmpty($platformInstanceDomainResponse) ? $platformInstanceDomainResponse : $platformInstanceDomain
        if (![string]::IsNullOrEmpty($platformInstanceDomain) -and $platformInstanceUri.Host -notlike "*$platformInstanceDomain") {
            Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid domain. Domain must match the platform instance URI" -ForegroundColor Red
            $platformInstanceDomain = $null
        }
    } until ($platformInstanceDomain)
    Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceDomain" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE DOMAIN
#region PLATFORM INSTANCE ID

    $platformInstanceId ??= $platformInstanceUri.Host -replace "\.","-"
    do {
        $platformInstanceIdResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance ID ", "$($platformInstanceId ? "[$platformInstanceId]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $platformInstanceIdResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformInstanceId = ![string]::IsNullOrEmpty($platformInstanceIdResponse) ? $platformInstanceIdResponse : $platformInstanceId
        if ([string]::IsNullOrEmpty($platformInstanceId)) {
            Write-Host+ -NoTrace -NoTimestamp "NULL: Platform Instance ID is required" -ForegroundColor Red
            $platformInstanceId = $null
        }
        if ($platformInstanceId -notmatch "^[a-zA-Z0-9\-]*$") {
            Write-Host+ -NoTrace -NoTimestamp "INVALID CHARACTER: letters, digits and hypen only" -ForegroundColor Red
            $platformInstanceId = $null
        }
    } until ($platformInstanceId)
    Write-Host+ -NoTrace -NoTimestamp "Platform Instance ID: $platformInstanceId" -IfDebug -ForegroundColor Yellow

#endregion PLATFORM INSTANCE ID
#region PLATFORM INSTANCE NODES

    if ($platformId -eq "AlteryxServer") {
        do {
            $platformInstanceNodesResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Nodes ", "$($platformInstanceNodes ? "[$($platformInstanceNodes -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $platformInstanceNodesResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $platformInstanceNodes = ![string]::IsNullOrEmpty($platformInstanceNodesResponse) ? $platformInstanceNodesResponse : $platformInstanceNodes
            if ([string]::IsNullOrEmpty($platformInstanceNodes)) {
                Write-Host+ -NoTrace -NoTimestamp "NULL: Platform Instance Nodes is required" -ForegroundColor Red
                $platformInstanceNodes = $null
            }
        } until ($platformInstanceNodes)
        $platformInstanceNodes = $platformInstanceNodes -split "," | ForEach-Object { $_.Trim(" ") }
        Write-Host+ -NoTrace -NoTimestamp "Platform Instance Nodes: $platformInstanceNodes" -IfDebug -ForegroundColor Yellow
    }

#endregion PLATFORM INSTANCE NODES 
#region PYTHON

    $pythonEnvLocation = $null
    $pythonPipLocation = $null
    $pythonSitePackagesLocation = $null
    switch ($platformId) {
        "AlteryxServer" {
            $pythonEnvLocation = "$platformInstallLocation\bin\Miniconda3\envs\DesignerBaseTools_vEnv"
            $pythonPipLocation = "$pythonEnvLocation\Scripts"
            $pythonSitePackagesLocation = "$pythonEnvLocation\Lib\site-packages"

            $requiredPythonPackagesResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Required Python Packages ", "$($requiredPythonPackages ? "[$($requiredPythonPackages -join ", ")]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $requiredPythonPackagesResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $requiredPythonPackages = ![string]::IsNullOrEmpty($requiredPythonPackagesResponse) ? $requiredPythonPackagesResponse : $requiredPythonPackages
            $requiredPythonPackages = $requiredPythonPackages -split "," | ForEach-Object { $_.Trim(" ") }
            Write-Host+ -NoTrace -NoTimestamp "Required Python Packages: $requiredPythonPackages" -IfDebug -ForegroundColor Yellow
        }
        default {$null}
    }

#region PYTHON
#region IMAGES

    do {
        try {
            $imagesUriResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Images URL ", "$($imagesUri ? "[$imagesUri]" : $null)", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $imagesUriResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $imagesUri = ![string]::IsNullOrEmpty($imagesUriResponse) ? $imagesUriResponse : $imagesUri
            $imagesUri = [System.Uri]::new($imagesUri)
        }
        catch {
            Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid URI format" -ForegroundColor Red
            $imagesUri = $null
        }
        if ($imagesUri) {
            try {
                $imagesUriNoEndingSlash = $imagesUri.AbsoluteUri.Substring($imagesUri.AbsoluteUri.Length-1,1) -eq "/" ? $imagesUri.AbsoluteUri.Substring(0,$imagesUri.AbsoluteUri.Length-1) : $imagesUri
                $imgFile = "$imagesUriNoEndingSlash/windows_server.png"
                Invoke-WebRequest "$imgFile" -Method Head | Out-Null
                Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] Overwatch image files found at '$imgFile'" -IfVerbose -ForegroundColor DarkGreen
            }
            catch
            {
                Write-Host+ -NoTrace -NoTimestamp "[ERROR] Overwatch image files not found at '$imgFile'" -ForegroundColor Red
                $imagesUri = $null
            }
        }
    } until ($imagesUri)
    Write-Host+ -NoTrace -NoTimestamp "Public URI for images: $imagesUri" -IfDebug -ForegroundColor Yellow

#endregion IMAGES
#region LOCAL DIRECTORIES

    $requiredDirectories = @("config","data","definitions","docs","docs\img","img","initialize","install","logs","preflight","postflight","providers","services","temp","data\$platformInstanceId","install\data")

    $missingDirectories = @()
    foreach ($requiredDirectory in $requiredDirectories) {
        if (!(Test-Path "$PSScriptRoot\$requiredDirectory")) { $missingDirectories += "$PSScriptRoot\$requiredDirectory" }
    }
    if ($missingDirectories) {

        Write-Host+
        Write-Host+ -NoTrace -NoTimestamp "Local Directories" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "-----------------" -ForegroundColor DarkGray

        foreach ($missingDirectory in $missingDirectories) {
            New-Item -ItemType Directory -Path $missingDirectory -Force
        }

    }

#endregion LOCAL DIRECTORIES
#region PRODUCTS
    
    $productsSelected = @()
    $productSpecificServices = @()
    $productDependencies = @()
    $productHeaderWritten = $false
    foreach ($key in $global:Catalog.Product.Keys) {

        $product = $global:Catalog.Product.$key
        
        if ([string]::IsNullOrEmpty($product.Installation.Prerequisite.Platform) -or $product.Installation.Prerequisite.Platform -contains $platformId) {

            if ($product.Id -notin $installedProducts.Id) {

                $productResponse = $null

                if ($product.Installation.Flag -contains "AlwaysInstall") {
                    $productsSelected += $product.id
                    $productResponse = "Y"
                }
                elseif ($product.Installation.Flag -notcontains "NoPrompt") {
                    if (!$productHeaderWritten) {
                        Write-Host+
                        Write-Host+ -NoTrace -NoTimestamp "Select Products" -ForegroundColor DarkGray
                        Write-Host+ -NoTrace -NoTimestamp "---------------" -ForegroundColor DarkGray
                        $productHeaderWritten = $true
                    }
                    $productResponseDefault = $product.id -in $productIds ? "Y" : "N"
                    $productResponse = $null
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $($product.id) ","[$productResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
                    if (!$UseDefaultResponses) {
                        $productResponse = Read-Host
                    }
                    else {
                        Write-Host+
                    }
                    if ([string]::IsNullOrEmpty($productResponse)) {$productResponse = $productResponseDefault}
                    if ($productResponse -eq "Y") {
                        $productsSelected += $product.id
                    }
                }

                if ($productResponse -eq "Y") {
                    if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Product)) {
                        foreach ($prerequisiteProduct in $product.Installation.Prerequisite.Product) {
                            if ($prerequisiteProduct -notin $installedProducts.Id) {
                                if ($prerequisiteProduct -notin $productsSelected) {
                                    $productsSelected += $prerequisiteProduct
                                    $productDependencies += @{
                                        Product = $product.id
                                        Dependency = $prerequisiteProduct
                                    }
                                    if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Service)) {
                                        foreach ($prerequisiteService in $product.Installation.Prerequisite.Service) {
                                            # if ($prerequisiteService -notin $productSpecificServices) {
                                                $productSpecificServices += @{
                                                    Product = $prerequisiteProduct
                                                    Service = $prerequisiteService
                                                }
                                            # }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            else {
                # code repeat necessary to catch product service prerequisites when using -Update switch
                if (![string]::IsNullOrEmpty($product.Installation.Prerequisite.Service)) {
                    foreach ($prerequisiteService in $product.Installation.Prerequisite.Service) {
                        # if ($prerequisiteService -notin $productSpecificServices) {
                            $productSpecificServices += @{
                                Product = $product.Name
                                Service = $prerequisiteService
                            }
                        # }
                    }
                }
            }

        }

    }
    $productIds = $productsSelected

    Write-Host+ -Iff $productHeaderWritten

    if ($productDependencies) {
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "Other Products" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "--------------" -ForegroundColor DarkGray
        foreach ($productDependency in $productDependencies) {
            Write-Host+ -NoTrace -NoTimestamp $($productDependency.Dependency),"(required by $($productDependency.Product))" -ForegroundColor Gray,DarkGray
        }
        Write-Host+
    }

#endregion PRODUCTS
#region PROVIDERS

    $providerHeaderWritten = $false
    $_providerIds = @()
    foreach ($key in $global:Catalog.Provider.Keys) {
        $provider = $global:Catalog.Provider.$key
        if ([string]::IsNullOrEmpty($provider.Installation.Prerequisite.Platform) -or $provider.Installation.Prerequisite.Platform -contains $platformId) {
            if ($provider.Id -notin $installedProviders.Id) {
                if ($provider.Installation.Flag -contains "AlwaysInstall") {
                    $_providerIds += $provider.Id
                }
                elseif ($provider.Installation.Flag -notcontains "NoPrompt") {
                    if (!$providerHeaderWritten) {
                        Write-Host+ -MaxBlankLines 1
                        Write-Host+ -NoTrace -NoTimestamp "Select Providers" -ForegroundColor DarkGray
                        Write-Host+ -NoTrace -NoTimestamp "----------------" -ForegroundColor DarkGray
                        $providerHeaderWritten = $true
                    }
                    $providerResponseDefault = $provider.ID -in $providerIds ? "Y" : "N"
                    $providerResponse = $null
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $($provider.Id) ","[$providerResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
                    if (!$UseDefaultResponses) {
                        $providerResponse = Read-Host
                    }
                    else {
                        Write-Host+
                    }
                    if ([string]::IsNullOrEmpty($providerResponse)) {$providerResponse = $providerResponseDefault}
                    if ($providerResponse -eq "Y") {
                        $_providerIds += $provider.Id
                    }
                }
            }
        }
    }
    $providerIds = $_providerIds

    Write-Host+ -Iff $providerHeaderWritten

#endregion PROVIDERS
#region FILES

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace -NoTimestamp "Configuration Files" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "-------------------" -ForegroundColor DarkGray

    #region CORE

        $coreFileUpdated = $false
        $files = (Get-ChildItem $PSScriptRoot\source\core -File -Recurse).VersionInfo.FileName
        foreach ($file in $files) { 
            $coreFileUpdated = $coreFileUpdated -or (Copy-File $file $file.replace("\source\core","") -ConfirmCopy)
        }

    #endregion CORE
    #region ENVIRON

        $environFileUpdated = $false
        $sourceFile = "$PSScriptRoot\source\environ\environ-template.ps1"
        $targetFile = "$PSScriptRoot\environ.ps1"
        $targetFileExists = Test-Path $targetFile
        if ($installOverwatch) {
            $environFile = Get-Content -Path $sourceFile
            $environFile = $environFile -replace "<operatingSystemId>", ($operatingSystemId -replace " ","")
            $environFile = $environFile -replace "<platformId>", ($platformId -replace " ","")
            $environFile = $environFile -replace "<overwatchInstallLocation>", $overwatchInstallLocation
            $environFile = $environFile -replace "<platformInstanceId>", $platformInstanceId
            $environFile = ($environFile -replace "<productIds>", "'$($productIds -join "', '")'") -replace "'",'"'
            $environFile = ($environFile -replace "<providerIds>", "'$($providerIds -join "', '")'") -replace "'",'"'
            $environFile = $environFile -replace "<imagesUri>", $imagesUri
            $environFile | Set-Content -Path $targetFile
            Write-Host+ -NoTrace -NoTimestamp "$($targetFileExists ? "Updated" : "Created") $targetFile" -ForegroundColor DarkGreen
            $environFileUpdated = $true
        }
        else {
            foreach ($productId in $productIds) {
                Update-Environ -Type Product -Name $productId
                $environFileUpdated = $true
            }
            foreach ($providerId in $providerIds) {
                Update-Environ -Type Provider -Name $providerId
                $environFileUpdated = $true
            }
        }
        $coreFileUpdated = $coreFileUpdated -or $environFileUpdated
        . $PSScriptRoot\environ.ps1

    #endregion ENVIRON
    #region PLATFORM INSTANCE DEFINITIONS

        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1 -ConfirmCopy)
        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1 -ConfirmCopy)

        $sourceFile = "$PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$($platformId.ToLower())-template.ps1"
        $destinationFile = "$PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1"
        $platformInstanceDefinitionsFileUpdated = Copy-File $sourcefile $destinationFile -ConfirmCopy
        $platformInstanceDefinitionsFile = Get-Content -Path $destinationFile
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformId>", ($platformId -replace " ","")
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstallLocation>", $platformInstallLocation
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceId>", $platformInstanceId
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceUrl>", $platformInstanceUri
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<platformInstanceDomain>", $platformInstanceDomain
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace '"<platformInstanceNodes>"', "@('$($platformInstanceNodes -join "', '")')"
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<pythonPipLocation>", $pythonPipLocation
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace "<pythonSitePackagesLocation>", $pythonSitePackagesLocation
        $platformInstanceDefinitionsFile = $platformInstanceDefinitionsFile -replace '"<requiredPythonPackages>"', "@('$($requiredPythonPackages -join "', '")')"
        $platformInstanceDefinitionsFile | Set-Content  -Path $destinationFile
        if ($platformInstanceDefinitionsFileUpdated) {
            Write-Host+ -NoTrace -NoTimestamp "Updated $destinationFile" -ForegroundColor DarkGreen
        }
        $coreFileUpdated = $coreFileUpdated -or $platformInstanceDefinitionsFileUpdated

    #endregion PLATFORM INSTANCE DEFINITIONS
    #region COPY

        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $PSScriptRoot\services -ConfirmCopy)
        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $PSScriptRoot\services -ConfirmCopy)

        $definitionsServices = "$PSScriptRoot\definitions\definitions-services.ps1"
        $definitionsServicesUpdated = $false

        foreach ($platformPrerequisiteService in $global:Catalog.Platform.$platformId.Installation.Prerequisite.Service) {
            $platformPrerequisiteServiceFileUpdated = Copy-File $PSScriptRoot\source\services\$($platformPrerequisiteService.ToLower())\services-$($platformPrerequisiteService.ToLower())*.ps1 $PSScriptRoot\services -ConfirmCopy
            if ($platformPrerequisiteServiceFileUpdated) {
                Get-Item $servicesPath\services-$($platformPrerequisiteService.ToLower())*.ps1 | 
                    Foreach-Object {
                        $contentLine = ". `$servicesPath\$($_.Name)"
                        if (!(Select-String -Path $definitionsServices -Pattern $contentLine -SimpleMatch -Quiet)) {
                            Add-Content -Path $definitionsServices -Value $contentLine
                            $definitionsServicesUpdated = $true
                        }
                    }
                }
            $coreFileUpdated = $coreFileUpdated -or $platformPrerequisiteServiceFileUpdated
        }

        foreach ($productSpecificService in $productSpecificServices) {
            $productFileUpdated = $false
            $productFileUpdated = $productFileUpdated -or (Copy-File $PSScriptRoot\source\services\$($productSpecificService.Service.ToLower())\definitions-service-$($productSpecificService.Service.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-service-$($productSpecificService.Service.ToLower()).ps1 -ConfirmCopy)
            $productFileUpdated = $productFileUpdated -or (Copy-File $PSScriptRoot\source\services\$($productSpecificService.Service.ToLower())\services-$($productSpecificService.Service.ToLower()).ps1 $PSScriptRoot\services\services-$($productSpecificService.Service.ToLower()).ps1 -ConfirmCopy)
            if ($productFileUpdated) {
                if ($productSpecificService.Product -notin $productIds) {
                    $productIds += $productSpecificService.Product
                }
                $contentLine1 = ". `$definitionsPath\definitions-service-$($productSpecificService.Service.ToLower()).ps1"
                $contentLine2 = ". `$servicesPath\services-$($productSpecificService.Service.ToLower()).ps1"
                if (!(Select-String -Path $definitionsServices -Pattern $contentLine1 -SimpleMatch -Quiet)) {
                    Add-Content -Path $definitionsServices -Value $contentLine1
                    Add-Content -Path $definitionsServices -Value $contentLine2
                    $definitionsServicesUpdated = $true
                }
            }
        }

        if ($definitionsServicesUpdated) {
            Write-Host+ -NoTrace -NoTimestamp "Updated $definitionsServices" -ForegroundColor DarkGreen
        }

        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\config-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1 -ConfirmCopy)
        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1 -ConfirmCopy)
        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\config\config-platform-$($platformInstanceId).ps1 -ConfirmCopy)

        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1 -ConfirmCopy)
        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1 -ConfirmCopy)
        $coreFileUpdated = $coreFileUpdated -or (Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformInstanceId).ps1 -ConfirmCopy)

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platforminstance-$($platformInstanceId).ps1
        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platforminstance-$($platformInstanceId).ps1

        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platforminstance-$($platformInstanceId).ps1
        Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-os-$($operatingSystemId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platform-$($platformId.ToLower()).ps1
        Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platforminstance-$($platformInstanceId).ps1

        if ($coreFileUpdated) {
            $productIds += $global:Environ.Product | Where-Object {$_ -notin $productIds}
            $providerIds += $global:Environ.Provider | Where-Object {$_ -notin $providerIds}
        }

        foreach ($product in $global:Environ.Product) {
            $productFileUpdated = $false
            $productFileUpdated = $productFileUpdated -or (Copy-File $PSScriptRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $PSScriptRoot\install\install-product-$($product.ToLower()).ps1 -ConfirmCopy)
            Copy-File $PSScriptRoot\source\product\$($product.ToLower())\uninstall-product-$($product.ToLower()).ps1 $PSScriptRoot\install\uninstall-product-$($product.ToLower()).ps1
            $productFileUpdated = $productFileUpdated -or (Copy-File $PSScriptRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.ToLower()).ps1 -ConfirmCopy)
            $productFileUpdated = $productFileUpdated -or (Copy-File $PSScriptRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $PSScriptRoot\$($product.ToLower()).ps1 -ConfirmCopy)
            if ($productFileUpdated -and $product.ToLower() -notin $productIds) {$productIds += $product.ToLower()}
        }      
        foreach ($provider in $global:Environ.Provider) {
            $providerFileUpdated = $false
            $providerFileUpdated = $providerFileUpdated -or (Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\install-provider-$($provider.ToLower()).ps1 -ConfirmCopy)
            Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\uninstall-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\uninstall-provider-$($provider.ToLower()).ps1
            $providerFileUpdated = $providerFileUpdated -or (Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-provider-$($provider.ToLower()).ps1 -ConfirmCopy)
            $providerFileUpdated = $providerFileUpdated -or (Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $PSScriptRoot\providers\provider-$($provider.ToLower()).ps1 -ConfirmCopy)
            if ($providerFileUpdated -and $provider.ToLower() -notin $providerIds) {$providerIds += $provider.ToLower()}
        }

    #endregion COPY
#endregion FILES

. $PSScriptRoot\definitions\classes.ps1
. $PSScriptRoot\definitions\catalog.ps1
. $PSScriptRoot\services\services-overwatch-loadearly.ps1
Write-Host+ -ResetAll

#region MODULES-PACKAGES

    Write-Host+ -MaxBlankLines 1
    $message = "<Powershell modules/packages <.>48> INSTALLING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    if (!(Get-PackageSource -ProviderName PowerShellGet)) {
        Register-PackageSource -Name PSGallery -Location "https://www.powershellgallery.com/api/v2" -ProviderName PowerShellGet -ErrorAction SilentlyContinue | Out-Null
    }
    $requiredModules = @("PsIni")
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ErrorAction SilentlyContinue | Out-Null)) {
            Install-Module -Name $module -ErrorAction SilentlyContinue | Out-Null
            Import-Module -Name $module -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (!(Get-PackageSource -ProviderName NuGet -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name Nuget -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -ErrorAction SilentlyContinue | Out-Null
    }
    $requiredPackages = @("Portable.BouncyCastle","MimeKit","MailKit")
    foreach ($package in $requiredPackages) {
        if (!(Get-Package -Name $package -ErrorAction SilentlyContinue)) {
            Install-Package -Name $package -SkipDependencies -Force | Out-Null
        }
    }

    $message = "$($emptyString.PadLeft(10,"`b"))INSTALLED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion MODULES-PACKAGES
#region PYTHON-PACKAGES

    switch ($platformId) {
        "AlteryxServer" {
            if ($requiredPythonPackages) {

                $message = "<Required Python Packages <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

                Install-PythonPackage -Package $requiredPythonPackages -Pip $pythonPipLocation -ComputerName $platformInstanceNodes -Quiet

                $message = "$($emptyString.PadLeft(10,"`b"))INSTALLED "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

            }
        }
        default {}
    }

#region PYTHON-PACKAGES
#region REMOVE CACHE

    if ($installOverwatch) {
        Remove-File "$PSScriptRoot\data\$($platformInstanceId.ToLower())\*.cache" -Quiet
    }

#endregion REMOVE CACHE
#region CREDENTIALS

    if ($installOverwatch) {
        . $PSScriptRoot\services\vault.ps1
        . $PSScriptRoot\services\encryption.ps1
        . $PSScriptRoot\services\credentials.ps1

        $message = "<Admin Credentials <.>48> VALIDATING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        if (!$(Test-Credentials -NoValidate "localadmin-$platformInstanceId")) { 
            Write-Host+
            Write-Host+

            Request-Credentials -Message "  Enter the local admin credentials" -Prompt1 "  User" -Prompt2 "  Password" | Set-Credentials "localadmin-$($global:Platform.Instance)"
            
            Write-Host+
            $message = "<Admin Credentials <.>48> VALID"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
            Write-Host+
        }
        else {
            $message = "$($emptyString.PadLeft(10,"`b"))VALID     "
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
    }

#endregion CREDENTIALS
#region INITIALIZE OVERWATCH

    $message = "<Overwatch <.>48> INITIALIZING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    try{
        psPref -xpref -xpostf -xwhp -Quiet
        $global:Product = @{Id="Command"}
        . $PSScriptRoot\definitions.ps1
    }
    catch {}
    finally {
        psPref -Quiet
    }

    $message = "$($emptyString.PadLeft(12,"`b"))INITIALIZED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

#endregion INITIALIZE OVERWATCH
#region REMOTE DIRECTORIES

    if ($installOverwatch) {
        $requiredDirectories = @("data\$platformInstanceId")

        $missingDirectories = @()
        foreach ($node in (pt nodes -k)) {
            $remotePSScriptRoot = "\\$node\$($PSScriptRoot.Replace(":","$"))"
            foreach ($requiredDirectory in $requiredDirectories) {
                if (!(Test-Path "$remotePSScriptRoot\$requiredDirectory")) { $missingDirectories += "$remotePSScriptRoot\$requiredDirectory" }
            }
        }
        if ($missingDirectories) {

            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp "Remote Directories" -ForegroundColor DarkGray
            Write-Host+ -NoTrace -NoTimestamp "------------------" -ForegroundColor DarkGray

            foreach ($missingDirectory in $missingDirectories) {
                New-Item -ItemType Directory -Path $missingDirectory -Force
            }

        }
    }

#endregion REMOTE DIRECTORIES
#region CONTACTS

    if ($installOverwatch) {
        $message = "<Contacts <.>48> UPDATING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        if (!(Test-Path $ContactsDB)) {New-ContactsDB}

        if (!(Get-Contact)) {
            while (!(Get-Contact)) {
                Write-Host+
                Write-Host+
                do {
                    $contactName = Read-Host "  Name"
                    if (Get-Contact -Name $contactName) {Write-Host+ -NoTrace -NoTimestamp "  Contact $($contactName) already exists." -ForegroundColor DarkYellow}
                } until (!(Get-Contact -Name $contactName))
                do {
                    $contactEmail = Read-Host "  Email (SMTP)"
                    if (!$contactEmail) {
                        Write-Host+ -NoTrace -NoTimestamp "    Email is required for SMTP." -ForegroundColor DarkYellow
                    }
                    elseif (Get-Contact -Email $contactEmail) {
                        Write-Host+ -NoTrace -NoTimestamp "    Email $($contactEmail) already exists." -ForegroundColor DarkYellow
                    }
                } until ($contactEmail -and !(Get-Contact -Email $contactEmail) -and $(IsValidEmail $contactEmail))
                do {
                    $contactPhone = Read-Host "  Phone (SMS)"
                    if (!$contactPhone) {
                        Write-Host+ -NoTrace -NoTimestamp "    Phone is required for SMS." -ForegroundColor DarkYellow
                    }
                    elseif (Get-Contact -Phone $contactPhone) {
                        Write-Host+ -NoTrace -NoTimestamp "    Phone $($contactPhone) already exists." -ForegroundColor DarkYellow
                    }
                } until ($contactPhone -and !(Get-Contact -Phone $contactPhone) -and $(IsValidPhone $contactPhone))
                Add-Contact $contactName -Email $contactEmail -Phone $contactPhone
            }

            Write-Host+
            $message = "<Contacts <.>48> UPDATED"
            Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
            Write-Host+

        }
        else {
            $message = "$($emptyString.PadLeft(8,"`b"))UPDATED "
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
    }

#endregion CONTACTS
#region LOG

    if ($installOverwatch) {
        $message = "<Log files <.>48> CREATING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

        $platformLogFile = ((Get-Catalog $Platform.Id -Type "Platform").Log).ToLower()
        if (!(Test-Log -Name $platformLogFile)) {
            New-Log -Name $platformLogFile | Out-Null
        }

        $message = "$($emptyString.PadLeft(8,"`b"))CREATED "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion LOG 
#region MAIN

    [console]::CursorVisible = $false

        #region CONFIG

            if ($Update) {

                if (Test-Path "$PSScriptRoot\config\config-os-$($operatingSystemId.ToLower())") {. "$PSScriptRoot\config\config-os-$($operatingSystemId.ToLower())" }
                if (Test-Path "$PSScriptRoot\config\config-platform-$($platformId.ToLower())") {. "$PSScriptRoot\config\config-platform-$($platformId.ToLower())" }
                if (Test-Path "$PSScriptRoot\config\config-platforminstance-$($platformInstanceId.ToLower())") {. "$PSScriptRoot\config\config-platforminstance-$($platformInstanceId.ToLower())" }

            }

        #endregion CONFIG
        #region PRODUCTS

            if ($productIds) {

                Write-Host+ -MaxBlankLines 1
                $message = "<Installing products <.>48> PENDING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Product             Publisher           Status              Task"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  -------             ---------           ------              ----"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

                foreach ($productId in $productIds) {

                    if ((Get-Product -Id $productId).HasTask) {
                        Disable-Product $productId -NoNewLine
                        Install-Product $productId -NoNewLine
                        if (!$SkipProductStart) {
                            Enable-Product $productId -NoNewLine
                        }
                        else {
                            Write-Host+
                        }
                    }
                    else {
                        Install-Product $productId
                    }

                }
                
                Write-Host+
                $message = "<Installing products <.>48> SUCCESS"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
                Write-Host+

            }

        #endregion PRODUCTS
        #region PROVIDERS

            if ($providerIds) {
                
                Write-Host+ -MaxBlankLines 1
                $message = "<Installing providers <.>48> PENDING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Provider            Publisher           Status"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  --------            ---------           ------"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray            

                $providerIds | ForEach-Object { Install-Provider $_ }
                
                Write-Host+ -MaxBlankLines 1
                $message = "<Installing providers <.>48> SUCCESS"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
                Write-Host+

            }

        #endregion PROVIDERS
        #region SAVE SETTINGS

            if (Test-Path $installSettings) {Clear-Content -Path $installSettings}
            '[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]' | Add-Content -Path $installSettings
            "Param()" | Add-Content -Path $installSettings
            "`$operatingSystemId = ""$operatingSystemId""" | Add-Content -Path $installSettings
            "`$platformId = ""$platformId""" | Add-Content -Path $installSettings
            "`$platformInstallLocation = ""$platformInstallLocation""" | Add-Content -Path $installSettings
            "`$platformInstanceId = ""$platformInstanceId""" | Add-Content -Path $installSettings
            "`$productIds = @('$($global:Environ.Product -join "', '")')" | Add-Content -Path $installSettings
            "`$providerIds = @('$($global:Environ.Provider -join "', '")')" | Add-Content -Path $installSettings
            "`$imagesUri = [System.Uri]::new(""$imagesUri"")" | Add-Content -Path $installSettings
            "`$platformInstanceUri = [System.Uri]::new(""$platformInstanceUri"")" | Add-Content -Path $installSettings
            "`$platformInstanceDomain = ""$platformInstanceDomain""" | Add-Content -Path $installSettings
            "`$platformInstanceNodes = @('$($platformInstanceNodes -join "', '")')" | Add-Content -Path $installSettings
            "`$requiredPythonPackages = @('$($requiredPythonPackages -join "', '")')" | Add-Content -Path $installSettings

        #endregion SAVE SETTINGS
        #region INITIALIZE OVERWATCH

            if ($productIds -or $providerIds) {

                $message = "<Overwatch <.>48> INITIALIZING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
            
                try{
                    psPref -xpref -xpostf -xwhp -Quiet
                    $global:Product = @{Id="Command"}
                    . $PSScriptRoot\definitions.ps1
                }
                catch {}
                finally {
                    psPref -Quiet
                }
            
                $message = "$($emptyString.PadLeft(12,"`b"))INITIALIZED "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

            }
        
        #endregion INITIALIZE OVERWATCH 
        #region POST-INSTALLATION CONFIG

            Show-PostInstallationConfiguration

        #endregion POST-INSTALLATION CONFIG

        Write-Host+ -MaxBlankLines 1
        $message = "Overwatch installation is complete."
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen
        Write-Host+

    [console]::CursorVisible = $true

#endregion MAIN