function global:Get-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        # [Parameter(Mandatory=$false)][object[]]$Session,
        [Parameter(Mandatory=$false)][string]$View
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }
    
    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $groups = @()

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    $groups = Invoke-Command -Session $psSession {
        $group = Get-LocalGroup @using:params -ErrorAction SilentlyContinue 
        $group | Add-Member -NotePropertyName Members -NotePropertyValue (Get-LocalGroupMember -Group $group.Name) -ErrorAction SilentlyContinue
        $group
    }

    foreach ($group in $groups) {
        $group | Add-Member -NotePropertyName ComputerName -NotePropertyValue $group.PSComputerName -ErrorAction SilentlyContinue
    }

    return $groups | Select-Object -Property $($View ? $GroupView.$($View) : $GroupView.Default)

}

function global:New-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    $params = @{};
    if ($Description) {$params += @{Description = $Description}}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        New-LocalGroup -Name $using:Name @using:params
    }

}

function global:Set-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Set-LocalGroup @using:params -Description $using:Description
    }

}

function global:Remove-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    $groups = Get-LocalGroup+ @params -ComputerName $ComputerName -Session $psSession

    $hasMembers = $false
    foreach ($group in $Groups) {
        if ($group.Members.Count -gt 0) {
            $hasMembers = $true
            Write-Host+ -NoTrace -NoTimestamp "    $($group.PSComputerName) > $($group.Name) > $($group.Members.Count) member[s]" -ForegroundColor DarkGray
        }
    }
    if ($hasMembers) {
        Write-Host+ -NoTrace -NoTimestamp "  You must remove the members from local group `"$($group.Name)`" before it can be deleted." -ForegroundColor Red 
        return
    }
    else {
        return Invoke-Command -Session $psSession {
            Remove-LocalGroup @using:params
        }
    }

}

function global:Get-LocalUser+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        # [Parameter(Mandatory=$false)][object[]]$Session,
        [Parameter(Mandatory=$false)][string]$View

    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name } }
    if ($SID) { $params += @{ SID = $SID } }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    $localUser = Invoke-Command -Session $psSession {
        Get-LocalUser @using:params -ErrorAction SilentlyContinue
    }
    $localUser | Add-Member -NotePropertyName "Username" -NotePropertyValue "$($localUser.PSComputerName.ToUpper())\$($localUser.Name)"

    return $localUser

}

function global:New-LocalUser+ {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Password,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][boolean]$PasswordNeverExpires=$false,
        [Parameter(Mandatory=$false)][boolean]$UserMayNotChangePassword=$false,   
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    $params = @{};
    if ($FullName) {$params += @{FullName = $FullName}}
    if ($Description) {$params += @{Description = $Description}}
    if ($Password) {
        $params += @{Password = ConvertTo-SecureString -String $Password -AsPlainText -Force}
        $params += @{PasswordNeverExpires = $PasswordNeverExpires}
        $params += @{UserMayNotChangePassword = $UserMayNotChangePassword}
    }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        New-LocalUser -Name $using:Name @using:params
    }

}

function global:Set-LocalUser+ {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string]$Password,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][boolean]$PasswordNeverExpires,
        # [Parameter(Mandatory=$false)][boolean]$UserMayNotChangePassword,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}
    if ($FullName) {$params += @{FullName = $FullName}}
    if ($Description) {$params += @{Description = $Description}}
    if ($Password) {
        $params += @{Password = ConvertTo-SecureString -String $Password -AsPlainText -Force}
        $params += @{PasswordNeverExpires = $PasswordNeverExpires}
        # $params += @{UserMayNotChangePassword = $UserMayNotChangePassword}
    }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Set-LocalUser @using:params
    }

}

function global:Remove-LocalUser+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Remove-LocalUser @using:params
    }

}

function global:Add-LocalGroupMember+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string]$Member,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Add-LocalGroupMember @using:params -Member $using:Member
    }

}

function global:Remove-LocalGroupMember+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$SID,
        [Parameter(Mandatory=$false)][string]$Member,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    if (!$Name -and !$SID) {
        throw "Either `$Name or `$SID must be specified."
    }
    if ($Name -and $SID) {
        throw "Either `$Name or `$SID must be specified but not both."
    }

    $params = @{}
    if ($Name) { $params += @{ Name = $Name }}
    if ($SID) { $params += @{ SID = $SID }}

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    return Invoke-Command -Session $psSession {
        Remove-LocalGroupMember @using:params -Member $using:Member -ErrorAction SilentlyContinue
    }

}