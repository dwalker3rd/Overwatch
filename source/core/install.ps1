#Requires -RunAsAdministrator
#Requires -Version 7

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param (
    [switch]$SkipPython,
    [switch]$SkipPowerShell,
    [switch]$UseDefaultResponses,
    [switch][Alias("PostInstall")]$PostInstallation
)

#region REMOVE PSSESSIONS

    # Remove-PSSession+

#endregion REMOVE PSSESSIONS

$global:WriteHostPlusPreference = "Continue"

$global:Environ = @{}
$global:Location = @{}

#region REQUIRED FILES

    . $PSScriptRoot\source\core\services\services-overwatch-loadearly.ps1
    . $PSScriptRoot\source\core\services\services-overwatch-install.ps1  

    #region ENVIRON

        $sourceEnvironFile = "$PSScriptRoot\source\environ\environ-template.ps1"
        $destinationEnvironFile = "$PSScriptRoot\environ.ps1"

        # if this is first install, then environ.ps1 does not exist
        # copy it to the users' temp directory and update the global Location variable
        if (!(Test-Path "environ.ps1")) {

            $tempEnvironFile = "$($env:TEMP)\environ.ps1"
            $tempEnvironFileNoProductsNoProviders = "$($env:TEMP)\environNoProductsNoProviders.ps1"
            
            Update-Environ -Mode Replace -Source $sourceEnvironFile -Destination $tempEnvironFile -Type Location -Name Root -Expression (Get-Location)
            Update-Environ -Mode Replace -Source $tempEnvironFile -Destination $tempEnvironFileNoProductsNoProviders -Type Environ -Name Product -Expression ""
            Update-Environ -Mode Replace -Source $tempEnvironFileNoProductsNoProviders -Destination $tempEnvironFileNoProductsNoProviders -Type Environ -Name Provider -Expression ""
            Remove-Variable -Scope Global Environ

            $environFile = $tempEnvironFileNoProductsNoProviders
        }
        else {
            $environFile = "$PSScriptRoot\environ.ps1"
        }

        . $environFile

        if (!(Test-Path "environ.ps1")) {
            $environFile = $tempEnvironFile
        }

    #endregion ENVIRON
    #region CATALOG

        if (!(Test-Path $global:Location.Definitions)) {
            New-Item -ItemType Directory -Path $global:Location.Definitions -Force | Out-Null
        }
        if (!(Test-Path $global:Location.Catalog)) {
            Copy-File "$($global:Location.Source)\core\definitions\catalog.ps1" $global:Location.Catalog -Quiet
        }
        if (!(Test-Path $global:Location.Classes)) {
            Copy-File "$($global:Location.Source)\core\definitions\classes.ps1" $global:Location.Classes -Quiet
        }

    #endregion CATALOG

#endregion REQUIRED FILES

. $PSScriptRoot\source\core\definitions\definitions-sysinternals.ps1
. $PSScriptRoot\source\core\definitions\definitions-powershell.ps1
. $global:Location.Classes
. $global:Location.Catalog
. $PSScriptRoot\source\core\definitions\definitions-regex.ps1
. $PSScriptRoot\source\core\definitions\definitions-overwatch.ps1
. $PSScriptRoot\source\core\services\services-overwatch-loadearly.ps1
. $PSScriptRoot\source\core\services\services-overwatch-install.ps1
. $PSScriptRoot\source\core\services\services-overwatch.ps1
. $PSScriptRoot\source\core\services\cache.ps1
. $PSScriptRoot\source\core\services\files.ps1
. $PSScriptRoot\source\core\services\logging.ps1
. $PSScriptRoot\source\core\services\python.ps1

Write-Host+ -ResetAll

#region POST INSTALL SHORTCUT

    if ($PostInstallation -and $PSBoundParameters.Keys.Count -gt 1) {
        Write-Host+ -NoTrace -NoTimestamp  "The PostInstallation switch cannot be used with other switches." -ForegroundColor Red
        return
    }

    if ($PostInstallation) {
        try{
            Show-PostInstallation
        }
        catch {
            Write-Host+ -NoTrace -NoTimestamp  "The PostInstallation switch cannot be used until Overwatch is initialized." -ForegroundColor Red
            Write-Host+
        }
        return
    }

#endregion POST INSTALL SHORTCUT

$global:DebugPreference = "SilentlyContinue"
$global:InformationPreference = "Continue"
$global:VerbosePreference = "SilentlyContinue"
$global:WarningPreference = "Continue"
$global:ProgressPreference = "SilentlyContinue"
$global:PreflightPreference = "SilentlyContinue"
$global:PostflightPreference = "SilentlyContinue"
$global:WriteHostPlusPreference = "Continue"

# Clear-Host

$disabledProductIds = @()
$impactedIds = @()
$impactedProductIds = @()
$impactedProductIdsWithTasks = @()
$impactedProductIdsWithEnabledTasks = @()
$productIds = @()
$providerIds = @()

#region INSTALLER UPDATE CHECK

    $installUpdateRestartData = read-cache installUpdateRestart
    $installUpdateRestart = $installUpdateRestartData.installUpdateRestart
    if ($installUpdateRestart) { $UseDefaultResponses = $true }

#endregion INSTALLER UPDATE CHECK
#region DISCOVERY

    Write-Host+
    Write-Host+ -NoTrace -NoTimestamp "Discovery" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "---------" -ForegroundColor DarkGray

    $overwatchInstallLocation = Get-Location

    $installedProducts = @()
    $installedProviders = @()
    $installMode = $null
    try {

        $message = "<Overwatch <.>24> SEARCHING"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $global:WriteHostPlusPreference = "SilentlyContinue"
        $global:Product = @{Id="Command"}
        . $PSScriptRoot\definitions.ps1 -MinimumDefinitions

        $installedProducts = Get-Catalog -Type Product -Installed
        $installedProviders = Get-Catalog -Type Provider -Installed
        $installMode = "Update"

        $global:WriteHostPlusPreference = "Continue"
        $message = "$($emptyString.PadLeft(9,"`b"))$($Overwatch.DisplayName) "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Blue

    }
    catch {
        $installMode = "Install"
        $global:WriteHostPlusPreference = "Continue"
        $message = "$($emptyString.PadLeft(9,"`b"))None      "
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor Gray
    }

    if ($installMode -eq "Install") {
        Write-Host+ -NoTrace -NoTimestamp -Parse "<Mode <.>24> Install" -ForegroundColor Gray,DarkGray,Blue
    }
    elseif ($installMode -eq "Update") {
        Write-Host+ -NoTrace -NoTimestamp -Parse  "<Mode <.>24> Update" -ForegroundColor Gray,DarkGray,Blue
    }

    $operatingSystemId = $null
    $installedOperatingSystem = $((Get-CimInstance -ClassName Win32_OperatingSystem).Name -split "\|")[0]
    foreach ($key in $global:Catalog.Os.Keys) {
        if ($installedOperatingSystem.StartsWith($global:Catalog.OS.$key.Name)) {
            $operatingSystemId = $key
        }
    }
    if ([string]::IsNullOrEmpty($operatingSystemId)) {
        throw "$installedOperatingSystem is not an Overwatch-supported operating system."
    }
    Write-Host+ -NoTrace -NoTimestamp -Parse "<Operating System <.>24> $installedOperatingSystem" -ForegroundColor Gray,DarkGray,Blue
    # $operatingSystemId = $installedOperatingSystem

    $installedPlatforms = @()
    foreach ($key in $global:Catalog.Platform.Keys) {
        # TODO: this is awkward and it confuses me: rework this
        $platformIsInstalled = $global:Catalog.Platform.$key.Installation.Flag -contains "UnInstallable" ? $false : $true
        foreach ($installationTest in $global:Catalog.Platform.$key.Installation.IsInstalled) {
            switch ($installationTest) {
                # test for os or platform services
                {$_.Type -in @("Service","PlatformService")} {
                    $platformIsInstalled = $platformIsInstalled -and (Invoke-Expression "Wait-$($installationTest.Type) -Name $($installationTest.$($installationTest.Type)) -Status Running -TimeoutInSeconds 1 -WaitTimeInSeconds 1")
                }
                # test for platforms which have the Installation.IsInstalled test defined
                {$_.Type -in @("Command")} {
                    $platformIsInstalled = $platformIsInstalled -and (Invoke-Command $installationTest.Command)
                }
            }
        }
        if ($platformIsInstalled) { $installedPlatforms += $key }
    }
    Write-Host+ -NoTrace -NoTimestamp -Parse "<Platform <.>24> $($installedPlatforms ? ($installedPlatforms -join ", ") : "None")" -ForegroundColor Gray,DarkGray,$($installedPlatforms ? "Blue" : "Gray")

    Write-Host+ -NoTrace -NoTimestamp -Parse "<Location <.>24> $((Get-Location).Path)" -ForegroundColor Gray,DarkGray,Blue

    Write-Host+

#endregion DISCOVERY

. $PSScriptRoot\source\core\services\tasks.ps1
. $PSScriptRoot\source\core\services\powershell.ps1

$tempLocationDefinitions = $global:Location.Definitions
$global:Location.Definitions = "$($global:Location.Root)\source\core\definitions"
. $PSScriptRoot\source\core\services\services-overwatch.ps1
$global:Location.Definitions = $tempLocationDefinitions

#region LOAD SETTINGS

    Write-Host+ -MaxBlankLines 1

    if (Test-Path -Path $($global:InstallSettings)) {
        . $($global:InstallSettings)
    }
    else {
        Write-Host+ -NoTrace -NoTimestamp "No saved settings in $installSettings" -ForegroundColor DarkGray
        Write-Host+
    } 

#endregion LOAD SETTINGS

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace -NoTimestamp "Installation Questions" -ForegroundColor DarkGray
    Write-Host+ -NoTrace -NoTimestamp "----------------------" -ForegroundColor DarkGray

#region OVERWATCH INSTALL LOCATION

    $_useDefaultResponses = $UseDefaultResponses
    do {
        $overwatchInstallLocationResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Overwatch Install Location ", "$($overwatchInstallLocation ? "[$overwatchInstallLocation]" : $PSScriptRoot)", ": " -ForegroundColor Gray, Blue, Gray
        if (!$UseDefaultResponses) {
            $overwatchInstallLocationResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $overwatchInstallLocation = ![string]::IsNullOrEmpty($overwatchInstallLocationResponse) ? $overwatchInstallLocationResponse : $overwatchInstallLocation
        Write-Host+ -NoTrace -NoTimestamp "Overwatch Install Location: $overwatchInstallLocation" -IfDebug -ForegroundColor Yellow
        if (!(Test-Path -Path $overwatchInstallLocation)) {
            $UseDefaultResponses = $false
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find path '$overwatchInstallLocation' because it does not exist." -ForegroundColor Red
            $overwatchInstallLocation = $null
        }
        elseif ((Get-Location).Path -ne $overwatchInstallLocation) {
            $UseDefaultResponses = $false
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] Current location and install location must be the same." -ForegroundColor Red
            $overwatchInstallLocation = $null
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The path '$overwatchInstallLocation' is valid." -IfVerbose -ForegroundColor DarkGreen
        }
    } until ($overwatchInstallLocation)
    if ($_useDefaultResponses) { $UseDefaultResponses = $true }
    Write-Host+ -NoTrace -NoTimestamp "Overwatch Install Location: $overwatchInstallLocation" -IfDebug -ForegroundColor Yellow

    #region REGISTRY

        $catalogFileContent = Get-Content -Path $global:Location.Catalog -Raw
        $result = [regex]::Matches($catalogFileContent, $global:RegexPattern.Overwatch.Registry.Path)
        $overwatchRegistryPath = $result[0].Groups['OverwatchRegistryPath'].Value
        $overwatchRegistryKey = "InstallLocation"
        if (!(Test-Path -Path $overwatchRegistryPath)) {
            New-Item -Path $overwatchRegistryPath -Force | Out-Null
        }
        Set-ItemProperty -Path $overwatchRegistryPath -Name $overwatchRegistryKey -Value $overwatchInstallLocation 

    #endregion REGISTRY

#endregion OVERWATCH INSTALL LOCATION

    $requiredDependenciesNotInstalled = @()

#region CLOUD

    $supportedCloudProviderIds = @()
    $supportedCloudProviderIds += $global:Catalog.Cloud.Keys
    # Write-Host+ -NoTrace -NoTimestamp -NoSeparator "Supported Cloud Providers: ", "$($supportedCloudProviderIds -join ", ")" -ForegroundColor Gray, Blue 
    if ([string]::IsNullOrEmpty($cloudId)) { $cloudId = "None" }

    $_useDefaultResponses = $UseDefaultResponses
    do {
        $cloudIdResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Select Cloud Provider ", "[$($supportedCloudProviderIds -join ", ")]", " or enter `"None`" ", "[$cloudId]", ": " -ForegroundColor Gray, Blue, Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $cloudIdResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $cloudId = ![string]::IsNullOrEmpty($cloudIdResponse) ? $cloudIdResponse : $cloudId
        Write-Host+ -NoTrace -NoTimestamp "Cloud ID: $cloudId" -IfDebug -ForegroundColor Yellow
        if ($supportedCloudProviderIds -notcontains $cloudId -and $cloudId -ne "None") {
            $UseDefaultResponses = $false
            Write-Host+ -NoTrace -NoTimestamp "Cloud provider must be one of the following: $($supportedCloudProviderIds -join ", ")" -ForegroundColor Red
            $cloudId = $null
        }
    } until ($supportedCloudProviderIds -contains $cloudId -or $cloudId -eq "None")
    if ($_useDefaultResponses) { $UseDefaultResponses = $true }
    if (![string]::IsNullOrEmpty($cloudId) -and $cloudId -ne "None") {
        $requiredDependenciesNotInstalled += Get-CatalogDependencies -Type Cloud -Id $cloudId -Include Product,Provider -NotInstalled
    }

#endregion CLOUD
#region PLATFORM ID

    $unInstallablePlatforms = (Get-Catalog -Type Platform | Where-Object {$_.Installation.Flag -contains "UnInstallable"}).Id
    if ([string]::IsNullOrEmpty($installedPlatforms)) {
        if ([string]::IsNullOrEmpty($platformId)) {
            # make sure "None" is listed first
            $installedPlatforms = @("None",($unInstallablePlatforms -split ", " | Where-Object {$_ -ne "None"}) -join ", ")
        }
        else {
            $installedPlatforms = @($platformId)
        }
    }
    # $platformId = $installedPlatforms[0]

    $_useDefaultResponses = $UseDefaultResponses
    do {
        $platformIdResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Select Platform ", "$(![string]::IsNullOrEmpty($platformId) ? "[$($platformId)]" : "[$($installedPlatforms -join ", ")]")", ": " -ForegroundColor Gray, Blue, Gray 
        if (!$UseDefaultResponses) {
            $platformIdResponse = Read-Host
        }
        else {
            Write-Host+
        }
        $platformId = ![string]::IsNullOrEmpty($platformIdResponse) ? $platformIdResponse : $platformId
        Write-Host+ -NoTrace -NoTimestamp "Platform ID: $platformId" -IfDebug -ForegroundColor Yellow
        if ($installedPlatforms -notcontains $platformId) {
            $UseDefaultResponses = $false
            Write-Host+ -NoTrace -NoTimestamp "Platform must be one of the following: $($installedPlatforms -join ", ")" -ForegroundColor Red
        }
    } until ($installedPlatforms -contains $platformId)
    if ($_useDefaultResponses) { $UseDefaultResponses = $true }
    $requiredDependenciesNotInstalled += Get-CatalogDependencies -Type Platform -Id $platformId -Include Cloud,Product,Provider -NotInstalled

#endregion PLATFORM ID
#region PLATFORM INSTALL LOCATION

    if ($platformId -notin $unInstallablePlatforms) {
        $_useDefaultResponses = $UseDefaultResponses
        if ([string]::IsNullOrEmpty($platformInstallLocation)) {
            if ($global:Catalog.Platform.$platformId.Installation.InstallLocation) {
                $platformInstallLocation = Invoke-Command $global:Catalog.Platform.$platformId.Installation.InstallLocation
            }
        }
        do {
            $platformInstallLocationResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Install Location ", "$($platformInstallLocation ? "[$platformInstallLocation]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $platformInstallLocationResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $platformInstallLocation = ![string]::IsNullOrEmpty($platformInstallLocationResponse) ? $platformInstallLocationResponse : $platformInstallLocation
            Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow
            if (!(Test-Path -Path $platformInstallLocation)) {
                $UseDefaultResponses = $false
                Write-Host+ -NoTrace -NoTimestamp "[ERROR] Cannot find path '$platformInstallLocation' because it does not exist." -ForegroundColor Red
                $platformInstallLocation = $null
            }
            else {
                Write-Host+ -NoTrace -NoTimestamp "[SUCCESS] The path '$platformInstallLocation' is valid." -IfVerbose -ForegroundColor DarkGreen
            }
        } until ($platformInstallLocation)
        if ($_useDefaultResponses) { $UseDefaultResponses = $true }
        Write-Host+ -NoTrace -NoTimestamp "Platform Install Location: $platformInstallLocation" -IfDebug -ForegroundColor Yellow
    }

#endregion PLATFORM INSTALL LOCATION

    if ($global:Catalog.Platform.$platformId.Installation.Flags -notcontains "NoPlatformInstanceUri") {

        #region PLATFORM INSTANCE URI

            if ($platformId -notin $unInstallablePlatforms) {
                    $_useDefaultResponses = $UseDefaultResponses
                    do {
                        try {
                            $platformInstanceUriResponse = $null
                            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance URI ", "$($platformInstanceUri ? "[$platformInstanceUri]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
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
                            $UseDefaultResponses = $false
                            Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid URI format" -ForegroundColor Red
                            $platformInstanceUri = $null
                        }
                    } until ($platformInstanceUri)
                    if ($_useDefaultResponses) { $UseDefaultResponses = $true }
                    Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceUri" -IfDebug -ForegroundColor Yellow
            }

        #endregion PLATFORM INSTANCE URI
        #region PLATFORM INSTANCE DOMAIN

            if ($platformId -notin $unInstallablePlatforms) {
                $platformInstanceDomain ??= $platformInstanceUri.Host.Split(".",2)[1]
                $_useDefaultResponses = $UseDefaultResponses
                do {
                    $platformInstanceDomainResponse = $null
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Domain ", "$($platformInstanceDomain ? "[$platformInstanceDomain]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
                    if (!$UseDefaultResponses) {
                        $platformInstanceDomainResponse = Read-Host
                    }
                    else {
                        Write-Host+
                    }
                    $platformInstanceDomain = ![string]::IsNullOrEmpty($platformInstanceWriteDomainResponse) ? $platformInstanceDomainResponse : $platformInstanceDomain
                    if (![string]::IsNullOrEmpty($platformInstanceDomain) -and $platformInstanceUri.Host -notlike "*$platformInstanceDomain") {
                        $UseDefaultResponses = $false
                        Write-Host+ -NoTrace -NoTimestamp "ERROR: Invalid domain. Domain must match the platform instance URI" -ForegroundColor Red
                        $platformInstanceDomain = $null
                    }
                } until ($platformInstanceDomain)
                if ($_useDefaultResponses) { $UseDefaultResponses = $true }
                Write-Host+ -NoTrace -NoTimestamp "Platform Instance Uri: $platformInstanceDomain" -IfDebug -ForegroundColor Yellow
            }

        #endregion PLATFORM INSTANCE DOMAIN

    }

#region PLATFORM INSTANCE ID

    # if ($platformId -eq "None") {
    #     $platformInstanceId = "None"
    # }
    # else {
        $platformInstanceIdRegex = (Get-Catalog -Type "Platform" -Id $platformId).Installation.PlatformInstanceId
        if (!$platformInstanceIdRegex) {
            $platformInstanceIdRegex = @{
                Input = "`$global:Platform.Uri.Host"
                Pattern = "\."
                Replacement = "-"
            }
        }
        if ([string]::IsNullOrEmpty($platformInstanceId)) {
            $platformInstanceId = (Invoke-Expression $platformInstanceIdRegex.Input) -replace $platformInstanceIdRegex.Pattern,$platformInstanceIdRegex.Replacement
        }

        $_useDefaultResponses = $UseDefaultResponses
        do {
            $platformInstanceIdResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance ID ", "$($platformInstanceId ? "[$platformInstanceId]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $platformInstanceIdResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $platformInstanceId = ![string]::IsNullOrEmpty($platformInstanceIdResponse) ? $platformInstanceIdResponse : $platformInstanceId
            if ([string]::IsNullOrEmpty($platformInstanceId)) {
                $UseDefaultResponses = $false
                Write-Host+ -NoTrace -NoTimestamp "NULL: Platform Instance ID is required" -ForegroundColor Red
                $platformInstanceId = $null
            }
            if ($platformInstanceId -notmatch "^[a-zA-Z0-9\-]*$") {
                $UseDefaultResponses = $false
                Write-Host+ -NoTrace -NoTimestamp "INVALID CHARACTER: letters, digits and hypen only" -ForegroundColor Red
                $platformInstanceId = $null
            }
        } until ($platformInstanceId)
        if ($_useDefaultResponses) { $UseDefaultResponses = $true }
        Write-Host+ -NoTrace -NoTimestamp "Platform Instance ID: $platformInstanceId" -IfDebug -ForegroundColor Yellow
    # }

#endregion PLATFORM INSTANCE ID
#region PLATFORM INSTANCE NODES

    if ($global:Catalog.Platform.$platformId.Installation.Flags -contains "HasPlatformInstanceNodes") {
        $_useDefaultResponses = $UseDefaultResponses
        do {
            $platformInstanceNodesResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Platform Instance Nodes ", "$($platformInstanceNodes ? "[$($platformInstanceNodes -join ", ")]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
            if (!$UseDefaultResponses) {
                $platformInstanceNodesResponse = Read-Host
            }
            else {
                Write-Host+
            }
            $platformInstanceNodes = ![string]::IsNullOrEmpty($platformInstanceNodesResponse) ? $platformInstanceNodesResponse : $platformInstanceNodes
            if ([string]::IsNullOrEmpty($platformInstanceNodes)) {
                $UseDefaultResponses = $false
                Write-Host+ -NoTrace -NoTimestamp "NULL: Platform Instance Nodes is required" -ForegroundColor Red
                $platformInstanceNodes = $null
            }
        } until ($platformInstanceNodes)
        if ($_useDefaultResponses) { $UseDefaultResponses = $true }
        $platformInstanceNodes = $platformInstanceNodes -split "," | ForEach-Object { $_.Trim(" ") }
        Write-Host+ -NoTrace -NoTimestamp "Platform Instance Nodes: $platformInstanceNodes" -IfDebug -ForegroundColor Yellow
    }
    else {
        $platformInstanceNodes = $env:COMPUTERNAME
    }

#endregion PLATFORM INSTANCE NODES 
#region PYTHON

    if ($null -ne $global:Catalog.Platform.$platformId.Installation.Python) {
        $pythonEnvLocation = Invoke-Command $global:Catalog.Platform.$platformId.Installation.Python.Location.Env
        $pythonPipLocation = Invoke-Command $global:Catalog.Platform.$platformId.Installation.Python.Location.Pip
        $pythonSitePackagesLocation = Invoke-Command $global:Catalog.Platform.$platformId.Installation.Python.Location.SitePackages
        $requiredPythonPackagesResponse = $null
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Required Python Packages ", "$($requiredPythonPackages ? "[$($requiredPythonPackages -join ", ")]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
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

#region PYTHON
#region IMAGES

    $_useDefaultResponses = $UseDefaultResponses
    do {
        try {
            $imagesUriResponse = $null
            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Images URL ", "$($imagesUri ? "[$imagesUri]" : "[]")", ": " -ForegroundColor Gray, Blue, Gray
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
                $UseDefaultResponses = $false
                Write-Host+ -NoTrace -NoTimestamp "[ERROR] Overwatch image files not found at '$imgFile'" -ForegroundColor Red
                $imagesUri = $null
            }
        }
    } until ($imagesUri)
    if ($_useDefaultResponses) { $UseDefaultResponses = $true }
    Write-Host+ -NoTrace -NoTimestamp "Public URI for images: $imagesUri" -IfDebug -ForegroundColor Yellow
    Write-Host+

#endregion IMAGES
#region LOCAL DIRECTORIES

    $requiredDirectories = @("archive","config","data","definitions","docs","docs\img","img","initialize","install","logs","preflight","postflight","providers","services","temp","install\data","views")

    $missingDirectories = @()
    foreach ($requiredDirectory in $requiredDirectories) {
        if (!(Test-Path "$PSScriptRoot\$requiredDirectory")) { $missingDirectories += "$PSScriptRoot\$requiredDirectory" }
    }
    if ($missingDirectories) {

        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "Local Directories" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "-----------------" -ForegroundColor DarkGray

        foreach ($missingDirectory in $missingDirectories) {
            $_dir = New-Item -ItemType Directory -Path $missingDirectory -Force
            Write-Host+ -NoTrace -NoTimeStamp "Directory: $($_dir.FullName)"
        }

        Write-Host+

    }

#endregion LOCAL DIRECTORIES
#region PRODUCTS

    if ($installedProducts) {
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "Installed Products" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "------------------" -ForegroundColor DarkGray
        ($installedProducts.Id | Sort-Object) -join ", "
        Write-Host+
    }
    
    $productHeaderWritten = $false
    $productsSelected = @()
    foreach ($key in $global:Catalog.Product.Keys) {
        $product = $global:Catalog.Product.$key
        if ([string]::IsNullOrEmpty($product.Installation.Prerequisites.Platform) -or $product.Installation.Prerequisites.Platform -contains $platformId) {
            if ($product.Id -notin $installedProducts.Id -and $product.Id -notin $requiredDependenciesNotInstalled.Id) {
                # if ((Test-Prerequisites -Type "Product" -Id $product.Id -PrerequisiteType "Installation" -Quiet).Pass) {
                    if (!$productHeaderWritten) {
                        Write-Host+ -MaxBlankLines 1
                        Write-Host+ -NoTrace -NoTimestamp "Select Products" -ForegroundColor DarkGray
                        Write-Host+ -NoTrace -NoTimestamp "---------------" -ForegroundColor DarkGray
                        $productHeaderWritten = $true
                    }
                    if ($product.Installation.Flag -contains "AlwaysInstall") {
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator "Install $($product.Id) ","[Y]",": Always Install" -ForegroundColor DarkGray,DarkBlue,DarkGray
                        $productsSelected += $product.Id
                    }
                    elseif ($product.Installation.Flag -notcontains "NoPrompt") {
                        $productResponseDefault = $product.ID -in $productIds ? "Y" : "N"
                        $productResponse = $null
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine "Install $($product.Id) ","[$productResponseDefault]",": " -ForegroundColor Gray,Blue,Gray
                        if (!$UseDefaultResponses) {
                            $productResponse = Read-Host
                        }
                        else {
                            Write-Host+
                        }
                        if ([string]::IsNullOrEmpty($productResponse)) {$productResponse = $productResponseDefault}
                        if ($productResponse -eq "Y") {
                            $productsSelected += $product.Id
                            $requiredDependenciesNotInstalled += Get-CatalogDependencies -Type Product -Id $product.id -Exclude Overwatch,Cloud,OS,Platform -NotInstalled -Platform $platformId
                        }
                    }
                # }
            }
        }
    }
    $productIds = [array]($productsSelected | Where-Object {$_ -notin $productIds})

    Write-Host+ -Iff $productHeaderWritten

#endregion PRODUCTS
#region PROVIDERS

    if ($installedProviders) {
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "Installed Providers" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "-------------------" -ForegroundColor DarkGray
        ($installedProviders.Id | Sort-Object) -join ", "
        Write-Host+
    }

    $providerHeaderWritten = $false
    $providersSelected = @()
    foreach ($key in $global:Catalog.Provider.Keys) {
        $provider = $global:Catalog.Provider.$key
        if ([string]::IsNullOrEmpty($provider.Installation.Prerequisites.Platform) -or $provider.Installation.Prerequisites.Platform -contains $platformId) {
            if ($provider.Id -notin $installedProviders.Id -and $provider.Id -notin $requiredDependenciesNotInstalled.Id) {
                if (!$providerHeaderWritten) {
                    Write-Host+ -MaxBlankLines 1
                    Write-Host+ -NoTrace -NoTimestamp "Select Providers" -ForegroundColor DarkGray
                    Write-Host+ -NoTrace -NoTimestamp "----------------" -ForegroundColor DarkGray
                    $providerHeaderWritten = $true
                }
                if ($provider.Installation.Flag -contains "AlwaysInstall") {
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator "Install $($provider.Id) ","[Y]",": Always Install" -ForegroundColor DarkGray,DarkBlue,DarkGray
                    $providersSelected += $provider.Id
                }
                elseif ($provider.Installation.Flag -notcontains "NoPrompt") {
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
                        $providersSelected += $provider.Id
                        $requiredDependenciesNotInstalled += Get-CatalogDependencies -Type Provider -Id $provider.id -Exclude Overwatch,Cloud,OS,Platform -NotInstalled -Platform $platformId
                    }
                }
            }
        }
    }
    $providerIds = [array]($providersSelected | Where-Object {$_ -notin $providerIds})

    Write-Host+ -Iff $providerHeaderWritten

#endregion PROVIDERS
#region DEPENDENCIES 

    if ($requiredDependenciesNotInstalled) {
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "Dependencies" -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp "------------" -ForegroundColor DarkGray
        foreach ($dependency in $requiredDependenciesNotInstalled) {
            $dependencyType = $dependency.Type
            $dependencyId = $dependency.Id
            $dependentType = ($dependency.Dependent -split "\.")[0]
            $dependentId = ($dependency.Dependent -split "\.")[1]
            if ($dependentType -cne $dependentType.ToUpper()) { $dependentType = $dependentType.ToLower() }
            if ($dependencyType -eq "PowerShell") {
                $dependencyId = "$($dependencyId -replace "s$") $($dependency.Object.Name)"
            }
            Write-Host+ -NoTrace -NoTimestamp "$($dependencyType) $($dependencyId)","(required by $dependentId $dependentType)" -ForegroundColor Gray,DarkGray
            switch ($dependency.Type) {
                "Product" { $productIds += [array]($dependency.Id | Where-Object {$_ -notin $productIds}) }
                "Provider" { $providerIds += [array]($dependency.Id | Where-Object {$_ -notin $providerIds}) }
            }
        }
        Write-Host+
    }

#endregion DEPENDENCIES 
#region UPDATES

    if ($installMode -eq "Update") {

        Write-Host+ -MaxBlankLines 1
        $message = "<Updated Files <.>48> SCANNING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        Write-Host+

        $updatedFiles = @()

        #region ENVIRON

            $sourceEnvironFile = "$PSScriptRoot\source\environ\environ-template.ps1"
            $tempEnvironFile = "$PSScriptRoot\temp\environ.ps1"
            $destinationEnvironFile = "$PSScriptRoot\environ.ps1"

            Update-Environ -Source $sourceEnvironFile -Destination $tempEnvironFile

            $environFile = Copy-File $tempEnvironFile $destinationEnvironFile -WhatIf -Quiet

            $environFileUpdated = $false
            if ($environFile) {

                $environFile.Component = "Core"
                $environFile.$($environFile.Component) = "Environ"
                $environFile += @{ Flag = "NOCOPY" }
                $environFileUpdated = $true
                Write-Host+ -NoTrace -NoTimestamp "  [$($environFile.Component)`:$($environFile.$($environFile.Component))] $($environFile.Destination)" -ForegroundColor DarkGray

                $environFileImpacts = @()
                foreach ($cloudImpact in (Compare-Object (Get-EnvironConfig -Key Environ.Cloud -Path $destinationEnvironFile) (Get-EnvironConfig -Key Environ.Cloud -Path $tempEnvironFile) -PassThru)) {
                    $environFileImpacts += "Cloud.$cloudImpact"
                }
                foreach ($productImpact in (Compare-Object (Get-EnvironConfig -Key Environ.Product -Path $destinationEnvironFile) (Get-EnvironConfig -Key Environ.Product -Path $tempEnvironFile) -PassThru)) {
                    $environFileImpacts += "Product.$productImpact"
                }
                foreach ($providerImpact in (Compare-Object (Get-EnvironConfig -Key Environ.Provider -Path $destinationEnvironFile) (Get-EnvironConfig -Key Environ.Provider -Path $tempEnvironFile) -PassThru)) {
                    $environFileImpacts += "Provider.$providerImpact"
                }

                $updatedFiles += $environFile

            }
            Remove-Files -Path $tempEnvironFile

        #endregion ENVIRON
        #region CORE

            $coreFiles = @()

            $files = (Get-ChildItem $PSScriptRoot\source\core -File).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            $files = (Get-ChildItem $PSScriptRoot\source\core\config -File).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            $files = (Get-ChildItem $PSScriptRoot\source\core\definitions -File).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            # if classes file is updated, then all cache will need to be deleted before Overwatch is initialized
            $classesFile = Copy-File $PSScriptRoot\source\core\definitions\classes.ps1 $PSScriptRoot\definitions\classes.ps1 -WhatIf
            $classesFileUpdated = $null -ne $classesFile
            # $coreFiles += $classesFile

            $files = (Get-ChildItem $PSScriptRoot\source\core\services -File -Recurse).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }
            $files = (Get-ChildItem $PSScriptRoot\source\core\views -File -Recurse).VersionInfo.FileName
            foreach ($file in $files) { 
                $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
                if ($coreFile) {
                    $coreFiles += $coreFile
                }
            }

            $updatedfiles += $coreFiles

            $installUpdate = $false
            if ($coreFiles.Count -gt 0 -and (Split-Path $coreFiles.Destination -Leaf) -like "*install.ps1") {
                $installUpdate = $true
            }

        #endregion CORE
        #region CLOUD

            $cloudFiles = @()
            $cloudInstallUpdate = $Null
            $cloudFiles += Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\definitions-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-cloud-$($cloudId.ToLower()).ps1 -WhatIf
            $cloudFiles += Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\services-$($cloudId.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            $cloudInstallUpdate = Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\install-cloud-$($cloudId.ToLower()).ps1 $PSScriptRoot\install\install-cloud-$($cloudId.ToLower()).ps1 -WhatIf
            $cloudFiles += $cloudInstallUpdate
            $cloudFiles += Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\config-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\config\config-cloud-$($cloudId.ToLower()).ps1 -WhatIf
            $cloudFiles += Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\initialize-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-cloud-$($cloudId.ToLower()).ps1 -WhatIf
            $updatedFiles += $cloudFiles

        #endregion CLOUD
        #region OS

            $osFiles = @()
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\config-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
            $osFiles += Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
            $updatedFiles += $osFiles

        #endregion OS
        #region PLATFORM            

            $platformFiles = @()
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\config\config-platform-$($platformInstanceId).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1 -WhatIf
            $platformFiles += Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformInstanceId).ps1 -WhatIf
            foreach ($platformPrerequisiteService in $global:Catalog.Platform.$platformId.Installation.Prerequisites.Service) {
                $platformFiles += Copy-File $PSScriptRoot\source\services\$($platformPrerequisiteService.ToLower())\services-$($platformPrerequisiteService.ToLower())*.ps1 $PSScriptRoot\services -WhatIf
            }
            $updatedFiles += $platformFiles

        #endregion PLATFORM
        #region PRODUCT

            $productFiles = @()
            $productIdsToReinstall = @()
            $allProductIds = $global:Environ.Product
            if ($productIds) { $allProductIds += $productIds }
            foreach ($product in $allProductIds) {
                $productFiles += Copy-File $PSScriptRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $PSScriptRoot\install\install-product-$($product.ToLower()).ps1 -WhatIf
                $productTemplateFile = Copy-File $PSScriptRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.ToLower()).ps1 -WhatIf
                if ($productTemplateFile) { $productIdsToReinstall += $productTemplateFile.Product }
                $productFiles += $productTemplateFile
                $productFiles += Copy-File $PSScriptRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $PSScriptRoot\$($product.ToLower()).ps1 -WhatIf
            }

            $updatedFiles += $productFiles

        #endregion PRODUCT
        #region PROVIDER                    

            $providerFiles = @()
            $providerIdsToReinstall = @()
            $allProviderIds = $global:Environ.Provider
            if ($providerIds) { $allProviderIds += $providerIds }
            foreach ($provider in $allProviderIds) {
                $providerFiles += Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\install-provider-$($provider.ToLower()).ps1 -WhatIf
                $providerTemplateFile = Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-provider-$($provider.ToLower()).ps1 -WhatIf
                if ($providerTemplateFile) { $providerIdsToReinstall += $providerTemplateFile.Provider }
                $providerFiles += $providerTemplateFile
                $providerFiles += Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $PSScriptRoot\providers\provider-$($provider.ToLower()).ps1 -WhatIf
            }

            $updatedFiles += $providerFiles

        #endregion PROVIDER

        if (!$updatedFiles) {
            Write-Host+ -ReverseLineFeed 1
            $message = "<Updated Files <.>48> NONE    "
            Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 2 -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        }
        else {
            $updatedFiles = $updatedFiles | Where-Object {!$_.NoClobber}
            Write-Host+
        }

    }

#endregion UPDATES
#region IMPACT

    $_impactedIds = @()

    $productIds += $productIdsToReinstall | Where-Object {$_ -notin $productIds}
    $providerIds += $providerIdsToReinstall | Where-Object {$_ -notin $providerIds}

    if ($environFile) {
        $_impactedIds += $environFileImpacts
        foreach ($environFileImpact in $environFileImpacts) {
            $_impactedDependentId = (Get-CatalogDependents -Uid $environFileImpact -Installed).Uid
            if ($_impactedDependentId) { $_impactedIds += $_impactedDependentId }
        }
    }
    if ($coreFiles) {
        $_impactedIds += (Get-Catalog -Installed).Uid()
    }
    if ($osFiles) {
        foreach ($osFile in $osFiles) { $_impactedIds += "OS.$($osFile.OS)"}
        foreach ($osId in $osIds) {
            $_impactedDependentId = (Get-CatalogDependents -Type OS $osId -Installed).Uid
            if ($_impactedDependentId) { $_impactedIds += $_impactedDependentId }
        }
    }
    if ($cloudFiles) {
        foreach ($cloudFile in $cloudFiles) { $_impactedIds += "Cloud.$($cloudFile.Cloud)"}
        foreach ($cloudId in $cloudIds) {
            $_impactedDependentId = (Get-CatalogDependents -Type Cloud $cloudId -Installed).Uid
            if ($_impactedDependentId) { $_impactedIds += $_impactedDependentId }
        }
    }    
    if ($platformFiles) {
        foreach ($platformFile in $platformFiles) { $_impactedIds += "Platform.$($platformFile.Platform)"}
        foreach ($platformId in $platformIds) {
            $_impactedDependentId = (Get-CatalogDependents -Type Platform $platformId -Installed).Uid
            if ($_impactedDependentId) { $_impactedIds += $_impactedDependentId }
        }
    }
    if ($productFiles) {
        foreach ($productFile in $productFiles) { $_impactedIds += "Product.$($productFile.Product)"}
        foreach ($productId in $productIds) {
            $_impactedDependentId = (Get-CatalogDependents -Type Product $productId -Installed).Uid
            if ($_impactedDependentId) { $_impactedIds += $_impactedDependentId }
        }
    }
    if ($providerFiles) {
        foreach ($providerFile in $providerFiles) { $_impactedIds += "Provider.$($providerFile.Provider)"}
        foreach ($providerId in $providerIds) {
            $_impactedDependentId = (Get-CatalogDependents -Type Provider $providerId -Installed).Uid
            if ($_impactedDependentId) { $_impactedIds += $_impactedDependentId }
        }
    }

    $impactedIds = $_impactedIds | Select-Object -Unique
    $impactedProductIds = $impactedIds | Where-Object { $_.StartsWith("Product.") } | Where-Object { ($_ -split "\.")[1] -notin $productIds}
    $impactedProductIdsWithTasks = $impactedProductIds | Where-Object { (Get-Catalog -Uid $_).HasTask }
    $_disabledPlatformTasks = Get-PlatformTask -Disabled
    if ($_disabledPlatformTasks) {
        $disabledProductIds += "Product.$($_disabledPlatformTasks.ProductID)"
    }
    $impactedProductIdsWithEnabledTasks = $impactedProductIdsWithTasks | Where-Object {$_ -notin $disabledProductIds}
    $impactedProviderIds = $impactedIds | Where-Object { $_.StartsWith("Provider.") } | Where-Object { ($_ -split "\.")[1] -notin $providerIds}

    if ($impactedProductIdsWithEnabledTasks) {

        Write-Host+ -MaxBlankLines 1
        $message = "<Impacted Products <.>48> DISABLING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,Red
        Write-Host+

        $message = "  Product             Status              Task"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
        $message = "  -------             ------              ----"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

        foreach ($impactedProductIdsWithEnabledTask in $impactedProductIdsWithEnabledTasks) {
            Disable-Product $impactedProductIdsWithEnabledTask
        }

        Write-Host+

    }

#endregion IMPACT
#region FILES

    if ($installMode -eq "Install" -or $updatedFiles) {

        Write-Host+ -MaxBlankLines 1
        $message = $installMode -eq "Install" ? "<Source Files <.>48> COPYING" : "<Updated Files <.>48> COPYING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
        Write-Host+

        #region CORE

            $files = (Get-ChildItem $PSScriptRoot\source\core -File -Recurse).VersionInfo.FileName
            foreach ($file in $files) { 
                Copy-File $file $file.replace("\source\core","")
            }

            $destinationEnvironFileExists = Test-Path $destinationEnvironFile
            if ($installMode -eq "Install") {
                Update-Environ -Source  $tempEnvironFile -Destination $destinationEnvironFile
            }
            elseif ($installMode -eq "Update") {
                if ($environFileUpdated) {
                    Update-Environ -Source $sourceEnvironFile -Destination $destinationEnvironFile
                }
            }
            Write-Host+ -NoTrace -NoTimestamp "  $($destinationEnvironFileExists ? "Updated" : "Created") $destinationEnvironFile" -ForegroundColor DarkGreen
            . $PSScriptRoot\environ.ps1

        #endregion ENVIRON
        #region CLOUD

            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\definitions-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\services-$($cloudId.ToLower())*.ps1 $PSScriptRoot\services
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\install-cloud-$($cloudId.ToLower()).ps1 $PSScriptRoot\install\install-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\config-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\config\config-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\initialize-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\preflightchecks-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\preflightupdates-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\posttflightchecks-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\posttflight\postflightchecks-cloud-$($cloudId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\cloud\$($cloudId.ToLower())\postflightupdates-cloud-$($cloudId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-cloud-$($cloudId.ToLower()).ps1

        #endregion CLOUD
        #region OS

            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $PSScriptRoot\services
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\config-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\preflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightchecks-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-os-$($operatingSystemId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\os\$($operatingSystemId.ToLower())\postflightupdates-os-$($operatingSystemId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-os-$($operatingSystemId.ToLower()).ps1

        #endregion OS
        #region PLATFORM

            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1

            $sourceFile = "$PSScriptRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$($platformId.ToLower())-template.ps1"
            $destinationFile = "$PSScriptRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1"
            if (Copy-File $sourcefile $destinationFile -ConfirmCopy) {
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
                Write-Host+ -NoTrace -NoTimestamp "  Updated $destinationFile" -ForegroundColor DarkGreen
            }

            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $PSScriptRoot\services
            
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platform-$($platformId.ToLower()).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platform-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platform-$($platformId.ToLower()).ps1

            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\config\config-platform-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $PSScriptRoot\initialize\initialize-platform-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightchecks-platforminstance-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\preflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\preflight\preflightupdates-platforminstance-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightchecks-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightchecks-platforminstance-$($platformInstanceId).ps1
            Copy-File $PSScriptRoot\source\platform\$($platformId.ToLower())\postflightupdates-platforminstance-$($platformId.ToLower())-template.ps1 $PSScriptRoot\postflight\postflightupdates-platforminstance-$($platformInstanceId).ps1

            $definitionsServicesUpdated = $false
            foreach ($platformPrerequisiteService in $global:Catalog.Platform.$platformId.Installation.Prerequisites.Service) {
                $platformPrerequisiteServiceFiles = Copy-File $PSScriptRoot\source\services\$($platformPrerequisiteService.ToLower())\services-$($platformPrerequisiteService.ToLower())*.ps1 $PSScriptRoot\services -WhatIf -Quiet
                foreach ($platformPrerequisiteServiceFile in $platformPrerequisiteServiceFiles) {
                    Copy-File $platformPrerequisiteServiceFile.Source $platformPrerequisiteServiceFile.Destination
                    Get-Item $platformPrerequisiteServiceFile.Destination | 
                        Foreach-Object {
                            $contentLine = ". `"`$(`$global:Location.Services)\$($_.Name)`""
                            if (!(Select-String -Path $definitionsServicesFile -Pattern $contentLine -SimpleMatch -Quiet)) {
                                Add-Content -Path $definitionsServicesFile -Value $contentLine
                                $definitionsServicesUpdated = $true
                            }
                        }
                    }
            }
            if ($definitionsServicesUpdated) {
                Write-Host+ -Iff $($definitionsServicesUpdated) -NoTrace -NoTimestamp "  Updated $definitionsServicesFile with platform services." -ForegroundColor DarkGreen
            }

        #endregion PLATFORM
        #region PRODUCT

            foreach ($product in $global:Environ.Product) {
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $PSScriptRoot\install\install-product-$($product.ToLower()).ps1
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\uninstall-product-$($product.ToLower()).ps1 $PSScriptRoot\install\uninstall-product-$($product.ToLower()).ps1
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-product-$($product.ToLower()).ps1
                Copy-File $PSScriptRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $PSScriptRoot\$($product.ToLower()).ps1
            }    

        #endregion PRODUCT             
        #region PROVIDER

            foreach ($provider in $global:Environ.Provider) {
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\install-provider-$($provider.ToLower()).ps1
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\uninstall-provider-$($provider.ToLower()).ps1 $PSScriptRoot\install\uninstall-provider-$($provider.ToLower()).ps1
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $PSScriptRoot\definitions\definitions-provider-$($provider.ToLower()).ps1
                Copy-File $PSScriptRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $PSScriptRoot\providers\provider-$($provider.ToLower()).ps1
            }

        #endregion PROVIDER

    }

    Write-Host+ -MaxBlankLines 1

#endregion FILES
#region CLOUD INSTALL

    if ($cloudInstallUpdate) {

        Write-Host+ -MaxBlankLines 1
        $message = "<Clouds <.>48> INSTALLING"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        Write-Host+

        $message = "  Cloud               Status"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
        $message = "  -----               ------"
        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray            

        $cloudId | ForEach-Object { Install-CatalogObject -Type Cloud -Id $_ -UseDefaultResponses:$UseDefaultResponses }
        
        Write-Host+
        $message = "<Clouds <.>48> INSTALLED"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
        Write-Host+

    }

#endregion CLOUD INSTALL
#region INSTALLER UPDATE

    if ($installUpdate) {

        $installUpdateRestartData = [PSCustomObject]@{
            installUpdateRestart = $true
            productIds = $productIds
            providerIds = $providerIds
            impactedIds = $impactedIds
            impactedProductIds = $impactedProductIds
            impactedProvidverIds = $impactedProviderIds
            disabledProductIds = $disabledProductIds
            impactedProductIdsWithTasks = $impactedProductIdsWithTasks
            impactedProductIdsWithEnabledTasks = $impactedProductIdsWithEnabledTasks
        }  
        
        $installUpdateRestartData | Write-Cache installUpdateRestart

        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace -NoTimestamp "The installer has been updated and must be restarted." -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoTimestamp "This update will not be complete until the installer is rerun." -ForegroundColor DarkYellow
        Write-Host+

        Remove-PSSession+
        
        return
    }

#endregion INSTALLER UPDATE
#region INITIALIZE OVERWATCH

    Write-Host+ -MaxBlankLines 1
    $message = "<Overwatch <.>48> INITIALIZING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    try{
        $global:WriteHostPlusPreference = "SilentlyContinue"
        $global:Product = @{Id="Command"}
        . $PSScriptRoot\definitions.ps1 -MinimumDefinitions
    }
    catch {}
    finally {
        $global:WriteHostPlusPreference = "Continue"
    }

    $message = "$($emptyString.PadLeft(12,"`b"))INITIALIZED "
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

    . $PSScriptRoot\services\services-overwatch-install.ps1

#endregion INITIALIZE OVERWATCH

#region INSTALLER UPDATED

    if ($installUpdateRestart) {
        $installUpdateRestartData = read-cache installUpdateRestart
        $productIds = $installUpdateRestartData.productIds
        $providerIds = $installUpdateRestartData.providerIds
        $impactedIds = $installUpdateRestartData.impactedIds
        $impactedProductIds = $installUpdateRestartData.impactedProductIds
        $impactedProviderIds = $installUpdateRestartData.impactedProviderIds
        $disabledProductIds = $installUpdateRestartData.disabledProductIds
        $impactedProductIdsWithTasks = $installUpdateRestartData.impactedProductIdsWithTasks
        $impactedProductIdsWithEnabledTasks = $installUpdateRestartData.impactedProductIdsWithEnabledTasks
    }

#endregion INSTALLER UPDATED
#region POWERSHELL MODULES-PACKAGES

    if (!$SkipPowerShell) {

        if (Test-Path "$PSScriptRoot\config\config-ps-remoting.ps1") {. "$PSScriptRoot\config\config-ps-remoting.ps1" -ComputerName $env:COMPUTERNAME }

        Set-CursorInVisible
        Write-Host+ -MaxBlankLines 1
        $psStatus = "PENDING"
        $message = "<PowerShell modules/packages <.>48> $psStatus"
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        $psStatusPadLeft = $psStatus.Length + 1
        $newLineClosed = $false

        $psGalleryRepository = Get-PSResourceRepository -Name PSGallery
        if (!$psGalleryRepository) {
            $psGalleryRepository = Register-PSResourceRepository -PSGallery -Trusted -ErrorAction SilentlyContinue
        }
        elseif (!$psGalleryRepository.IsTrusted) {
            $psGalleryRepository = Set-PSResourceRepository -Name PSGallery -Trusted -PassThru
        }

        # if (!(Get-PackageSource -ProviderName PowerShellGet -ErrorAction SilentlyContinue)) {
        #     Register-PackageSource -Name PSGallery -ProviderName PowerShellGet -Trusted -ErrorAction SilentlyContinue | Out-Null
        # }
        if (!(Get-PackageSource -ProviderName NuGet -ErrorAction SilentlyContinue)) {
            Register-PackageSource -Name Nuget -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -Trusted -ErrorAction SilentlyContinue | Out-Null
        }

        $psStatus = "SCANNING"
        $psStatusPadRight =  $psStatusPadLeft-$psStatus.Length -lt 0 ? 0 : $psStatusPadLeft-$psStatus.Length
        $message = "$($emptyString.PadLeft($psStatusPadLeft,"`b")) $psStatus$($emptyString.PadLeft($psStatusPadRight," "))$($emptyString.PadLeft($psStatusPadRight,"`b"))"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine -NoTimeStamp $message -ForegroundColor DarkGray
        $psStatusPadLeft = $psStatus.Length + 1

        # copy catalog object with installation powershell prerequisites
        $psPrerequisites = (Get-Catalog) | Where-Object {$_.IsInstalled() -and $_.Installation.Prerequisites.Type -and $_.Installation.Prerequisites.Type -eq "PowerShell"} | Copy-Object
        # remove all non-powershell prerequisites from copied object
        foreach ($psPrerequisite in $psPrerequisites) {
            $psInstallationPrerequisites = @()
            foreach ($installationPrerequisite in $psPrerequisite.Installation.Prerequisites) {
                if ($installationPrerequisite.Type -eq "PowerShell") {
                    $psInstallationPrerequisites += $installationPrerequisite
                }
            }
            $psPrerequisite.Installation.Prerequisites = $psInstallationPrerequisites
        }

        $psStatus = "PENDING"
        $psStatusPadRight =  $psStatusPadLeft-$psStatus.Length -lt 0 ? 0 : $psStatusPadLeft-$psStatus.Length
        $message = "$($emptyString.PadLeft($psStatusPadLeft,"`b")) $psStatus$($emptyString.PadLeft($psStatusPadRight," "))$($emptyString.PadLeft($psStatusPadRight,"`b"))"
        Write-Host+ -NoTrace -NoSeparator -NoNewLine -NoTimeStamp $message -ForegroundColor DarkGray
        $psStatusPadLeft = $psStatus.Length + 1

        $noop = $true
        foreach ($psPrerequisite in $psPrerequisites) {
            switch ($psPrerequisite.Installation.Prerequisites.Type) {                    
                "PowerShell" {
                    switch ($psPrerequisite.Installation.Prerequisites.$($psPrerequisite.Installation.Prerequisites.Type).Keys[0]) {
                        "Modules" {                             
                            foreach ($prerequisiteModule in $psPrerequisite.Installation.Prerequisites.PowerShell.Modules) {    
                                
                                if (!$newLineClosed) { Write-Host+; $newLineClosed = $true }
                                
                                $moduleStatus = "TESTING"
                                $messageBodyLength = 40
                                $message = "<  $($prerequisiteModule.name) $($prerequisiteModule.RequiredVersion) <.>$messageBodyLength> $moduleStatus"
                                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                                $moduleStatusPadLeft = $moduleStatus.Length + 1

                                $moduleTestResults = Test-Prerequisites -Type $psPrerequisite.Type -Id $psPrerequisite.Id -PrerequisiteType Installation -PrerequisiteFilter "Name -eq `"$($prerequisiteModule.Name)`"" -Quiet
                                $module = $moduleTestResults.Prerequisites.Tests.PowerShell.Modules

                                Start-Sleep -Milliseconds 500
                                $moduleStatus = "PENDING"
                                $moduleStatusPadRight =  $moduleStatusPadLeft-$moduleStatus.Length -lt 0 ? 0 : $moduleStatusPadLeft-$moduleStatus.Length
                                $message = "$($emptyString.PadLeft($moduleStatusPadLeft,"`b")) $moduleStatus$($emptyString.PadLeft($moduleStatusPadRight," "))$($emptyString.PadLeft($moduleStatusPadRight,"`b"))"
                                Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
                                $moduleStatusPadLeft = $moduleStatus.Length + 1

                                if (!$module.IsInstalled -or 
                                    ($module.IsInstalled -and !$module.IsRequiredVersionInstalled) -or 
                                    ($module.IsInstalled -and !$module.IsImported) -or
                                    ($module.IsInstalled -and $module.IsImported -and !$module.isRequiredVersionImported) -and 
                                    (!$module.DoNotImport)) {

                                    if (!$module.isInstalled -or ($module.IsInstalled -and !$module.IsRequiredVersionInstalled)) {
                                        $installedModule = Install-PSResource -Name $module.Name -Version $module.$($module.VersionToInstall) -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                                        $noop = $noop -and $false
                                    }

                                    Start-Sleep -Milliseconds 500
                                    $moduleStatus = "INSTALLED"
                                    $moduleStatusPadRight =  $moduleStatusPadLeft-$moduleStatus.Length -lt 0 ? 0 : $moduleStatusPadLeft-$moduleStatus.Length
                                    $message = "$($emptyString.PadLeft($moduleStatusPadLeft,"`b")) $moduleStatus$($emptyString.PadLeft($moduleStatusPadRight," "))$($emptyString.PadLeft($moduleStatusPadRight,"`b"))"
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                                    $moduleStatusPadLeft = $moduleStatus.Length + 1

                                    if (!$module.DoNotImport) {
                                        
                                        # the module has not been imported
                                        # or, if it was just reinstalled, then reimport
                                        if (!$module.IsImported -or $installedModule) {
                                            $global:InformationPreference = "SilentlyContinue"
                                            Import-Module -Name $module.Name -RequiredVersion $module.$($module.VersionToInstall) -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue 2>$null | Out-Null
                                            $global:InformationPreference = "Continue"
                                            $noop = $noop -and $false
                                        }

                                        Start-Sleep -Milliseconds 500
                                        $moduleStatus = "LOADED"
                                        $moduleStatusPadRight =  $moduleStatusPadLeft-$moduleStatus.Length -lt 0 ? 0 : $moduleStatusPadLeft-$moduleStatus.Length
                                        $message = "$($emptyString.PadLeft($moduleStatusPadLeft,"`b")) $moduleStatus$($emptyString.PadLeft($moduleStatusPadRight," "))$($emptyString.PadLeft($moduleStatusPadRight,"`b"))"
                                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                                        $moduleStatusPadLeft = $moduleStatus.Length + 1
                                    
                                    }

                                    # repeat the last message, but without color this time
                                    Start-Sleep -Milliseconds 500
                                    $moduleStatusPadRight =  $moduleStatusPadLeft-$moduleStatus.Length -lt 0 ? 0 : $moduleStatusPadLeft-$moduleStatus.Length
                                    $message = "$($emptyString.PadLeft($moduleStatusPadLeft,"`b")) $moduleStatus$($emptyString.PadLeft($moduleStatusPadRight," "))$($emptyString.PadLeft($moduleStatusPadRight,"`b"))"
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
                                    $moduleStatusPadLeft = $moduleStatus.Length + 1

                                    Write-Host+ # close the -NoNewLine

                                }
                                else {
                                    # backspace to beginning position
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageBodyLength + $moduleStatusPadLeft,"`b")
                                    # write over previous text with spaces
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageBodyLength + $moduleStatusPadLeft," ")
                                    # backspace to beginning position again in prep for next line of text
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageBodyLength + $moduleStatusPadLeft,"`b")
                                }

                            }
                        }
                        "Packages" {
                            foreach ($prerequisitePackage in $psPrerequisite.Installation.Prerequisites.PowerShell.Packages) {   

                                if (!$newLineClosed) { Write-Host+; $newLineClosed = $true }
                                
                                $packageStatus = "TESTING"
                                $messageBodyLength = 40
                                $message = "<  $($prerequisitePackage.name) $($prerequisitePackage.RequiredVersion) <.>$messageBodyLength> $packageStatus"
                                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray
                                $packageStatusPadLeft = $packageStatus.Length + 1

                                $packageTestResults = Test-Prerequisites -Type $psPrerequisite.Type -Id $psPrerequisite.Id -PrerequisiteType Installation -PrerequisiteFilter "Name -eq `"$($prerequisitePackage.Name)`"" -Quiet
                                $package = $packageTestResults.Prerequisites.Tests.PowerShell.Packages          
                                
                                Start-Sleep -Milliseconds 500
                                $packageStatus = "PENDING"
                                $packageStatusPadRight =  $packageStatusPadLeft-$packageStatus.Length -lt 0 ? 0 : $packageStatusPadLeft-$packageStatus.Length
                                $message = "$($emptyString.PadLeft($packageStatusPadLeft,"`b")) $packageStatus$($emptyString.PadLeft($packageStatusPadRight," "))$($emptyString.PadLeft($packageStatusPadRight,"`b"))"
                                Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
                                $packageStatusPadLeft = $packageStatus.Length + 1

                                if (!$package.IsInstalled -or 
                                    ($package.IsInstalled -and !$package.IsRequiredVersionInstalled)) {

                                    if (!$package.isInstalled -or ($package.IsInstalled -and !$package.IsRequiredVersionInstalled)) {
                                        Install-Package -Name $package.Name -RequiredVersion $package.$($package.VersionToInstall) -SkipDependencies:$package.SkipDependencies -Force -ErrorAction SilentlyContinue | Out-Null
                                        $noop = $noop -and $false
                                    }

                                    Start-Sleep -Milliseconds 500
                                    $packageStatus = "INSTALLED"
                                    $packageStatusPadRight =  $packageStatusPadLeft-$packageStatus.Length -lt 0 ? 0 : $packageStatusPadLeft-$packageStatus.Length
                                    $message = "$($emptyString.PadLeft($packageStatusPadLeft,"`b")) $packageStatus$($emptyString.PadLeft($packageStatusPadRight," "))$($emptyString.PadLeft($packageStatusPadRight,"`b"))"
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                                    $packageStatusPadLeft = $packageStatus.Length + 1

                                    # repeat the last message, but without color this time
                                    Start-Sleep -Milliseconds 500
                                    $packageStatusPadRight =  $packageStatusPadLeft-$packageStatus.Length -lt 0 ? 0 : $packageStatusPadLeft-$packageStatus.Length
                                    $message = "$($emptyString.PadLeft($packageStatusPadLeft,"`b")) $packageStatus$($emptyString.PadLeft($packageStatusPadRight," "))$($emptyString.PadLeft($packageStatusPadRight,"`b"))"
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGray
                                    $packageStatusPadLeft = $packageStatus.Length + 1

                                    Write-Host+ # close the -NoNewLine

                                }
                                else {
                                    # backspace to beginning position
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageBodyLength + $packageStatusPadLeft,"`b")
                                    # write over previous text with spaces
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageBodyLength + $packageStatusPadLeft," ")
                                    # backspace to beginning position again in prep for next line of text
                                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageBodyLength + $packageStatusPadLeft,"`b")
                                }

                            }
                        }
                    }
                }
            }


        }

        $psStatus = "INSTALLED"
        if ($newLineClosed) {
            $message = "<PowerShell modules/packages <.>48> $psStatus"
            Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed ($noop ? 1 : 0) -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
            Write-Host+
        }
        else {
            $psStatusPadRight =  $psStatusPadLeft-$psStatus.Length -lt 0 ? 0 : $psStatusPadLeft-$psStatus.Length
            $message = "$($emptyString.PadLeft($psStatusPadLeft,"`b")) $psStatus$($emptyString.PadLeft($psStatusPadRight," "))$($emptyString.PadLeft($psStatusPadRight,"`b"))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
        Set-CursorVisible

    }

#endregion POWERSHELL MODULES-PACKAGES
#region PYTHON-PACKAGES

    if (!$SkipPython) {
        if ($null -ne $global:Catalog.Platform.$platformId.Installation.Python) {
            if ($requiredPythonPackages) {

                $message = "<Python Packages <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

                Install-PythonPackage -Package $requiredPythonPackages -Pip $pythonPipLocation -ComputerName $platformInstanceNodes -Quiet

                $message = "$($emptyString.PadLeft(10,"`b"))INSTALLED "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen

            }
        }
    }

#region PYTHON-PACKAGES
#region REMOVE CACHE

    if ($installMode -eq "Install" -or $classesFileUpdated) {
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\clusterstatus.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\heartbeat.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platforminfo.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platformstatus.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platformservices.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\platformtopology.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\providers.cache"
        Remove-Files "$PSScriptRoot\data\$($platformInstanceId.ToLower())\products.cache"
    }

#endregion REMOVE CACHE
#region LOCAL ADMIN/RUNAS

    $message = "<Local Admin/RunAs Account <.>48> VALIDATING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray

    if (!(Test-LocalAdmin)) {
        Set-LocalAdmin
        $message = "<Local Admin/RunAs Account <.>48> VALID"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
    }
    else {
        $message = "$($emptyString.PadLeft(10,"`b"))$($emptyString.PadLeft(10," "))$($emptyString.PadLeft(10,"`b"))VALID"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

#endregion LOCAL ADMIN/RUNAS
#region REMOTE DIRECTORIES

    $requiredDirectories = @("data","config")

    $missingDirectories = @()
    foreach ($node in (Get-PlatformTopology nodes -Keys -Online)) {
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
            $_dir = New-Item -ItemType Directory -Path $missingDirectory -Force
            Write-Host+ -NoTrace -NoTimeStamp "Directory: $($_dir.FullName)"
        }

        Write-Host+

    }

#endregion REMOTE DIRECTORIES
#region CONTACTS

    if ($installMode -eq "Install") {
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
#region MAIN

    Set-CursorInvisible

        #region CONFIG

            if (!$SkipPowerShell) {    
                if (Test-Path "$PSScriptRoot\config\config-ps-remoting.ps1") {. "$PSScriptRoot\config\config-ps-remoting.ps1" }
            }

            if (Test-Path "$PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1") {. "$PSScriptRoot\config\config-os-$($operatingSystemId.ToLower()).ps1" }
            if (Test-Path "$PSScriptRoot\config\config-os-$($cloudId.ToLower()).ps1") {. "$PSScriptRoot\config\config-cloud-$($cloudId.ToLower()).ps1" }
            if (Test-Path "$PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1") {. "$PSScriptRoot\config\config-platform-$($platformId.ToLower()).ps1" }
            if (Test-Path "$PSScriptRoot\config\config-platforminstance-$($platformInstanceId.ToLower()).ps1") {. "$PSScriptRoot\config\config-platforminstance-$($platformInstanceId.ToLower()).ps1" }

        #endregion CONFIG
        #region PROVIDERS

            if ($providerIds) {
                    
                Write-Host+ -MaxBlankLines 1
                $message = "<Providers <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Provider            Status"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  --------            ------"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray     

                foreach ($providerId in $providerIds) {
                                                         
                    $cursorVisible = [console]::CursorVisible
                    Set-CursorVisible

                    $message = "  $providerId$($emptyString.PadLeft(20-$providerId.Length," "))","PENDING"
                    $messageLength = $message[0].Length + $message[1].Length
                    Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

                    $prerequisiteFail = @{}
                    try {
                        
                        Install-CatalogObject -Type Provider -Id $providerId -UseDefaultResponses:$UseDefaultResponses

                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageLength,"`b")
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator `
                            "  $providerId$($emptyString.PadLeft(20-$providerId.Length," "))", "INSTALLED" `
                            -ForegroundColor Gray,DarkGreen,Gray,DarkGreen

                    }
                    catch {

                        Write-Host+ -ReverseLineFeed 3
                        $message = "  Provider            Installation        Prerequisite        Status"
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                        $message = "  --------            ------------        ------------        ------"
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray  

                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageLength,"`b")
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator `
                            "  $providerId$($emptyString.PadLeft(20-$providerId.Length," "))", "FAILED$($emptyString.PadLeft(13," "))", `
                            "$($prerequisiteFail.Id)$($emptyString.PadLeft(20-$($prerequisiteFail.Id).Length," "))", "$($prerequisiteFail.Status)" `
                            -ForegroundColor Gray,Red,Gray,Red

                        Uninstall-CatalogObject -Type Provider -Id $providerId -DeleteAllData -Quiet -Force

                    }
                
                    [console]::CursorVisible = $cursorVisible

                }
                
                Write-Host+
                $message = "<Providers <.>48> INSTALLED "
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
                Write-Host+

            }

        #endregion PROVIDERS        
        #region PRODUCTS

            if ($productIds) {

                Write-Host+ -MaxBlankLines 1
                $message = "<Products <.>48> INSTALLING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Product             Status              Task"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  -------             ------              ----"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

                foreach ($productId in $productIds) {

                    $cursorVisible = [console]::CursorVisible
                    Set-CursorVisible

                    try {
                        if ((Get-Catalog -Uid "Product.$productId").HasTask) {

                            $message = "  $productId$($emptyString.PadLeft(20-$productId.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
                            $messageLength = $message[0].Length + $message[1].Length
                            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

                            Install-CatalogObject -Type Product -Id $productId -NoNewLine

                            if ($installMode -eq "Update") {
                                if ("Product.$productId" -notin $disabledProductIDs) {
                                    Enable-Product $productId -NoNewLine
                                }
                                elseif ($installMode -eq "Install") {
                                    Disable-Product $productId -NoNewLine
                                }
                            }
                            # else {
                            #     Write-Host+
                            # }

                        }
                        else {

                            $message = "  $Id$($emptyString.PadLeft(20-$Id.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
                            Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

                            Install-CatalogObject -Type Product -Id $productId -UseDefaultResponses:$UseDefaultResponses

                            $message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))READY$($emptyString.PadLeft(15," "))"
                            Write-Host+ -NoTrace -NoTimeStamp -NoSeparator -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, DarkGreen
                            
                        }
                    }
                    catch {

                        Write-Host+ -ReverseLineFeed 3
                        $message = "  Product             Installation        Task                Prerequisite        Status"
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                        $message = "  -------             ------------        ----                ------------        ------"
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

                        $productTaskStatus = ""
                        if ($global:Catalog.Product.$productId.Installed -and $global:Catalog.Product.$productId.HasTask) {
                            $productTaskStatus = (Get-PlatformTask -Id $productId).Status
                        }

                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $emptyString.PadLeft($messageLength,"`b")
                        Write-Host+ -NoTrace -NoTimestamp -NoSeparator `
                            "  $productId$($emptyString.PadLeft(20-$productId.Length," "))", "FAILED$($emptyString.PadLeft(13," "))", `
                            "$($productTaskStatus.ToUpper())$($emptyString.PadLeft(20-$productTaskStatus.Length," "))" `
                            "$($prerequisiteFail.Id)$($emptyString.PadLeft(20-$($prerequisiteFail.Id).Length," "))", "$($prerequisiteFail.Status)" `
                            -ForegroundColor Gray,Red,Gray,Red

                        Uninstall-CatalogObject -Type Provider -Id $productId -DeleteAllData -Quiet -Force

                    }
                
                    [console]::CursorVisible = $cursorVisible                    

                }

                Write-Host+
                $message = "<Products <.>48> INSTALLED "
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
                Write-Host+

            }

            if ($installMode -eq "Update" -and $impactedProductIdsWithEnabledTasks) {

                Write-Host+ -MaxBlankLines 1
                $message = "<Products <.>48> STARTING"
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
                Write-Host+

                $message = "  Product             Status              Task"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray
                $message = "  -------             ------              ----"
                Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message -ForegroundColor DarkGray

                foreach ($impactedProductIdsWithEnabledTask in $impactedProductIdsWithEnabledTasks) {
                    Enable-Product $impactedProductIdsWithEnabledTask
                }

                Write-Host+
                $message = "<Products <.>48> STARTED "
                Write-Host+ -NoTrace -NoTimestamp -Parse $message -ForegroundColor Blue,DarkGray,DarkGreen
                Write-Host+

            }            

        #endregion PRODUCTS
        #region SAVE SETTINGS

            Update-InstallSettings

        #endregion SAVE SETTINGS
        #region RE-INITIALIZE OVERWATCH

            $message = "<Overwatch <.>48> VERIFYING"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -Parse $message -ForegroundColor Blue,DarkGray,DarkGray
        
            try{
                $global:PreflightPreference = "SilentlyContinue"
                $global:PostflightPreference = "SilentlyContinue"
                $global:WriteHostPlusPreference = "SilentlyContinue"

                $global:Product = @{Id="Command"}
                . $PSScriptRoot\definitions.ps1 -LoadOnly

                $global:WriteHostPlusPreference = "Continue"

                $message = "$($emptyString.PadLeft(9,"`b"))VERIFIED "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
            }
            catch {
                $global:WriteHostPlusPreference = "Continue"

                $message = "$($emptyString.PadLeft(9,"`b"))FAIL     "
                Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkRed
            }
            finally {
                $global:PreflightPreference = "Continue"
                $global:PostflightPreference = "Continue"
            }

            Write-Host+
        
        #endregion RE-INITIALIZE OVERWATCH 
        #region POST-INSTALLATION CONFIG

            Show-PostInstallation

        #endregion POST-INSTALLATION CONFIG
        #region CLEAR INSTALLUPDATERESTART

            clear-cache installUpdateRestart

        #endregion CLEAR INSTALLUPDATERESTART
        #region REMOVE PSSESSIONS

            Remove-PSSession+

        #endregion REMOVE PSSESSIONS

        Write-Host+ -MaxBlankLines 1
        $message = "Overwatch installation is complete."
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor DarkGreen
        Write-Host+

        Write-Host+ -ResetAll

    Set-CursorVisible

#endregion MAIN