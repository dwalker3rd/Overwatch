    #region STUBS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    function global:Get-PlatformInfo {

        [CmdletBinding()]
        param (
            [switch]$ResetCache
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Get-PlatformService {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName,
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$ResetCache
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    
    function global:Get-PlatformProcess {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName,
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$ResetCache
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Get-PlatformStatusRollup {

        [CmdletBinding()] param()

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }
        
    function global:Initialize-PlatformTopology {

        [CmdletBinding()] param()
        
        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Start-Platform {

        [CmdletBinding()] param()
        
        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Stop-Platform {

        [CmdletBinding()] param()
        
        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Restart-Platform {

        [CmdletBinding()] param()
        
        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Cleanup-Platform {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
        
        [CmdletBinding()] param()

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Backup-Platform {

        [CmdletBinding()] param()

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Backup-PlatformCallback {
        
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=1)][string]$Id
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Get-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Status,
            [Parameter(Mandatory=$false)][string]$Type,
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$Latest
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Show-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Status,
            [Parameter(Mandatory=$false)][string]$Type,
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$Latest
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Watch-AsyncJob {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Context,
            [Parameter(Mandatory=$false)][string]$Callback,
            [switch]$Add,
            [switch]$Update,
            [switch]$Remove
        )
        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug        
        return
    }

    Set-Alias -Name Write-Watchlist -Value Write-Cache -Scope Global
    Set-Alias -Name Clear-Watchlist -Value Clear-Cache -Scope Global
    Set-Alias -Name Read-Watchlist -Value Read-Cache -Scope Global
    
    function global:Show-Watchlist {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Watchlist,
            [Parameter(Mandatory=$false)][string]$View="Watchlist"
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Update-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false,Position=0)][string]$Id
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Wait-AsyncJob {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id,
            [Parameter(Mandatory=$false)][int]$IntervalSeconds = 15,
            [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 300,
            [Parameter(Mandatory=$false)][int]$ProgressSeconds
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Get-PlatformLicenses {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$View,
            [switch]$ResetCache
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Show-PlatformLicenses {

        [CmdletBinding()] param ()

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    function global:Confirm-PlatformLicenses {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$View
        )

        Write-Host+ -IfDebug -NoTrace -ForegroundColor DarkYellow "DEBUG: $($MyInvocation.MyCommand) is a STUB"
        Write-Host+ -IfDebug
        return
    }

    #endregion STUBS