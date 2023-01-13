[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

param(
    [Parameter(Mandatory=$true)][Alias("site")][string]$contentUrl
)

function Write-Start {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    $message = "<$Name <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine:$(!($NewLine.IsPresent)) -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

}

function Write-End {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    if ($NewLine) {
        $message = "<$Name <.>48> SUCCESS"
        Write-Host+ -NoTrace -Parse $message-ForegroundColor Gray,DarkGray,DarkGreen
    }
    else {
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }
}

Connect-TableauServer -Site $contentUrl

Write-Host+ -ResetAll
Write-Host+ -NoTrace "Site: $(![string]::IsNullOrEmpty($ContentUrl) ? $ContentUrl : "default")"
Write-Host+ -SetIndentGlobal +2

Write-Start Site
$site = Get-TSSite
Write-End Site

Write-Start Users
$users = Get-TSUsers+
Write-End Users

Write-Start Groups
$groups = Get-TSGroups+
Write-End Groups

Write-Start Projects
$projects = Get-TSProjects+ -Users $users -Groups $groups
Write-End Projects

Write-Start Workbooks
$workbooks = Get-TSWorkbooks+ -Users $users -Groups $groups -Projects $projects
Write-End Workbooks

Write-Start Views
$views = Get-TSViews+  -Users $users -Groups $groups -Projects $projects -Workbooks $workbooks
Write-End Views

Write-Start Datasources
$datasources = Get-TSDatasources+ -Users $users -Groups $groups -Projects $projects
Write-End Datasources

Write-Start Flows
$flows = Get-TSFlows+ -Users $users -Groups $groups -Projects $projects
Write-End Flows

Write-Start Metrics
$metrics = Get-TSMetrics
Write-End Metrics

Write-Start Collections
$collections = $null # Get-TSCollections
Write-End Collections

Write-Start Favorites
$favorites = Get-TSFavorites+ -Users $users -Projects $projects -Workbooks $workbooks -views $views -Datasources $datasources -Flows $flows -Metrics $metrics -Collections $collections
Write-End Favorites

Write-Start Subscriptions
$subscriptions = Get-TSSubscriptions
Write-End Subscriptions

Write-Start Schedules
$schedules = Get-TSSchedules
Write-End Schedules

Write-Start DataAlerts
$dataAlerts = Get-TSDataAlerts
Write-End DataAlerts

Write-Host+ -SetIndentGlobal -2
Write-Host+