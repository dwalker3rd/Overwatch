$levelColors = @("Blue","Cyan","Cyan","Cyan","Cyan","Cyan","Cyan")

function Write-Start {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [switch]$NewLine
    )

    $message = "<    $Name <.>36> PENDING"
    Write-Host+ -NoTrace -NoTimestamp -NoNewLine:$(!($NewLine.IsPresent)) -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

}

function Write-End {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Status = ($Refresh ? "REFRESHED" : ($Restore ? "RESTORED" : "REUSING")),
        [switch]$NewLine
    )

    $statusColor = 
        switch ($Status) {
            "FAILED" { "Red" }
            default { "DarkGreen" }
        }

    if ($NewLine) {
        $message = "<    $Name <.>36> $status"
        Write-Host+ -NoTrace -NoTimestamp -ReverseLineFeed 1 -Parse $message -ForegroundColor DarkBlue,DarkGray,$statusColor
    }
    else {
        $message = "$($emptyString.PadLeft(8,"`b")) $status$($emptyString.PadLeft(8," "))"
        Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor $statusColor
    }
}

function global:Get-TSServerObjects {

    Param ()

    Write-Start site
    $global:site = Get-TSSite 
    $global:site | Write-Cache "$($global:Platform.Instance)-site" 
    Write-End site

    Write-Start users
    $global:users = Get-TSUsers
    $global:users | Write-Cache "$($global:Platform.Instance)-users"
    Write-End users

    Write-Start groups
    $global:groups = Get-TSGroups
    $global:groups | Write-Cache "$($global:Platform.Instance)-groups"
    Write-End groups

    Write-Start projects+ -NewLine
    Write-Host+ -SetIndentGlobal 8
    $global:projects = Get-TSProjects+ -Groups $global:groups -Users $global:users
    $global:projects | Write-Cache "$($global:Platform.Instance)-projects"
    Write-Host+ -ResetIndentGlobal
    Write-End projects+ -NewLine

    Write-Start projectsDefaultPermissions+
    $global:projectsDefaultPermissions = Get-TSProjectDefaultPermissions+ -Projects $global:projects -Groups $global:groups -Users $global:users
    $global:projectsDefaultPermissions | Write-Cache "$($global:Platform.Instance)-projectsDefaultPermissions"
    Write-End projectsDefaultPermissions+

    Write-Start workbooks+
    $global:workbooks = Get-TSWorkbooks+ -users $global:users -groups $global:groups -projects $global:projects
    $global:workbooks | Write-Cache "$($global:Platform.Instance)-workbooks"
    Write-End workbooks+

    Write-Start datasources+
    $global:datasources = Get-TSDatasources+ -users $global:users -groups $global:groups -projects $global:projects
    $global:datasources | Write-Cache "$($global:Platform.Instance)-datasources"
    Write-End datasources+

    Write-Start flows+
    $global:flows = Get-TSFlows+ -Users $global:users -Groups $global:groups -Projects $global:projects
    $global:flows | Write-Cache "$($global:Platform.Instance)-flows"
    Write-End flows+

    Write-Start metrics
    $global:metrics = Get-TSMetrics
    $global:metrics | Write-Cache "$($global:Platform.Instance)-metrics"
    Write-End metrics

    Write-Start favorites
    $global:favorites = Get-TSFavorites
    $global:favorites | Write-Cache "$($global:Platform.Instance)-favorites"
    Write-End favorites

    Write-Start subscriptions
    $global:subscriptions = Get-TSSubscriptions
    $global:subscriptions | Write-Cache "$($global:Platform.Instance)-subscriptions"
    Write-End subscriptions

    Write-Start schedules
    $global:schedules = Get-TSSchedules
    $global:schedules | Write-Cache "$($global:Platform.Instance)-schedules"
    Write-End schedules

    Write-Start dataAlerts
    $global:dataAlerts = Get-TSDataAlerts
    $global:dataAlerts | Write-Cache "$($global:Platform.Instance)-dataAlerts"
    Write-End dataAlerts

    Write-Host+

}

function global:Restore-TSServerObjects {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    Param ()

    function Restore-Cache {

        param(
            [Parameter(Mandatory=$false)][string]$Type
        )

        Write-Start $Type
        $status = $Refresh ? "REFRESHED" : ($Restore ? "RESTORED" : "REUSING")
        if ((Get-Cache "$($global:Platform.Instance)-$Type").Exists) {
            $tsObject = Read-Cache "$($global:Platform.Instance)-$Type"
        }
        else {
            $status = "FAILED"
        }
        Write-End $Type -Status $status

        return $tsObject

    }

    $global:site = Restore-Cache site
    $global:users = Restore-Cache users
    $global:groups = Restore-Cache groups
    $global:projects = Restore-Cache projects
    $global:projectsDefaultPermissions = Restore-Cache projectsDefaultPermissions
    $global:workbooks = Restore-Cache workbooks
    $global:datasources = Restore-Cache datasources
    $global:flows = Restore-Cache flows
    $global:metrics = Restore-Cache metrics
    $global:favorites = Restore-Cache favorites
    $global:subscriptions = Restore-Cache subscriptions
    $global:schedules = Restore-Cache schedules
    $global:dataAlerts = Restore-Cache dataAlerts

    Write-Host+

}

function global:Update-TSProjectDefaultPermissions {

    param(
        [Parameter(Mandatory=$true)][object]$Project,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$true)][object]$Permissions,
        [Parameter(Mandatory=$false)][int]$Level = 0
    )

    $typeLength = 0

    foreach ($key in $Permissions.Keys) {
        $type = "$($key)$($key -eq "lens" ? "es" : "s")"
        $capabilities = foreach ($capability in $Permissions.$key) {"$($capability.name):$($capability.mode)"}
        $response, $responseError = Add-TSProjectDefaultPermissions -Project $Project -Type $type -Group $Group -User $User -Capabilities $capabilities
        if ($responseError) {
            throw $responseError
        }
        else { 
            $typeMessage = " +$type"; $typeLength += $typeMessage.Length
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine $typeMessage -ForegroundColor DarkGreen
        }
    }

    Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($emptyString.PadLeft($typeLength,"`b"))$($emptyString.PadLeft($typeLength," "))$($emptyString.PadLeft($typeLength,"`b"))"
    Write-Host+

    $Level = $Level + 1
    foreach ($nestedProject in ($global:projects | Where-Object { $_.parentProjectId -eq $Project.id })) {
        if ($nestedProject.contentPermissions -ne "LockedToProject") {
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($nestedProject.name)","[$($nestedProject.contentPermissions)]" -ForegroundColor DarkGray, $levelColors[$Level], DarkGray
            Update-TSProjectDefaultPermissions -Project $nestedProject -Group $Group -User $User -Permissions $Permissions -Level $Level
        }
        else {
            Write-Host+ -NoTrace -NoTimestamp "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($nestedProject.name)","[LockedToParent]" -ForegroundColor DarkGray, $levelColors[$Level], DarkGray
        }
    }

    return

}

function global:Set-ProjectDefaultPermissions {

    param(
        # the site contenturl
        [Parameter(Mandatory=$true)][string]$ContentUrl,
        # a group object or name
        [Parameter(Mandatory=$false)][object]$Group, 
         # a user object or name
        [Parameter(Mandatory=$false)][object]$User,
        # a default permissions object or the project name to use as a template
        [Parameter(Mandatory=$true)][object]$DefaultPermissions, 
        [switch]$Restore,
        [switch]$Refresh,
        [switch]$ShowProgress
    )

    if ($Refresh -and $Restore) {
        throw "The switches `$Refresh and `$Restore cannot be used together."
    }
    if (!($Group -or $User) -or ($Group -and $User)) {
        throw "A group or a user must be specified."
    }

    $_showProgress = $global:ProgressPreference
    if ($ShowProgress) {
        $global:ProgressPreference = "Continue"
    }

    Write-Host+ -ResetIndentGlobal
    
    Write-Host+

    Connect-TableauServer -Site $ContentUrl
    Write-Host+ -NoTrace -NoTimestamp "Server:","$($global:Platform.Uri.Host)" -ForegroundColor DarkGray,DarkBlue
    Write-Host+ -NoTrace -NoTimestamp "Site:","$($site.contentUrl)" -ForegroundColor DarkGray,DarkBlue

    Write-Host+

    if ($Refresh) {
        Get-TSServerObjects
    }
    elseif ($Restore) {
        Restore-TSServerObjects
    }
    else {
    }

    # if $User is type [string], then find the user object by name
    if ($null -ne $User -and $User.GetType() -eq [string]) {
        if (![string]::IsNullOrEmpty($User)) {
            $_user = $global:users | Where-Object {$_.name -eq $User}
            if (!$_user) {
                Write-Host+ -NoTrace -NoTimestamp "[ERROR] The user `'$User`' was not found in site `'$($site.contentUrl)`'." -ForegroundColor Red
                Write-Host+
                return
            }
            $User = $_user
        }
    }

    # if $Group is type [string], then find the Group object by name
    if ($null -ne $Group -and $Group.GetType() -eq [string]) {
        if (![string]::IsNullOrEmpty($Group)) {
            $_group = $global:groups | Where-Object {$_.name -eq $Group}
            if (!$_group) {
                Write-Host+ -NoTrace -NoTimestamp "[ERROR] The group `'$Group`' was not found in site `'$($site.contentUrl)`'." -ForegroundColor Red
                Write-Host+
                return 
            }
            $Group = $_group
        }
    }

    # if $DefaultPermissions is type [string], then it's a project name
    # find the project object and then, using the $Group or $User object name, get the default permissions for each type
    if ($DefaultPermissions.GetType() -eq [string]) {
        $_defaultPermissions = $projectsDefaultPermissions | Where-Object {$_.workbook.project.name -eq $DefaultPermissions}
        if (!$_defaultPermissions) {
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] `$DefaultPermissions is null." -ForegroundColor Red
            Write-Host+ -NoTrace -NoTimestamp "[ERROR] The template project `'$DefaultPermissions`' was not found in site `'$($site.contentUrl)`'."  -ForegroundColor Red
            Write-Host+
            return
        }
        $DefaultPermissions = @{}
        foreach ($type in @("workbook","datasource","datarole","lens","flow","metric","database")) {
            if ($Group) {
                $DefaultPermissions += @{"$($type)" = ($_defaultPermissions.$($type).granteeCapabilities | where-object {$_.group.id -eq $Group.id}).capabilities.capability}
            }
            elseif ($User) {
                $DefaultPermissions += @{"$($type)" = ($_defaultPermissions.$($type).granteeCapabilities | where-object {$_.user.id -eq $User.id}).capabilities.capability}
            }
        }
    }

    $Level = 0
    foreach ($parentProject in ($global:projects | Where-Object { $null -eq $_.parentProjectId })) {
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($parentProject.name)","[$($parentProject.contentPermissions)]" -ForegroundColor DarkGray, $levelColors[$Level], DarkGray
        Update-TSProjectDefaultPermissions -Project $parentProject -Group $Group -User $User -Permissions $DefaultPermissions -Level $Level
    }

    $global:ProgressPreference = $_showProgress

}