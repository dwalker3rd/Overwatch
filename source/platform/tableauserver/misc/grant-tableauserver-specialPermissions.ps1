$levelColors = @("Blue","Cyan","Cyan","Cyan","Cyan","Cyan","Cyan")

function global:Enter-TSProject {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    param(
        [Parameter(Mandatory=$true)][object]$Project,
        # [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$false)][object]$Group,
        [Parameter(Mandatory=$false)][object]$User,
        [Parameter(Mandatory=$true)][object]$Permissions,
        [Parameter(Mandatory=$true)][object]$DefaultPermissions,
        [Parameter(Mandatory=$false)][int]$Level = 0,
        [switch]$WhatIf
    )

    $typeLength = 0
    $hasError = $false

    #set permissions for project
    $capabilities = foreach ($capability in $Permissions) {"$($capability.name):$($capability.mode)"}
    if (!$WhatIf) {
        $response, $responseError = Add-TSProjectPermissions -Project $Project -Group $Group -User $User -Capabilities $capabilities
    }
    else {
        Start-Sleep -Milliseconds 500
    }
    if ($responseError) {
        throw $responseError
    }
    else { 
        $message = " +project"; $typeLength += $message.Length
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
    }

    Start-Sleep -Milliseconds 500
    Write-Host+ -Iff $(!$hasError) -NoTrace -NoTimestamp -NoNewLine "$($emptyString.PadLeft($typeLength,"`b"))$($emptyString.PadLeft($typeLength," "))$($emptyString.PadLeft($typeLength,"`b"))"

    # set default permissions for project
    foreach ($key in $DefaultPermissions.Keys) {
        
        $typeLength = 0
        $hasError = $false

        $type = "$($key)$($key -eq "lens" ? "es" : "s")"

        $capabilities = foreach ($capability in $DefaultPermissions.$key) {"$($capability.name):$($capability.mode)"}
        if (!$WhatIf) {
            $response, $responseError = Add-TSProjectDefaultPermissions -Project $Project -Type $type -Group $Group -User $User -Capabilities $capabilities
        }      
        if ($responseError) {
            # throw $responseError
            $message = " $type"; $typeLength += $message.Length
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkRed
            $hasError = $true
        }
        else { 
            $message = " $type"; $typeLength += $message.Length
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
        }

        $hasContent = $false
        if ($Project.contentPermissions -eq "ManagedByOwner") {

            # $typeLength = 0
            # $hasError = $false
    
            # foreach ($key in $DefaultPermissions.Keys) {
            #     $type = "$($key)$($key -eq "lens" ? "es" : "s")"
                $capabilities = foreach ($capability in $DefaultPermissions.$key) {"$($capability.name):$($capability.mode)"}
                foreach ($contentObject in ((Invoke-Expression "`$global:$type") | Where-Object { !$_.permissions.parent -and $_.location.id -eq $Project.Id })) {
                    $hasContent = $true
                    # if ($typeLength -eq 0) {
                    #     $message = " $($type)"; $typeLength += $message.Length
                    #     Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                    # }
                    if (!$WhatIf) {
                        $response, $responseError = Invoke-Expression "Add-TS$($key)Permissions -$key `$contentObject -Group `$Group -User `$User -Capabilities `$capabilities"
                    }
                    if ($responseError) {
                        # throw $responseError
                        $message = "x"; $typeLength += $message.Length
                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkRed
                        $hasError = $true
                    }
                    else { 
                        $message = "+"; $typeLength += $message.Length
                        Write-Host+ -NoTrace -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen
                    }
                }
            # }
            
        }

        Start-Sleep -Milliseconds 500
        if (!$hasError -and $typeLength -gt 0 -and !$hasContent) {
            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($emptyString.PadLeft($typeLength,"`b"))$($emptyString.PadLeft($typeLength," "))$($emptyString.PadLeft($typeLength,"`b"))"
            $hasError = $false; $typeLength = 0
        }

    }
    # Write-Host+ -Iff $(!$hasError) -NoTrace -NoTimestamp -NoNewLine "$($emptyString.PadLeft($typeLength,"`b"))$($emptyString.PadLeft($typeLength," "))$($emptyString.PadLeft($typeLength,"`b"))"

    Write-Host+ -NoTrace -NoTimestamp

    $Level = $Level + 1
    foreach ($nestedProject in ($global:projects | Where-Object { $_.parentProjectId -eq $Project.id -and $_.name -ne "-Personal Space"})) {
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($nestedProject.name)","[$($nestedProject.contentPermissions)]" -ForegroundColor DarkGray, $levelColors[$Level], DarkGray
        Enter-TSProject -Project $nestedProject -Group $Group -User $User -Permissions $Permissions -DefaultPermissions $DefaultPermissions -Level $Level -WhatIf:$WhatIf
    }

    return

}

function global:Grant-TSSpecialPermissions {

    param(
        # the site contenturl
        [Parameter(Mandatory=$true)][string]$ContentUrl,
        # a group object or name
        [Parameter(Mandatory=$false)][object]$Group, 
         # a user object or name
        [Parameter(Mandatory=$false)][object]$User,
        # the project to use as a template for permissions and defaultPermissions
        [Parameter(Mandatory=$true)][object]$ProjectTemplate,
        [switch]$ShowProgress,
        [switch]$WhatIf
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
    $Permissions = @()
        if ($Group) {
            $Permissions += ($_permissions.granteeCapabilities | where-object {$_.group.id -eq $Group.id}).capabilities
        }
        elseif ($User) {
            $Permissions += ($_permissions.granteeCapabilities | where-object {$_.user.id -eq $User.id}).capabilities
        }

    $Level = 0
    foreach ($parentProject in (($global:projects | Where-Object { $null -eq $_.parentProjectId -and $_.id -ne $_projectTemplate.id -and $_.name -ne "-Personal Space" }))) {
        Write-Host+ -NoTrace -NoTimestamp -NoNewLine "$($global:emptyString.PadLeft(($Level+1) * 4," "))$($Level)>","$($parentProject.name)","[$($parentProject.contentPermissions)]" -ForegroundColor DarkGray, $levelColors[$Level],DarkGray 
        Enter-TSProject -Project $parentProject -User $User -Group $Group -Permissions $Permissions -DefaultPermissions $DefaultPermissions -Level $Level -WhatIf:$WhatIf
    }

    $global:ProgressPreference = $_showProgress

}