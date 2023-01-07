    function Export-TSObject {

        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline)][Object[]]$InputObject,
            [Parameter(Mandatory=$true,Position=0)][ValidateSet("Server","Site")][string]$Type,
            [Parameter(Mandatory=$true,Position=1)][string]$Name,
            [Parameter(Mandatory=$false)][ValidateSet("json")][string]$Format = "json"
        )

        begin {

            $exportDirectory = switch ($Type) {
                "Server" {
                    "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\.$Format"
                }
                "Site" {
                    $contentUrl = ![string]::IsNullOrEmpty($global:tsRestApiConfig.ContentUrl) ? $global:tsRestApiConfig.ContentUrl : "default"
                    "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentURL\.$Format"
                }
            }
            if (!(Test-Path -Path $exportDirectory -PathType Container)) { New-Item -ItemType Directory -Path $exportDirectory | Out-Null }

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
                    $exportObject = $outputObject | ConvertFrom-XmlElement | ConvertTo-Json -Depth 10
                }
            }
            Set-Content -Path $outFile -Value $exportObject -Force
        
        }

    }

    function Write-Start {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Name,
            [switch]$NewLine
        )

        $message = "<Export $Name <.>48> PENDING"
        Write-Host+ -NoTrace -NoNewLine:$(!($NewLine.IsPresent)) -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

    }

    function Write-End {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Name,
            [switch]$NewLine
        )

        if ($NewLine) {
            $message = "<Export $Name <.>48> SUCCESS"
            Write-Host+ -NoTrace -Parse $message-ForegroundColor Gray,DarkGray,DarkGreen
        }
        else {
            $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
            Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
        }
    }

    function global:Export-Content {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

        [CmdletBinding()]
        param ()

        Write-Host+ -ResetAll

        Write-Host+ -NoTrace -NoTimestamp "Export for Tableau Server"

        do {
            $defaultServerSiteResponse = "site"
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "Export server or site?","[$defaultServerSiteResponse]: " -ForegroundColor Gray,Blue
            $exportServerSiteResponse = Read-Host
            $exportServerSiteResponse = ![string]::IsNullOrEmpty($exportServerSiteResponse) ? $exportServerSiteResponse : $defaultServerSiteResponse
            if ($exportServerSiteResponse -notin ("Server","Site")) { 
                Write-Host+ -NoTrace -NoTimestamp "Response must be `"Server`" or `"Site`"" -ForegroundColor Red
            }
        } until ($exportServerSiteResponse -in ("Server","Site"))

        $defaultServerResponse = $global:tsRestApiConfig.Server
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "Server","[$defaultServerResponse]",": " -ForegroundColor Gray,Blue,Gray
        $server = Read-Host
        $server = ![string]::IsNullOrEmpty($server) ? $server : $defaultServerResponse

        $contentUrl = ""
        if ($exportServerSiteResponse -eq "Site") {
            $defaultContentUrlResponse = $global:tsRestApiConfig.ContentUrl
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "ContentUrl","[$defaultContentUrlResponse]",": " -ForegroundColor Gray,Blue,Gray
            $contentUrl = Read-Host
            $contentUrl = ![string]::IsNullOrEmpty($contentUrl) ? $contentUrl : $defaultContentUrlResponse
        }

        $defaultCredentialsNameResponse = $exportServerSiteResponse -eq "Server" ? "localadmin-$($Platform.Instance)" : $null
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "Credentials","[$defaultCredentialsNameResponse]",": " -ForegroundColor Gray,Blue,Gray
        $credentialsName = Read-Host
        $credentialsName = ![string]::IsNullOrEmpty($credentialsName) ? $credentialsName : $defaultCredentialsNameResponse

        try {
            Initialize-TSRestApiConfiguration -Server $server -ContentUrl $contentUrl -Credentials $credentialsName
        }
        catch {
            throw "Invalid server, site or credentials."
        }

        switch ($exportServerSiteResponse) {
            "Server" { 
                Export-TSServer
            }
            "Site" {
                Export-TSSite 
            }
        }


    }

function global:Export-TSServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = $global:tsRestApiConfig.Server,
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)"
    )

    # is the server export/download directory locked?
    if (Test-Path "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\inuse.lock") {

        $inuseMeta = Get-Content "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\inuse.lock"
        $inuseDateTime = ($inuseMeta.Split(","))[0]
        $inuseUsername = ($inuseMeta.Split(","))[1]
        
        Write-Host+ -NoTrace -NoTimestamp "The server export directory has been in use by $inuseUsername since $inuseDateTime" -ForegroundColor DarkYellow
        return

    }

    # is any site's export/downlaod directory locked?
    foreach ($site in Get-TSSites) {
        if (Test-Path "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$($site.contentUrl)\inuse.lock") {

            $inuseMeta = Get-Content "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$($site.contentUrl)\inuse.lock"
            $inuseDateTime = ($inuseMeta.Split(","))[0]
            $inuseUsername = ($inuseMeta.Split(","))[1]
            
            Write-Host+ -NoTrace -NoTimestamp "The site export directory for the site `"$($site.contentUrl)`" has been in use by $inuseUsername since $inuseDateTime" -ForegroundColor DarkYellow
            return

        }
    }

    try {

        # remove all files from the server's export/download directory
        Remove-Item "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\*" -Recurse -Force -ErrorAction SilentlyContinue

        # set the server lock file with the current datetime and user
        Set-Content "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\inuse.lock" -Value "$([datetime]::Now.ToString('u')), $($env:USERNAME)"

        Write-Host+ -ResetAll
        Write-Host+
        Write-Host+ -NoTrace "Server: $($global:tsRestApiConfig.Platform.Uri.Host) ($($global:tsRestApiConfig.Platform.Name))"

        Write-Host+ -SetIndentGlobal +2

        Write-Start serverInfo
        $serverInfo = Get-TSServerInfo
        $serverInfo | Export-TSObject Server serverInfo
        Write-End serverInfo

        Write-Start sites
        $sites = Get-TSSites
        $sites | Export-TSObject Server sites
        Write-End sites

        Write-Host+ -SetIndentGlobal -2

        foreach ($site in $sites) { Export-TSSite $site.contentUrl }

    }
    catch {}
    finally {
        # remove the server's export/download directory lock file
        Remove-Item "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\inuse.lock" -force
    }

}

function global:Export-TSSite {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][Alias("Site")][string]$ContentUrl = $global:tsRestApiConfig.ContentUrl
    )

    $callStack = Get-PSCallStack
    $caller = $callstack[1] ? ($callstack[1].FunctionName -eq "<ScriptBlock>" ? "" : $callstack[1].FunctionName.replace('global:','')) : ""
    if ($caller -ne "Export-TSServer") {

        # is the server's export/download directory locked?
        if (Test-Path "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\inuse.lock") {

            $inuseMeta = Get-Content "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\inuse.lock"
            $inuseDateTime = ($inuseMeta.Split(","))[0]
            $inuseUsername = ($inuseMeta.Split(","))[1]
            
            Write-Host+ -NoTrace -NoTimestamp "The server export directory has been in use by $inuseUsername since $inuseDateTime" -ForegroundColor DarkYellow
            return

        }
    
    }

    # is this site's export/download directory locked?
    if (Test-Path "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$(![string]::IsNullOrEmpty($ContentUrl) ? $ContentUrl : "default")\inuse.lock") {

        $inuseMeta = Get-Content "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$ContentUrl\inuse.lock"
        $inuseDateTime = ($inuseMeta.Split(","))[0]
        $inuseUsername = ($inuseMeta.Split(","))[1]
        
        Write-Host+ -NoTrace -NoTimestamp "The site export directory for this site, `"$ContentUrl`", has been in use by $inuseUsername since $inuseDateTime" -ForegroundColor DarkYellow
        return

    }

    try {

        # remove all files from this site's download/export directory
        Remove-Item "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$ContentUrl\*" -Recurse -Force -ErrorAction SilentlyContinue

        # set this site's export/download directory's lock file with current datetime and user
        if (!(Test-Path "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$ContentUrl")) { New-Item -ItemType Directory -Path "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$ContentUrl" | Out-Null }
        Set-Content "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$ContentUrl\inuse.lock" -Value "$([datetime]::Now.ToString('u')), $($env:USERNAME)"
        
        Write-Host+ -MaxBlankLines 1
        Write-Host+ -NoTrace "Site: $(![string]::IsNullOrEmpty($ContentUrl) ? $ContentUrl : "default")"
        Write-Host+ -SetIndentGlobal +2

        Switch-TSSite -ContentUrl $ContentUrl

        Write-Start site
        $site = Get-TSSite
        $site | Export-TSObject Site site
        Write-End site
        
        Write-Start users
        $users = Get-TSUsers+
        $users | Export-TSObject Site users
        Write-End users
        
        Write-Start groups
        $groups = Get-TSGroups+
        $groups | Export-TSObject Site groups
        Write-End groups

        Write-Start projects
        $projects = Get-TSProjects+
        $projects | Export-TSObject Site projects
        Write-End projects

        Write-Start workbooks
        $workbooks = Get-TSWorkbooks+ -Users $Users -Groups $Groups -Projects $Projects -Download
        $workbooks | Export-TSObject Site workbooks
        Write-End workbooks

        Write-Start wiews
        $views = Get-TSViews+  -Users $Users -Groups $Groups -Projects $Projects -Workbooks $workbooks
        $views | Export-TSObject Site views
        Write-End views

        Write-Start datasources
        $datasources = Get-TSDatasources+ -Users $Users -Groups $Groups -Projects $Projects -Download
        $datasources | Export-TSObject Site datasources
        Write-End datasources

        Write-Start flows
        $flows = Get-TSFlows+ -Users $Users -Groups $Groups -Projects $Projects -Download
        $flows | Export-TSObject Site flows
        Write-End flows

        Write-Start metrics
        $metrics = Get-TSMetrics
        $metrics | Export-TSObject Site metrics
        Write-End metrics

        Write-Start favorites
        $favorites = Get-TSFavorites
        $favorites | Export-TSObject Site favorites
        Write-End favorites

        Write-Start subscriptions
        $subscriptions = Get-TSSubscriptions
        $subscriptions | Export-TSObject Site subscriptions
        Write-End subscriptions

        Write-Start schedules
        $schedules = Get-TSSchedules 
        $schedules | Export-TSObject Site schedules
        Write-End schedules

        Write-Start dataAlerts
        $dataAlerts = Get-TSDataAlerts
        $dataAlerts | Export-TSObject Site dataAlerts
        Write-End dataAlerts
        
        Write-Host+ -SetIndentGlobal -2
        Write-Host+
    }
    catch {}
    finally {

        # remove this site's export/download directory lock file
        Remove-Item "$($global:Location.Root)\data\$($tsRestApiConfig.Platform.Instance)\.export\$ContentUrl\inuse.lock" -force

    }
}
