    $script:exporttypes = @{
        server = @(
            "serverInfo","sites"
        )
        site = @(
            "site","users","groups","projects",
            "projectDefaultPermissions",
            "workbooks",
            "views","datasources","flows","metrics","favorites",
            "subscriptions","schedules","dataAlerts"
        )
    }
    $script:plusTypes = @("users","groups","projects","projectDefaultPermissions","workbooks","views","datasources","flows")
    $script:typesRequiringUsers = @("projects","projectDefaultPermissions","workbooks","views","datasources","flows")
    $script:typesRequiringGroups = @("projects","projectDefaultPermissions","workbooks","views","datasources","flows")
    $script:typesRequiringProjects = @("projectDefaultPermissions","workbooks","views","datasources","flows")
    $script:downloadTypes = @("workbooks","datasources","flows")
    $script:showProgressTypes = @("users","groups","projects","workbooks","views","datasources","flows")
    
    function Write-Start {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Action,
            [Parameter(Mandatory=$true)][string]$Type,
            [switch]$NewLine
        )

        $script:WriteEndNewLine = $NewLine

        $actionMessage = "    $Action "
        $actionMessageLength = 42 - $actionMessage.Length
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $actionMessage -ForegroundColor DarkGray
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine:$(!$NewLine) -Parse "<$Type <.>$($actionMessageLength)> PENDING" -ForegroundColor DarkBlue,DarkGray,DarkGray

    }

    function Write-End {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)][string]$Action,
            [Parameter(Mandatory=$true)][string]$Type,
            [Parameter(Mandatory=$false)][string]$Status = "SUCCESS",
            [switch]$NewLine
        )

        if ($script:WriteEndNewLine) {
            $NewLine = $true
            $script:WriteEndNewLine = $false
        }

        $statusColor = 
            switch ($Status) {
                "FAILED" { "Red" }
                default { "Green" }
            }

        if ($NewLine) {
            $actionMessage = "    $Action "
            $actionMessageLength = 42 - $actionMessage.Length
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine -ReverseLineFeed 1 -EraseLine $actionMessage -ForegroundColor DarkGray
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine:$(!$NewLine)  -Parse "<$Type <.>$($actionMessageLength)> $Status " -ForegroundColor DarkBlue,DarkGray,$statusColor
        }
        else {
            $statusMessage = "$($emptyString.PadLeft(8,"`b")) $status"
            Write-Host+ -NoTrace -NoTimeStamp $statusMessage -ForegroundColor $statusColor
        }
    }

    function Get-ServerUri {

        param(
            [Parameter(Mandatory=$false)][object]$Server
        )

        $uri = $Server
        try { invoke-webrequest $uri -Method Head | Out-Null }
        catch {
            try {
                $uri = "https://$($Server)"
                invoke-webrequest $uri -Method Head | Out-Null
            }
            catch { return }
        }
        return [uri]$uri

    }

    function Lock-ExportDirectory {

        param(
            [Parameter(Mandatory=$true,Position=0)][ValidateSet("Server","Site")][string]$Target
        )
        
        $lockFile = switch ($Target) {
            "Server" { $serverLockFile }
            "Site" { $siteLockFile }
        }
        
        Set-Content $lockFile -Value "$([datetime]::Now.ToString('u')), $($env:USERNAME)"
    
    }
    function Lock-Site { Lock-ExportDirectory Site }
    function Lock-Server { Lock-ExportDirectory Server }

    function Unlock-ExportDirectory {
    
        param(
            [Parameter(Mandatory=$true,Position=0)][ValidateSet("Server","Site")][string]$Target
        )
    
        $lockFile = switch ($Target) {
            "Server" { $serverLockFile }
            "Site" { $siteLockFile }
        }
    
        Remove-Item $lockFile -Force
    
    }
    function Unlock-Site { Unlock-ExportDirectory Site }
    function Unlock-Server { Unlock-ExportDirectory Server }

    function IsServerLocked {

        param()

        if (Test-Path $serverLockFile) {
            $inUseMeta = Get-Content $serverLockFile
            $inUseDateTime = ($inUseMeta.Split(","))[0]
            $inUseUsername = ($inUseMeta.Split(","))[1]
            if ($inUseUsername -ne $ENV:USERNAME) {
                Write-Host+ -NoTrace -NoTimestamp "[$inUseDateTime] Server $( $global:tsrestApiConfig.Server) locked by $inUseUsername." -ForegroundColor DarkYellow
                return $true
            }
        }
        return $false

    }

    function IsAnySiteLocked {

        param()

        $isAnySiteLocked = $false
        foreach ($site in $global:sites) {
            $siteLockFile = "$exportDirectory\$($Site.contentUrl)\inUse.lock"
            if (Test-Path $siteLockFile) {
                $inUseMeta = Get-Content $siteLockFile
                $inUseDateTime = ($inUseMeta.Split(","))[0]
                $inUseUsername = ($inUseMeta.Split(","))[1]
                if ($inUseUsername -ne $ENV:USERNAME) {
                    Write-Host+ -NoTrace -NoTimestamp "[$inUseDateTime] Site $($site.contentUrl) locked by $inUseUsername." -ForegroundColor DarkYellow
                    $isAnySiteLocked = $true
                }
            }
        }
        return $isAnySiteLocked

    }

    function Get-TSObjects+ {

        param()

        $_showProgress = $global:ProgressPreference
        if ($ShowProgress) {
            $global:ProgressPreference = "Continue"
        }

        foreach ($exportType in ($script:exportTypes.server + $Script:exportTypes.site)) {

            Write-Start -Action "Get" -Type $exportType

            $exportTypeTitleCase = "$($exportType[0].ToString().ToUpper())$($exportType.SubString(1,$exportType.Length-1))"
            $getTSObjectsExpression = "Get-TS$($exportTypeTitleCase)$($exportType -in $plusTypes ? "+" : $null) "
            $getTSObjectsExpression += $exportType -in $typesRequiringUsers ? "-Users `$global:Users " : $null
            $getTSObjectsExpression += $exportType -in $typesRequiringGroups ? "-Groups `$global:Groups " : $null
            $getTSObjectsExpression += $exportType -in $typesRequiringProjects ? "-Projects `$global:Projects " : $null
            $getTSObjectsExpression += $exportType -in $showProgressTypes ? "-ShowProgress " : $null

            try {
                if ($exportType -in $showProgressTypes) {
                    Write-Host+ -SetIndentGlobal 8
                    Write-Host+; Write-Host+
                }
                
                Set-Variable -Scope Global -Name $exportType -Value (Invoke-Expression $getTSObjectsExpression)
                
                if ($exportType -in $showProgressTypes) {
                    Write-Host+ -ResetIndentGlobal
                }
            }
            catch {}
            finally {
                Write-Host+ -ResetIndentGlobal
            }   

            Invoke-Expression "`$global:$exportType" | Write-Cache "$($global:Platform.Instance)-$exportType" 

            Write-End -Action "Get" -Type $exportType
        }

        $global:ProgressPreference = $_showProgress

    }

    function Restore-TSObjects {

        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
        param ()

        function Restore-TSObject {
            param(
                [Parameter(Mandatory=$false,Position=0)][string]$Type
            )
            $status = "RESTORED"
            Write-Start -Action "Restore" -Type $Type
            if ((Get-Cache "$($global:Platform.Instance)-$Type").Exists) {
                Set-Variable -Scope Global -Name $Type -Value (Read-Cache "$($global:Platform.Instance)-$Type")
            }
            else {
                $status = "NOCACHE"
            }
            Write-End -Action "Restore" -Type $Type -Status $status
        }
    
        foreach ($exportType in ($script:exportTypes.server + $Script:exportTypes.site)) {
            Restore-TSObject $exportType
        }

    }

    function global:Export-TSObject {

        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline)][Object[]]$InputObject,
            [Parameter(Mandatory=$true,Position=1)][string]$Name,
            [Parameter(Mandatory=$false)][ValidateSet("json")][string]$Format = "json"
        )

        begin {
            $outFile = "$exportDirectory\$Name.$Format"
            $outputObject = @()
        }
        process {
            $outputObject += $InputObject 
        }
        end {
            if (!$outputObject) { return }
            switch ($Format) {
                default {
                    $exportObject = $outputObject | ConvertTo-Json -Depth 10
                }
            }
            Set-Content -Path $outFile -Value $exportObject -Force
        }
    }

    function Download-TSSiteContent {

        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

        Param (
            [Parameter(Mandatory=$true,Position=1)][string]$Type
        )

        $contentUrl = (Get-TSSite).contentUrl
        $exportDirectory = "$($global:Location.Data)\$($global:Platform.Instance)\.export\$contentUrl\"

        if (!(Test-Path -Path $exportDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $exportDirectory | Out-Null
        }

        $objects = (Invoke-Expression "`$global:$Type")[0..2]

        $count = 1
        foreach ($object in $objects) {

            $downloadStatus = "SUCCEEDED"

            $objectId = $object.Id
            $objectName = $object.Name
            $objectType = $Type -replace '^(.*)s$','$1'

            $response = Download-TSObject -Method "Get$objectType" -InputObject $object
            if ($response.error) {
                $errorMessage = "Error $($response.error.code) ($($response.error.summary)): $($response.error.detail)"
                Write-Log -Message $errorMessage -EntryType "Error" -Action $Method -Status "Error"
                $object | Add-Member -NotePropertyName "error" -NotePropertyValue ($response | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
                $downloadStatus = "FAILED"
            }
            else {
                $object | Add-Member -NotePropertyName "outFile" -NotePropertyValue $response.outFile -ErrorAction SilentlyContinue
            }

            $_objectPath = $null
            if (!$object.outFile) { throw "$($response.outFile) is null." }
            $objectPath = $object.outFile -replace [System.Text.RegularExpressions.Regex]::Escape($exportDirectory), ""
            Write-Host+ -NoTrace -NoTimeStamp -ReverseLineFeed 1 -EraseLineToCursor "        [$count/$($objects.Count)] $objectPath" -ForegroundColor DarkGray

            $count++

        }

        Write-Host+ -NoTrace -NoTimeStamp -ReverseLineFeed 2 -EraseLineToCursor

    }

    function Export-TSServer {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$Server =  $global:tsrestApiConfig.Server,
            [switch]$Restore,
            [switch]$Refresh
        )

        if (IsServerLocked) { return }
        if (IsAnySiteLocked) { return }

        try {

            $script:exportDirectory = "$($global:Location.Data)\$($global:Platform.Instance)\.export\"
            $script:serverLockFile = "$exportDirectory\inUse.lock"

            # remove all files from the server's export/download directory
            # Remove-Item "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\*" -Recurse -Force -ErrorAction SilentlyContinue

            Lock-Server

            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp "Server:","$($global:Platform.Instance)" -ForegroundColor DarkGray,DarkBlue
            Write-Host+

            if ($Refresh) {
                Get-TSObjects+
            }
            elseif ($Restore) {
                Restore-TSObjects
            }

            foreach ($exportType in $exportTypes.server) {
                Write-Start -Action "Export" -Type $exportType
                Invoke-Expression "`$global:$($exportType)" | Export-TSObject Server $exportType
                Write-End -Action "Export" -Type $exportType
            }

            foreach ($site in $global:sites) {
                Export-TSSite $site.contentUrl
            }

        }
        catch {}
        finally {
            Unlock-Server
        }

    }

    function Export-TSSite {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][object]$Server =  $global:tsrestApiConfig.Server,
            [Parameter(Mandatory=$true,Position=0)][object]$Site,
            [switch]$Restore,
            [switch]$Refresh
        )

        $_server = $Server
        $script:Server = Get-ServerUri $Server
        if (!$script:Server) {
            throw "'$_server' is not a valid uri or uri.host"
        }

        $contentUrl = switch ($Site.GetType()) {
            "object" { $Site.ContentUrl }
            "string" { $Site }
        }
        if ($contentUrl -in $global:Sites.contentUrl) {
            throw "'$Site' is not a valid site for server '$script:Server'."
        }

        Switch-TSSite -ContentUrl $contentUrl
        # call Get-TSSite to get the proper case for the contentUrl
        $contentUrl = (Get-TSSite).contentUrl 

        if (IsServerLocked) { return }
        if (IsAnySiteLocked) { return }

        try {

            $script:exportDirectory
            $script:exportDirectory = "$($global:Location.Data)\$($global:Platform.Instance)\.export\$contentUrl"
            $script:siteLockFile = "$exportDirectory\inUse.lock"

            # # remove all files from this site's download/export directory
            # Remove-Item "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$contentUrl\*" -Recurse -Force -ErrorAction SilentlyContinue

            # set this site's export/download directory's lock file with current datetime and user
            if (!(Test-Path $exportDirectory)) { New-Item -ItemType Directory -Path $exportDirectory | Out-Null }

            Lock-Site $Site
            
            Write-Host+
            Write-Host+ -NoTrace -NoTimestamp "Site:","$(![string]::IsNullOrEmpty($contentUrl) ? $contentUrl : "default")" -ForegroundColor DarkGray,DarkBlue
            Write-Host+
                    
            if ($Refresh) {
                Get-TSObjects+ Site
            }
            elseif ($Restore) {
                Restore-TSObjects Site
            }

            foreach ($exportType in $exportTypes.site) {
                $objectCount = (Invoke-Expression "`$global:$($exportType)").Count
                Write-Start -Action "Export" -Type $exportType -NewLine:$($exportType -in $downloadTypes)
                if ($objectCount -gt 0) {
                    Invoke-Expression "`$global:$($exportType)" | Export-TSObject site $exportType
                    if ($downloadTypes -contains $exportType) {
                        Write-Host+
                        Download-TSContent Site $exportType
                    }
                }
                Write-End -Action "Export" -Type $exportType -Status "Exported"
            }
        
            Write-Host+

        }
        catch {}
        finally {

            Unlock-Site

        }
    }