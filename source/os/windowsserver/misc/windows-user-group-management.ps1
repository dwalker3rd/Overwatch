function global:Get-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    $groups = Invoke-Command -Session $psSession {
        $group = Get-LocalGroup @using:params -ErrorAction SilentlyContinue 
        $group | Add-Member -NotePropertyName Members -NotePropertyValue (Get-LocalGroupMember -Group $group.Name) -ErrorAction SilentlyContinue
        $group
    }

    foreach ($group in $groups) {
        $group | Add-Member -NotePropertyName ComputerName -NotePropertyValue $group.PSComputerName -ErrorAction SilentlyContinue
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return $groups | Select-Object -Property $($View ? $GroupView.$($View) : $GroupView.Default)

}

function global:New-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
        # [Parameter(Mandatory=$false)][object[]]$Session
    )

    $params = @{};
    if ($Description) {$params += @{Description = $Description}}

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        New-LocalGroup -Name $using:Name @using:params
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return #Get-LocalGroup+ -Name $Name -ComputerName $ComputerName

}

function global:Set-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Set-LocalGroup @using:params -Description $using:Description
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return Get-LocalGroup+ @params -ComputerName $ComputerName -View Min

}

function global:Remove-LocalGroup+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

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
    }
    else {
        Invoke-Command -Session $psSession {
            Remove-LocalGroup @using:params
        }
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return

}

function global:Get-LocalUser+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Get-LocalUser @using:params -ErrorAction SilentlyContinue
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return

}

function global:New-LocalUser+ {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        New-LocalUser -Name $using:Name @using:params
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return Get-LocalUser+ -Name $Name -ComputerName $ComputerName

}

function global:Set-LocalUser+ {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Set-LocalUser @params
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return Get-LocalUser+ @params -ComputerName $ComputerName

}

function global:Remove-LocalUser+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Remove-LocalUser -Name $using:params
    }

    Remove-PsSession $psSession

    return Get-LocalUser+ @params -ComputerName $ComputerName

}

function global:Add-LocalGroupMember+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Add-LocalGroupMember @using:params -Member $using:Member
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return Get-LocalGroup+ @params -ComputerName $ComputerName -View Min

}

function global:Remove-LocalGroupMember+ {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Name,
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

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Remove-LocalGroupMember @using:params -Member $using:Member -ErrorAction SilentlyContinue
    }

    # if (!$Session) {Remove-PSSession $psSession}
    Remove-PsSession $psSession

    return Get-LocalGroup+ @params -ComputerName $ComputerName -View Min

}