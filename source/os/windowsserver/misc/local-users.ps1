function global:Get-User {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string]$View

    )

    $users = @()

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Get-LocalUser -Name $using:Name -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Name = $_.Name
                Enabled = $_.Enabled
                Description = $_.Description 
                Groups = foreach ($group in (get-localgroup)) {
                            if (get-localgroupmember -Member $using:Name -Group $group.Name -erroraction silentlycontinue) {
                                $group.Name
                            }
                        }
            }
        }
    }


    return $users | Select-Object -Property $($View ? $UserView.$($View) : $UserView.Default)
}

function global:New-User {

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

    Invoke-Command -Session $psSession {
        New-LocalUser -Name $using:Name @using:params
    }

}

function global:Set-User {

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Password,
        [Parameter(Mandatory=$false)][string]$FullName,
        [Parameter(Mandatory=$false)][string]$Description,
        [Parameter(Mandatory=$false)][boolean]$PasswordNeverExpires,
        [Parameter(Mandatory=$false)][boolean]$UserMayNotChangePassword,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $params = @{};
    if ($FullName) {$params += @{FullName = $FullName}}
    if ($Description) {$params += @{Description = $Description}}
    if ($Password) {
        $params += @{Password = ConvertTo-SecureString -String $Password -AsPlainText -Force}
        $params += @{PasswordNeverExpires = $PasswordNeverExpires}
        # $params += @{UserMayNotChangePassword = $UserMayNotChangePassword}
    }

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Set-LocalUser -Name $using:Name @using:params
    }

}

function global:Add-UserToGroup {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$Group,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        foreach ($g in $using:Group) {
            Add-LocalGroupMember -Group $g -Member $using:Name 
        }
    }

}

function global:Remove-UserFromGroup {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string[]]$Group
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        $using:Group | Foreach-Object { Remove-LocalGroupMember -Group $_ -Member $using:Name }
    }

}

function global:Remove-User {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $psSession = Use-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Remove-LocalUser -Name $using:Name
    }

    return
}