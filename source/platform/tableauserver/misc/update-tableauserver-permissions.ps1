$levelColors = @("Blue","Cyan","Cyan","Cyan","Cyan","Cyan","Cyan")

function global:Update-TSProjectPermissions {

    param(
        [Parameter(Mandatory=$true)][Alias("Project","Workbook","Datasource","Flow")][object]$InputObject,
        # [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$true)][object]$Permissions,
        [Parameter(Mandatory=$true)][object]$DefaultPermissions,
        [Parameter(Mandatory=$false)][int]$Level = 0
    )

    # $User = $Grantee.granteeType -eq "User" ? $Grantee : $null
    # $User = $Grantee.granteeType -eq "Group" ? $Grantee : $null

    $typeLength = 0
    $hasError = $false
    switch ($InputObject.type) {

        "Project" {

            foreach ($key in $Permissions.Keys) {
                $permissionsType = "$($key)$($key -eq "lens" ? "es" : "s")"
                $capabilities = foreach ($capability in $Permissions.$key) {"$($capability.name):$($capability.mode)"}
                $response, $responseError = Add-TSProjectPermissions -Project $InputObject -Group $Group -User $User -Capabilities $capabilities
                if ($responseError) {
                    throw $responseError
                }
                else { 
                    $message = " +$permissionsType"; $typeLength += $message.Length
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                }
            }

            foreach ($key in $DefaultPermissions.Keys) {
                $defaultPermissionsType = "$($key)$($key -eq "lens" ? "es" : "s")"
                $capabilities = foreach ($capability in $defaultPermissions.$key) {"$($capability.name):$($capability.mode)"}
                $response, $responseError = Add-TSProjectDefaultPermissions -Project $InputObject -Type $defaultPermissionsType -Group $Group -User $User -Capabilities $capabilities
                if ($responseError) {
                    # throw $responseError
                    $message = " x$defaultPermissionsType"; $typeLength += $message.Length
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkRed
                    $hasError = $true
                }
                else { 
                    $message = " +$defaultPermissionsType"; $typeLength += $message.Length
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                }
            }

        }

    }

    if (!$hasError) {
        Write-Host+ -NoTrace -NoTimestamp "$($emptyString.PadLeft($typeLength,"`b"))$($emptyString.PadLeft($typeLength," "))$($emptyString.PadLeft($typeLength,"`b"))"
    }
    else {
        Write-Host+
    }

    $Level = $Level + 1
    foreach ($nestedProject in ($global:projects | Where-Object { $_.parentProjectId -eq $InputObject.id })) {
        # if ($nestedProject.contentPermissions -ne "LockedToProject") {
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($nestedProject.name)","[$($nestedProject.contentPermissions)]" -ForegroundColor DarkGray, $levelColors[$Level], DarkGray
            Update-TSProjectPermissions -Project $nestedProject -Group $Group -User $User -Permissions $Permissions -DefaultPermissions $DefaultPermissions -Level $Level
        # }
        # else {
        #     Write-Host+ -NoTrace -NoTimestamp "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($nestedProject.name)","[LockedToParent]" -ForegroundColor DarkGray, $levelColors[$Level], DarkGray
        # }
    }

    return

}

function global:Update-TSPermissions {

    param(
        # the site contenturl
        [Parameter(Mandatory=$true)][string]$ContentUrl,
        # a group object or name
        [Parameter(Mandatory=$false)][object]$Group, 
         # a user object or name
        [Parameter(Mandatory=$false)][object]$User,
        # the project to use as a template for permissions and defaultPermissions
        [Parameter(Mandatory=$true)][object]$ProjectTemplate,
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

    # $grantee = $null
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
        # $grantee = $User
        # $grantee | Add-Member -NotePropertyName "granteeType" -NotePropertyValue "User"
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
        # $grantee = $Group
        # $grantee | Add-Member -NotePropertyName "granteeType" -NotePropertyValue "Group"
    }

    # find the project object specified the $ProjectTemplate parameter
    $_projectTemplate = $global:projects | Where-Object { $_.name -eq $ProjectTemplate }
    if (!$_projectTemplate) {
        Write-Host+ -NoTrace -NoTimestamp "[ERROR] The template project `'$ProjectTemplate`' was not found in site `'$($site.contentUrl)`'."  -ForegroundColor Red
        Write-Host+
        return
    }

    # using the $Group or $User object name, get the project's permissions for each exportType
    $_defaultPermissions = $_projectTemplate.permissions.defaultPermissions
    if (!$_defaultPermissions) {
        Write-Host+ -NoTrace -NoTimestamp "[ERROR] `$DefaultPermissions is null." -ForegroundColor Red
        Write-Host+
        return
    }
    $DefaultPermissions = @{}
    foreach ($type in @("workbook","datasource","datarole","lens","flow","metric","database")) {
        if ($Group) {
            $DefaultPermissions += @{"$($type)" = ($_defaultPermissions.$($type).granteeCapabilities | where-object {$_.group.id -eq $Group.id}).capabilities}
        }
        elseif ($User) {
            $DefaultPermissions += @{"$($type)" = ($_defaultPermissions.$($type).granteeCapabilities | where-object {$_.user.id -eq $User.id}).capabilities}
        }
    }

    # using the $Group or $User object name, get the project's permissions for each exportType
    $_permissions = $_projectTemplate.permissions
    if (!$_permissions) {
        Write-Host+ -NoTrace -NoTimestamp "[ERROR] `$permissions is null." -ForegroundColor Red
        Write-Host+
        return
    }
    $Permissions = @{}
    foreach ($type in @("project")) {
        if ($Group) {
            $Permissions += @{"$($type)" = ($_permissions.granteeCapabilities | where-object {$_.group.id -eq $Group.id}).capabilities}
        }
        elseif ($User) {
            $Permissions += @{"$($type)" = ($_permissions.granteeCapabilities | where-object {$_.user.id -eq $User.id}).capabilities}
        }
    }

    $Level = 0
    foreach ($parentProject in ($global:projects | Where-Object { $null -eq $_.parentProjectId -and $_.id -ne $_projectTemplate.id })) {
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($parentProject.name)","[$($parentProject.contentPermissions)]" -ForegroundColor DarkGray, $levelColors[$Level],DarkGray
        # Update-TSPermissions -Project $parentProject -Grantee $grantee -Permissions $Permissions -DefaultPermissions $DefaultPermissions -Level $Level
        Update-TSProjectPermissions -Project $parentProject -User $User -Group $Group -Permissions $Permissions -DefaultPermissions $DefaultPermissions -Level $Level
    }

    $global:ProgressPreference = $_showProgress

}