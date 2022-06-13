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
    Write-Host+ -NoTrace -NoNewLine:$(!($NewLine.IsPresent)) -Parse $message -ForegroundColor Gray,DarkGray,DarkGray -NoSeparator

}

function Write-End {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    if ($NewLine) {
        $message = "<Export $Name <.>48> SUCCESS"
        Write-Host+ -NoTrace -Parse $message-ForegroundColor Gray,DarkGray,DarkGreen -NoSeparator
    }
    else {
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }

}

function global:Export-TSServer {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Server = "localhost",
        [Parameter(Mandatory=$false)][Alias("Site")][string]$ContentUrl = "*",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)"
    )

    $exportAllSites = $ContentUrl -eq "*"
    if ($exportAllSites -or (Get-Culture).TextInfo.ToTitleCase($ContentUrl) -eq "Default") {$ContentUrl = ""}

    Initialize-TSRestApiConfiguration -Server $Server -ContentUrl $ContentUrl -Credentials $Credentials

    Write-Host+ -ResetAll
    Write-Host+
    Write-Host+ -NoTrace "Server: $($global:tsRestApiConfig.Platform.Uri.Host) ($($global:tsRestApiConfig.Platform.Name))"

    Write-Host+ -SetIndentGlobal -Indent 2

    Write-Start serverInfo
    $serverInfo = Get-TSServerInfo
    $serverInfo | Export-TSObject Server serverInfo
    Write-End serverInfo

    Write-Start sites
    $sites = $exportAllSites ? (Get-TSSites) : (Get-TSSite)
    $sites | Export-TSObject Server sites
    Write-End sites

    Write-Host+ -SetIndentGlobal -Indent -2

    foreach ($site in $sites) {

        Write-Host+
        Write-Host+ -NoTrace "Site: $(![string]::IsNullOrEmpty($site.contentUrl) ? $site.contentUrl : "default")"

        Write-Host+ -SetIndentGlobal -Indent 2

        Switch-TSSite -ContentUrl $site.contentUrl
        Export-TSSite
        
        Write-Host+ -SetIndentGlobal -Indent -2
    }

}

function global:Export-TSSite {

    [CmdletBinding()]
    param()
    
    # $users = Get-TSUsers+
    # $groups = Get-TSGroups+
    # $projects = Get-TSProjects+ -Users $Users -Groups $Groups

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
    $projects = Get-TSProjects+ -Users $Users -Groups $Groups
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

}
