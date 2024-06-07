param(
    [Parameter(Mandatory=$true)][string]$ContentUrl,
    [Parameter(Mandatory=$false)][object]$Group,
    [Parameter(Mandatory=$false)][string]$User,
    [Parameter(Mandatory=$true)][object]$ProjectAsDefaultPermissionsTemplate
)

function Write-Start {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    $message = "<$Name <.>48> PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine:$(!($NewLine.IsPresent)) -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

}

function Write-End {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    if ($NewLine) {
        $message = "<$Name <.>48> SUCCESS"
        Write-Host+ -NoTrace -NoTimestamp -Parse $message-ForegroundColor Gray,DarkGray,DarkGreen
    }
    else {
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen
    }
}

function Cache-TSServerObjects {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    Param ()

    Write-Start site
    $script:site = Get-TSSite
    # $script:site | Write-Cache tableau-path-org-site
    Write-End site

    Write-Start users
    $script:users = Get-TSusers
    # $script:users | Write-Cache tableau-path-org-users
    Write-End users

    Write-Start groups
    $script:groups = Get-TSgroups
    # $script:groups | Write-Cache tableau-path-org-groups
    Write-End groups

    Write-Start projects+ -NewLine
    $script:projects = Get-TSProjects+ -Groups $script:groups -Users $script:users
    # $script:projects | Write-Cache tableau-path-org-projects
    Write-End projects+

    Write-Start projectDefaultPermissions+
    $script:projectsDefaultPermissions = Get-TSProjectDefaultPermissions+ -Projects $script:projects -Groups $script:groups -Users $script:users
    # $script:projectDefaultPermissions | Write-Cache tableau-path-org-projectDefaultPermissions
    Write-End projectDefaultPermissions+

    # Write-Start workbooks+
    # $script:workbooks = Get-TSWorkbooks+ -users $script:users -groups $script:groups -projects $script:projects
    # $script:workbooks | Write-Cache tableau-path-org-workbooks
    # Write-End workbooks+

    # Write-Start datasources+
    # $script:datasources = Get-TSDatasources+ -users $script:users -groups $script:groups -projects $script:projects
    # $script:datasources | Write-Cache tableau-path-org-datasources
    # Write-End datasources+

    # Write-Start flows+
    # $script:flows = Get-TSFlows+ -Users $script:users -Groups $script:groups -Projects $script:projects -Download
    # $script:flows | Export-CSV -Path "$($exportPath)\flows.csv"
    # Write-End flows+

    # Write-Start metrics
    # $script:metrics = Get-TSMetrics
    # $script:metrics | Export-CSV -Path "$($exportPath)\metrics.csv"
    # Write-End metrics

    # Write-Start favorites
    # $script:favorites = Get-TSFavorites
    # $script:favorites | Export-CSV -Path "$($exportPath)\favorites.csv"
    # Write-End favorites

    # Write-Start subscriptions
    # $script:subscriptions = Get-TSSubscriptions
    # $script:subscriptions | Export-CSV -Path "$($exportPath)\subscriptions.csv"
    # Write-End subscriptions

    # Write-Start schedules
    # $script:schedules = Get-TSSchedules 
    # $script:schedules | Export-CSV -Path "$($exportPath)\schedules.csv"
    # Write-End schedules

    # Write-Start dataAlerts
    # $script:dataAlerts = Get-TSDataAlerts
    # $script:dataAlerts | Export-CSV -Path "$($exportPath)\dataAlerts.csv"
    # Write-End dataAlerts

}

function Update-TSProject {

    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$true)][object]$Permissions,
        [Parameter(Mandatory=$false)][int]$Level = 0
    )

    # if (!($Group -or $User) -or ($Group -and $User)) {
    #     throw "Must specify either Group or User"
    # }

    foreach ($key in $Permissions.Keys) {
        $type = "$($key)$($key -eq "lens" ? "es" : "s")"
        $capabilities = foreach ($capability in $Permissions.$key) {"$($capability.name):$($capability.mode)"}
        $response, $responseError = Add-TSProjectDefaultPermissions -Project $Project -Type $type -Group $Group -User $User -Capabilities $capabilities
        if ($responseError) {
            throw $responseError
        }
        else { 
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine " +$type" -ForegroundColor DarkGray
        }
    }

    Write-Host+ # close NoNewLine

    $Level = $Level + 1
    foreach ($nestedProject in ($script:projects | Where-Object { $_.parentProjectId -eq $Project.id })) {
        if ($nestedProject.contentPermissions -ne "LockedToProject") {
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft($Level * 4," "))$($nestedProject.name)"
            Update-TSProject -Project $nestedProject -Group $Group -User $User -Permissions $Permissions -Level $Level
        }
    }

    return

}

#region MAIN

    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "Must specify either Group or User"
    }

    $_user = $null
    if (![string]::IsNullOrEmpty($User)) {
        $_user = $script:users | Where-Object {$_.name -eq $User}
    }
    $_group = $null
    if (![string]::IsNullOrEmpty($Group)) {
        $_group = $script:groups | Where-Object {$_.name -eq $Group}
    }

    $_projectDefaultPermissions = $projectDefaultPermissions | Where-Object {$_.workbook.project.name -eq $ProjectAsDefaultPermissionsTemplate}

    $_permissions = @{}
    foreach ($type in @("workbook","datasource","datarole","lens","flow","metric","database")) {
        $_permissions += @{"$($type)" = ($_projectDefaultPermissions.$($type).granteeCapabilities | where-object {$_.group.id -eq $_group.id}).capabilities.capability}
    }

    Connect-TableauServer -Site $ContentUrl
    # Cache-TSServerObjects

    Write-Host+ -NoTrace -NoTimestamp -LineFeed 2 "site: $($site.contentUrl)"

    $_level = 0
    foreach ($parentProject in ($script:projects | Where-Object { $null -eq $_.parentProjectId })) {
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft($Level * 4," "))$($parentProject.name)"
        Update-TSProject -Project $parentProject -Group $_group -User $_user -Permissions $_permissions -Level $_level
    }

#endregion MAIN