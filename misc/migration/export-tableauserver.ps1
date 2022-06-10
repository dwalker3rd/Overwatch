function Export-TSObjectAsJson {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][Object[]]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name,
        [switch]$Server,
        [switch]$Site
    )

    begin {

        $exportFormat = "json"

        if (!$Server -and !$Site) {
            throw "`$Server or `$Site must be specified"
        }

        $exportDirectory = 
            if ($Server) {
                "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\.$exportFormat"
            }
            elseif ($Site) {
                $contentUrl = ![string]::IsNullOrEmpty($global:tsRestApiConfig.ContentUrl) ? $global:tsRestApiConfig.ContentUrl : "default"
                "$($global:Location.Root)\Data\$($global:tsRestApiConfig.Platform.Instance)\.export\$contentURL\.$exportFormat"
            }
        if (!(Test-Path -Path $exportDirectory -PathType Container)) { New-Item -ItemType Directory -Path $exportDirectory | Out-Null }

        $outFile = "$exportDirectory\$Name.$exportformat"

        $outputObject = @()

    }
    process {

        $outputObject += $InputObject 
    
    }
    end {

        if (!$outputObject) { return }
    
        $json = $outputObject | ConvertFrom-XmlElement | ConvertTo-Json -Depth 10
        Set-Content -Path $outFile -Value $json -Force
    
    }

}

function Export-TSSiteObject {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][Object[]]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name
    )

    begin {
        $outputObject = @()
    }
    process {
        $outputObject += $InputObject 
    }
    end {
        $outputObject | Export-TSObjectAsJson -Name $Name -Site
    }

}

function Export-TSServerObject {

    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][Object[]]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name
    )

    begin {
        $outputObject = @()
    }
    process {
        $outputObject += $InputObject 
    }
    end {
        $outputObject | Export-TSObjectAsJson -Name $Name -Server
    }

}

function Write-Start {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    $message = "Export $Name : PENDING"
    Write-Host+ -NoTrace -NoNewLine:$(!($NewLine.IsPresent)) $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray -NoSeparator

}

function Write-End {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    if ($NewLine) {
        $message = "Export $Name : SUCCESS"
        Write-Host+ -NoTrace $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGreen -NoSeparator
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
        [Parameter(Mandatory=$false)][Alias("Site")][string]$ContentUrl = "",
        [Parameter(Mandatory=$false)][string]$Credentials = "localadmin-$($Platform.Instance)"
    )

    Initialize-TSRestApiConfiguration -Server $Server -ContentUrl $ContentUrl -Credentials $Credentials

    Write-Host+ -ResetIndentGlobal
    Write-Host+
    Write-Host+ -NoTrace "Server: $($global:tsRestApiConfig.Platform.Uri.Host) ($($global:tsRestApiConfig.Platform.Name))"

    Write-Host+ -SetIndentGlobal -Indent 2

    Write-Start serverInfo
    $serverInfo = Get-TSServerInfo
    $serverInfo | Export-TSServerObject -Name server
    Write-End serverInfo

    Write-Start sites
    $sites = Get-TSSites
    $sites | Export-TSServerObject -Name sites
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
    $site | Export-TSSiteObject -Name site
    Write-End site
    
    Write-Start users
    $users = Get-TSUsers+
    $users | Export-TSSiteObject -Name users
    Write-End users
    
    Write-Start groups
    $groups = Get-TSGroups+
    $groups | Export-TSSiteObject -Name groups
    Write-End groups

    Write-Start projects
    $projects = Get-TSProjects+ -Users $Users -Groups $Groups
    $projects | Export-TSSiteObject -Name projects
    Write-End projects

    Write-Start workbooks
    $workbooks = Get-TSWorkbooks+ -Users $Users -Groups $Groups -Projects $Projects -Download
    $workbooks | Export-TSSiteObject -Name workbooks
    Write-End workbooks

    Write-Start wiews
    $views = Get-TSViews+  -Users $Users -Groups $Groups -Projects $Projects -Workbooks $workbooks
    $views | Export-TSSiteObject -Name views
    Write-End views

    Write-Start datasources
    $datasources = Get-TSDatasources+ -Users $Users -Groups $Groups -Projects $Projects -Download
    $datasources | Export-TSSiteObject -Name datasources
    Write-End datasources

    Write-Start flows
    $flows = Get-TSFlows+ -Users $Users -Groups $Groups -Projects $Projects -Download
    $flows | Export-TSSiteObject -Name flows
    Write-End flows

    Write-Start metrics
    $metrics = Get-TSMetrics
    $metrics | Export-TSSiteObject -Name metrics
    Write-End metrics

    Write-Start favorites
    $favorites = Get-TSFavorites
    $favorites | Export-TSSiteObject -Name favorites
    Write-End favorites

    Write-Start subscriptions
    $subscriptions = Get-TSSubscriptions
    $subscriptions | Export-TSSiteObject -Name subscriptions
    Write-End subscriptions

    Write-Start schedules
    $schedules = Get-TSSchedules 
    $schedules | Export-TSSiteObject -Name schedules
    Write-End schedules

    Write-Start dataAlerts
    $dataAlerts = Get-TSDataAlerts
    $dataAlerts | Export-TSSiteObject -Name dataAlerts
    Write-End dataAlerts

}
