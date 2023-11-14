function global:Get-User {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string]$View

    )

    $psSession = New-PSSession+ -ComputerName $ComputerName

    $users = Invoke-Command -Session $psSession {
        Get-LocalUser -Name $using:Name
    }

    Remove-PSSession+

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

    $psSession = New-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Write-Host+ -IfVerbose "Creating new user '$using:Name' on node '$($psSession.$ComputerName)'" -ForegroundColor DarkYellow
        New-LocalUser -Name $using:Name @using:params
    }

    Remove-PSSession+

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

    $psSession = New-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Set-LocalUser -Name $using:Name @using:params
        Write-Host+ -IfVerbose "Updated properties for user '$using:Name' on node '$($psSession.$ComputerName)'" -ForegroundColor DarkYellow
    }

    Remove-PSSession+

}

function global:Add-UserToGroup {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$Group,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $psSession = New-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        foreach ($g in $using:Group) {
            Add-LocalGroupMember -Group $g -Member $using:Name 
            Write-Host+ -IfVerbose "Added user '$using:Name' to local group '$using:Group' on node '$($psSession.$ComputerName)'" -ForegroundColor DarkYellow
        }
    }

    Remove-PSSession+

}

function global:Remove-UserFromGroup {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower(),
        [Parameter(Mandatory=$false)][string[]]$Group
    )

    $psSession = New-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        $using:Group | Foreach-Object { Remove-LocalGroupMember -Group $_ -Member $using:Name }
        Write-Host+ -IfVerbose "Removed user '$using:Name' to local group '$using:Group' on node '$($psSession.$ComputerName)'" -ForegroundColor DarkYellow
    }

    Remove-PSSession+

}

function global:Remove-User {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME.ToLower()
    )

    $psSession = New-PSSession+ -ComputerName $ComputerName

    Invoke-Command -Session $psSession {
        Remove-LocalUser -Name $using:Name
        Write-Host+ -IfVerbose "Removed user '$using:Name' on node '$($psSession.$ComputerName)'" -ForegroundColor DarkYellow
    }

    Remove-PSSession+
}