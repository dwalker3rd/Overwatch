[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12,[System.Net.SecurityProtocolType]::Tls11  

#region OVERWATCH

    function global:Get-Overwatch {

        [CmdletBinding()] 
        param ()

        return $global:Overwatch

    }

    function global:Get-Environ {

        [CmdletBinding()] 
        param ()

        return $global:Environ

    }

    function global:Get-OS {

        [CmdletBinding()] 
        param ()

        return $global:OS

    }

    function global:Get-Platform {

        [CmdletBinding()] 
        param ()

        return $global:Platform

    }

    function global:Get-Product {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [switch]$ResetCache
        )

        $definitionPath = "$($global:Location.Definitions)\definitions"

        $products = $null
        if (!$ResetCache) {
            if ($(get-cache products).Exists()) {
                $products = Read-Cache products #-MaxAge $(New-Timespan -Minutes 2)
            }
        }

        # persist $global:Product
        $productClone = $global:Product ? $($global:Product | Copy-Object) : $null

        # this method overwrites $global:Product so clone $global:Product
        if (!$products) {
            $products = @()
            $global:Environ.Product | ForEach-Object {
                if (Test-Path -Path $definitionPath-product-$($_).ps1) {
                    $products += . $definitionPath-product-$($_).ps1
                }
            }

            for ($i = 0; $i -lt $products.Count; $i++) {
                $products[$i].IsInstalled = $global:Environ.Product -contains $products[$i].Id
            }
            Write-Cache products -InputObject $products
        }

        if ($Name) {$products = $products | Where-Object {$_.Name -eq $Name}}
        if ($Id) {$products = $products | Where-Object {$_.Id -eq $Id}}

        # reset $global:Product with clone
        $global:Product = $productClone

        return $products
    }

    $global:logLockObject = $false

<#     
    function global:Test-IsProductLocked {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][ValidateCount(1,2)][string[]]$Name,
            [switch]$Silent
        )

        $waitInterval = [timespan]::Zero
        $writeLockMessages = $Silent ? $false : $true

        [console]::CursorVisible = $false

        $thisProduct = Read-Cache $Name[0]
        if (!$thisProduct) {
            $thisProduct = @{
                Name=$Name[0]
                Host = $HOST.Name
                PID = $PID
                Class = "Process"
                LockState = "Unknown"
                StartTime = $null
                EndTime = $null
                LastRunTime = $null
            }
        }
        # $thisProductPropertiesAsString = $thisProduct | Select-Object -ExcludeProperty Task | ConvertTo-Json -Compress

        $selfLocked = $thisProduct.LockState -eq "Locked" ? $thisProduct.PID -eq $PID : $false
        $locked = $thisProduct.LockState -eq "Locked" ? !$selfLocked : $false

        $lock = @{
            Locked = $locked ? "Locked" : "Unlocked"
            SelfLocked = $selfLocked ? "Locked" : "Unlocked"
            Product = @()
        }
        $lock.Product += @{
            Name = $thisProduct.Name
            Locked = $locked ? "Locked" : "Unlocked"
            SelfLocked = $selfLocked ? "Locked" : "Unlocked"
        }

        # Write-Log -Context $thisProduct.Name -Action "IsProductLocked" -Target $thisProduct.Name -Message ($global:logLockObject ? $thisProductPropertiesAsString : $null) -Status $thisProduct.LockState -EntryType "Warning" -Force

        $message = "$($thisProduct.Name) : $($thisProduct.LockState)"
        Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,$($thisProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen") 
        if ($locked) {   
            $message = "  Host : $($thisProduct.Host)"
            Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
            $message = "  PID .: $($thisProduct.PID)"
            Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
        }

        if ($Name.Count -gt 1) {

            $thatProduct = Read-Cache $Name[1]
            if (!$thatProduct) {
                $thatProduct = @{
                    Name = $Name[1]
                    Host = $HOST.Name
                    PID = $PID
                    Class = "Process"
                    LockState = "Unknown"
                    StartTime = $null
                    EndTime = $null
                    LastRunTime = $null
                }
            }
            # $thatProductPropertiesAsString = $thatProduct | Select-Object -ExcludeProperty Task | ConvertTo-Json -Compress
            $thatProductInit = $thatProduct | Copy-Object

            $thatProductSelfLocked = $thatProduct.LockState -eq "Locked" ? $thatProduct.PID -eq $PID : $false
            $thatProductLocked = $thatProduct.LockState -eq "Locked" ? !$thatProductSelfLocked : $false

            $locked = $locked -and $thatProductLocked
            $selfLocked = $selfLocked -and $thatProductSelfLocked

            $lock.Locked = $locked ? "Locked" : "Unlocked"
            $lock.SelfLocked = $selfLocked ? "Locked" : "Unlocked"
            $lock.Product += @{
                Name =$thatProduct.Name
                Locked = $thatProductLocked ? "Locked" : "Unlocked"
                SelfLocked = $thatProductSelfLocked ? "Locked" : "Unlocked"
            }

            # Write-Log -Context $thisProduct.Name -Action "IsProductLocked" -Target $thatProduct.Name -Message ($global:logLockObject ? $thatProductPropertiesAsString : $null) -Status $thatProduct.LockState -EntryType "Warning" -Force

            $message = "$($thatProduct.Name) : $($thatProduct.LockState)"
            Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,$($thatProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen")   
            if ($thatProductLocked) { 
                $message = "  Host : $($thatProduct.Host)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                $message = "  PID .: $($thatProduct.PID)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
            }
    
            if ($thatProductLocked) {

                if ($waitInterval -gt [timespan]::Zero) {

                    Start-Sleep -Milliseconds $waitInterval.TotalMilliSeconds
                            
                    $thatProduct = Read-Cache $thatProduct.Name
                    if (!$thatProduct) {$thatProduct = $thatProductInit | Copy-Object}
                    # $thatProductPropertiesAsString = $thatProduct | Select-Object -ExcludeProperty Task | ConvertTo-Json -Compress

                    # Write-Log -Context $thisProduct.Name -Action "IsProductLocked" -Target $thatProduct.Name -Message ($global:logLockObject ? $thatProductPropertiesAsString : $null) -Status $thatProduct.LockState -EntryType "Information" -Force
                    $message = "  $($thatProduct.Name) : $($thatProduct.LockState)"
                    Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,$($thatProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen")
                
                }

            }

        }

        # Write-Log -Context $thisProduct.Name -Action "IsProductLocked" -Target ($Name | ConvertTo-Json -AsArray -Compress) -Status ($locked ? "Locked" : "Unlocked") -Message $($lock | ConvertTo-Json -Depth 5 -Compress) -EntryType "Information" -Force
    
        [console]::CursorVisible = $true
    
        return $locked, $selfLocked #, $lock
    
    }
    
    function global:Lock-Product {
    
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][ValidateSet("AzureADCache","AzureADSync")][string[]]$Name,
            [switch]$Silent
        )

        $writeLockMessages = $Silent ? $false : $true

        $lockedProducts = @()

        $Name | ForEach-Object {
            
            $lockProduct = Read-Cache $_
    
            $locked,$selfLocked = Test-IsProductLocked -Name $lockProduct.Name -Silent
            
            $message = "$($lockProduct.Name) : $($lockProduct.LockState)"
            Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,$($lockProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen")  
            if ($locked -or $selfLocked) {
                $message = "  Host : $($lockProduct.Host)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                $message = "  PID .: $($lockProduct.PID)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
            }

            if (!$locked) {

                $lockProduct = @{
                    Name = $_
                    Host = $HOST.Name
                    PID = $PID
                    Class = $null
                    LockState = "Locked"
                    StartTime = Get-Date -AsUTC
                    EndTime = $null
                    LastRunTime = $lockProduct.LastRunTime
                    EndStatus = $lockProduct.EndStatus
                    Task = $null
                }

                $TaskService = New-Object -ComObject('Schedule.Service')
                $TaskService.Connect()
                $runningTasks = $TaskService.GetRunningTasks(0)
                $lockProduct.Task = $runningTasks | Where-Object{$_.Name -like "*$($lockProduct.Name)*"}
                $lockProduct.Host = $lockProduct.Task.Name ?? $HOST.Name
                $lockProduct.Class = $lockProduct.Task.EnginePID -eq $lockProduct.PID ? "Task" : "Process"

                # $message = "$($lockProduct.Name) : LOCKING"
                # Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
    
                $lockProduct | Write-Cache $lockProduct.Name

                $message = "$($lockProduct.Name) : $($lockProduct.LockState)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,$($lockProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen")  
                
                if (!$selfLocked) {
                    $message = "  Host : $($lockProduct.Host)"
                    Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                    $message = "  PID .: $($lockProduct.PID)"
                    Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                }
                
                # $lockProductPropertiesAsString = $lockProduct | Select-Object -ExcludeProperty Task | ConvertTo-Json -Compress
                # Write-Log -Context $lockProduct.Name -Action "Mutex" -Target $lockProduct.Name -Status $lockProduct.LockState -Message ($global:logLockObject ? $lockProductPropertiesAsString : $null) -Force
                # $lockProductTaskPropertiesAsString = ($lockProduct.Task | Select-Object -Property *) | ConvertTo-Json -Compress
                # Write-Log -Context $lockProduct.Name -Action "Mutex" -Target $lockProduct.Name -Status $lockProduct.LockState -Message $lockProductTaskPropertiesAsString -Force

                $lockedProducts += $lockProduct

            }
            else {
                
                Write-Log -Context "Mutex" -Action "Lock" -Target $lockProduct.Name -Status "Contention" -Message "Unable to acquire lock" -EntryType "Warning" -Force
                
                $message = "$($lockProduct.Name) : Contention"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkYellow 
                
                $message = "  Lock contention:  Unable to acquire lock"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                Write-Host+ -Iff $writeLockMessages

                if ($lockedProducts) {
                    Unlock-Product $lockedProducts.Name -Silent
                }

                break

            }

            Write-Host+ -Iff $writeLockMessages

        }
        
        return
    }
    
    function global:Unlock-Product {
    
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true,Position=0)][ValidateSet("AzureADCache","AzureADSync")][string[]]$Name,
            [Parameter(Mandatory=$false,Position=1)][ValidateSet("Success","Error","Aborted")][string]$Status = "Success",
            [switch]$Silent,
            [switch]$Force
        )

        $writeLockMessages = $Silent ? $false : $true

        $Name | ForEach-Object {

            $lockProduct = Read-Cache $_
    
            $locked,$selfLocked = Test-IsProductLocked -Name $lockProduct.Name -Silent
            
            $message = "$($lockProduct.Name) : $($lockProduct.LockState)"
            Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,$($lockProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen")  
            if ($locked -or $selfLocked) {
                $message = "  Host : $($lockProduct.Host)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                $message = "  PID .: $($lockProduct.PID)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
            }

            if ($selfLocked -or $Force) {

                if ($Force) {
                    $message = "  Override : w/FORCE"
                    Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 8),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DArkYellow
                }

                $lockProduct = @{
                    Name = $_
                    Host = $HOST.Name
                    PID = $PID
                    Class = $null
                    LockState = "Unlocked"
                    StartTime = $lockProduct.StartTime # Get-Date -AsUTC
                    EndTime = Get-Date -AsUTC
                    LastRunTime = $Status -eq "Success" ? $lockProduct.StartTime : $lockProduct.LastRunTime
                    EndStatus = $Status
                    Task = $null
                }
                
                $TaskService = New-Object -ComObject('Schedule.Service')
                $TaskService.Connect()
                $runningTasks = $TaskService.GetRunningTasks(0)
                $lockProduct.Task = $runningTasks | Where-Object{$_.Name -like "*$($lockProduct.Name)*"}
                $lockProduct.Host = $lockProduct.Task.Name ?? $HOST.Name
                $lockProduct.Class = $lockProduct.Task.EnginePID -eq $lockProduct.PID ? "Task" : "Process"

                # $message = "$($lockProduct.Name) : UNLOCKING"
                # Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkGray
                
                $lockProduct | Write-Cache $_

                # $lockProductPropertiesAsString = $lockProduct | Select-Object -ExcludeProperty Task | ConvertTo-Json -Compress
                # Write-Log -Context $lockProduct.Name -Action "UNLOCK" -Target $lockProduct.Name -Status $lockProduct.LockState -Message ($global:logLockObject ? $lockProductPropertiesAsString : $null) -Force
                
                $message = "$($lockProduct.Name) : $($lockProduct.LockState)"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,$($lockProduct.LockState -eq "Locked" ? "DarkRed" : "DarkGreen")

                if (!$selfLocked -and !$Force) {
                    $message = "  Host : $($lockProduct.Host)"
                    Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                    $message = "  PID .: $($lockProduct.PID)"
                    Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 12),$message.Split(":")[1] -ForegroundColor DarkGray,DarkGray,DarkGray
                }

            }
            else {

                Write-Log -Context "Mutex" -Action "Unlock" -Target $lockProduct.Name -Status "Contention" -Message "Unable to acquire lock" -EntryType "Warning" -Force

                $message = "$($lockProduct.Name) : Contention"
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor DarkBlue,DarkGray,DarkYellow 
                $message = "  Lock contention:  Unable to acquire lock"
                
                Write-Host+ -Iff $writeLockMessages -NoTrace -NoSeparator $message -ForegroundColor DarkGray
                Write-Host+ -Iff $writeLockMessages

                break
            }

            Write-Host+ -Iff $writeLockMessages

        }
        
        return
    }

 #>
    function global:Get-Provider {

        [CmdletBinding()] 
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$Id,
            [Parameter(Mandatory=$false)][string]$Name,
            [switch]$ResetCache
        )

        $definitionPath = "$($global:Location.Root)\definitions\definitions"

        if (!$ResetCache) {
            if ($(get-cache providers).Exists()) {
                $providers = Read-Cache providers -MaxAge $(New-Timespan -Minutes 2)
            }
        }
        
        if (!$providers) {
            $providers = @()
            $global:Environ.Provider | ForEach-Object {
                if (Test-Path -Path $definitionPath-provider-$($_).ps1) {
                    $providers += . $definitionPath-provider-$($_).ps1
                }
            }

            # for ($i = 0; $i -lt $providers.Count; $i++) {
            #     $providers[$i].IsInstalled = $global:Environ.Provider -contains $providers[$i].Id
            # }

            Write-Cache providers -InputObject $providers
        }

        if ($Name) {$providers = $providers | Where-Object {$_.Name -eq $Name}}
        if ($Id) {$providers = $providers | Where-Object {$_.Id -eq $Id}}

        return $providers
    }

#endregion OVERWATCH
#region PLATFORM

    #region STATUS

        function global:Get-PlatformStatus {
                
            [CmdletBinding()]
            param (
                [switch]$ResetCache,
                [switch]$NoCache,
                [switch]$Reset
            )

            Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            if ((get-cache platformstatus).Exists() -and !$ResetCache -and !$Reset -and !$NoCache) {
                $platformStatus = [PlatformStatus](Read-Cache platformStatus -MaxAge (New-TimeSpan -Seconds 5))
                if ($platformStatus) {return $platformStatus}
            }

            $platformStatus = [PlatformStatus]@{}

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action "Read-Cache" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force

            $params = @{}
            if ($NoCache) {$params += @{NoCache = $true}}
            $platformStatus.IsOK, $platformStatus.RollupStatus, $platformStatus.StatusObject = Get-PlatformStatusRollup @params

            if ($platformStatus.RollUpStatus -in @("Stopping","Starting","Restarting") -and !$platformStatus.Event) {
                $command = switch ($platformStatus.RollUpStatus) {
                    "Stopping" {"Stop"}
                    default {$platformStatus.RollUpStatus -replace "ing",""}
                }
                Set-PlatformEvent -Event $command -Context "Unknown" -EventReason "Unknown" -EventStatus $global:PlatformEventStatus.InProgress -PlatformStatus $platformStatus
            }

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action"Get-PlatformStatusRollup" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force

            $platformCimInstance = Get-PlatformCimInstance
            
            $isOK = $platformStatus.IsOK
            $platformCimInstance | `
                Where-Object {$_.Class -in 'Service'} | `
                    ForEach-Object {
                        $isOK = $isOK -and ($_.Required ? $_.IsOK : $true)
                    }

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action"Get-PlatformCimInstance" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force

            $IsStoppedTimeout = $false
            if (!$isOK) {
                if ($platformStatus.IsStopped) {

                    Write-Verbose "IsStopped: $($platformStatus.IsStopped)"
                    Write-Log -Action "IsStopped" -Target "Platform" -EntryType "Warning" -Status $platformStatus.IsStopped

                    $productShutdownTimeout = $(Get-Product -Id $platformStatus.EventCreatedBy).ShutdownMax
                    $productShutdownTimeout = $productShutdownTimeout.TotalMinutes -gt 0 ? $productShutdownTimeout : $PlatformShutdownMax
                    $shutdownTimeout = $platformStatus.EventCreatedBy ? $productShutdownTimeout : $PlatformShutdownMax
                    $IsStoppedTimeout = $(new-timespan -Start $platformStatus.EventCreatedAt).TotalMinutes -gt $shutdownTimeout.TotalMinutes
                    $isOK = !$IsStoppedTimeout

                    Write-Verbose "IsStoppedTimeout: $($IsStoppedTimeout)"
                    Write-Log -Action "IsStoppedTimeout" -Target "Platform" -EntryType "Warning" -Status $IsStoppedTimeout
            
                }
            }

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action "IsStopped" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force            

            $platformStatus.IsOk = $isOK
            $platformStatus.IsStopped = $serviceStatus -in $PlatformServiceDownState
            $platformStatus.IsStoppedTimeout = $IsStoppedTimeout
            $platformStatus.EventUpdatedAt = [datetime]::Now
            # $platformStatus.CheckedBy = $global:Product.Id
            $platformStatus.ByCimInstance = $platformCimInstance

            if ($platformStatus.IsStoppedTimeout -or $platformStatus.EventStatus -eq $PlatformEventStatus.Failed) {
                $platformStatus.Intervention = $true
            }

            if ($platformStatus.Event) {
                if ($platformStatus.EventStatus -eq $PlatformEventStatus.Completed -and 
                    $platformStatus.RollupStatus -eq $platformStatus.EventStatusTarget) {
                        $platformStatus.EventHasCompleted = $true
                }
            }

            if ($Reset) {

                Write-Verbose "Reset Platform Status"
                # Write-Log -Action "Reset" -Target "Platform Status" -EntryType "Warning" -Status $isOK

                $platformStatus.Event = $null
                $platformStatus.EventReason = $null
                $platformStatus.EventStatus = $null
                $platformStatus.EventStatusTarget = $null
                $platformStatus.EventCreatedAt = [datetime]::MinValue
                $platformStatus.EventCreatedBy = $null
                $platformStatus.Intervention = $false
                $platformStatus.EventHasCompleted = $false
                
            }

            $platformStatus | Write-Cache platformstatus

            Write-Verbose "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)"
            # Write-Log -Context "$($MyInvocation.MyCommand)" -Action "return" -EntryType "Information" -Message "IsOK: $($platformStatus.IsOK), Status: $($platformStatus.RollupStatus)" -Force  

            return $platformStatus # .IsOK

        }

    #endregion STATUS
    #region EVENT

        function global:Set-PlatformEvent {
                
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true)][string]$Event,
                [Parameter(Mandatory=$false)][string]$Context,
                [Parameter(Mandatory=$false)][string]$EventReason,
                [Parameter(Mandatory=$false)][ValidateSet('In Progress','Completed','Failed','Reset','Testing')][string]$EventStatus,
                [Parameter(Mandatory=$false)][string]$EventStatusTarget,
                [Parameter(Mandatory=$false)][object]$PlatformStatus = (Get-PlatformStatus)

            )

            Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            # $platformStatus = Get-PlatformStatus
            
            $PlatformStatus.Event = $Event
            $PlatformStatus.EventStatus = $EventStatus
            $PlatformStatus.EventReason = $EventReason
            $PlatformStatus.EventStatusTarget = $EventStatusTarget ? $EventStatusTarget : $PlatformEventStatusTarget.$($Event)
            $PlatformStatus.EventCreatedAt = [datetime]::Now
            $PlatformStatus.EventCreatedBy = $Context ?? $global:Product.Id
            $PlatformStatus.EventHasCompleted = $false

            $PlatformStatus | Write-Cache platformstatus

            Send-PlatformEventMessage -PlatformStatus $PlatformStatus

            return

        }

        function global:Reset-PlatformEvent {

            [CmdletBinding()]
            param ()

            $null = Get-PlatformStatus -Reset
            Send-PlatformEventMessage -Reset
        }

    #endregion EVENT
    #region TOPOLOGY

        function global:Get-PlatformTopology {
            
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false,Position=0)][string]$Key,
                [switch]$Online,
                [switch]$Offline,
                [switch]$ResetCache,
                [switch][Alias("k")]$Keys,
                [switch]$NoAlias
            )

            # read cache if it exists, else initialize the topology
            if (!$ResetCache -and $(get-cache platformtopology).Exists()) {
                $platformTopology = Read-Cache platformtopology
            } else {
                if ($ResetCache) {
                    $platformTopology = Initialize-PlatformTopology -ResetCache
                } else {
                    $platformTopology = Initialize-PlatformTopology
                }
            }

            # filter to offline/online nodes
            if ($Online -or $Offline) {
                $pt = $platformTopology | Copy-Object
                $nodes = $pt.nodes.keys #.psobject.properties.name
                $components = $pt.components.keys #.psobject.properties.name
                foreach ($node in $nodes) {
                    if (($Online -and ($platformTopology.Nodes.$node.Offline)) -or 
                        ($Offline -and (!$platformTopology.Nodes.$node.Offline))) {
                            foreach ($component in $components) {
                                if ($node -in $platformTopology.Components.$component.Nodes) {
                                    $platformTopology.Components.$component.Nodes.Remove($node)
                                }
                                if ($platformTopology.Components.$component.Nodes.Count -eq 0) {
                                    $platformTopology.Components.Remove($component)
                                }
                            }
                            $platformTopology.Nodes.Remove($node)
                        }
                }
            }

            # Get-PlatformTopology allows for dot-notated keys:  worker.nodes
            # $px are the original key splits saved for message writes
            # $kx are the processed keys that are used to access the topology hashtable
            $len = $Key ? $Key.Split('.').Count : 0
            $p = $Key.Split('.').ToLower()
            $k = [array]$p.Clone()
            for ($i = 0; $i -lt $len; $i++) {
                $k[$i] = "['$($NoAlias ? $k[$i] : ($platformTopology.Alias.($k[$i]) ?? $k[$i]))']"
            }

            $ptExpression = "`$platformTopology"
            if ($len -gt 0) {$ptExpression += "$($k -join '')"}
            $result = Invoke-Expression $ptExpression
            if (!$result) {
                $keysRegex = [regex]"(\[.+?\])"
                $groups = $keysRegex.Matches($ptExpression)
                $lastGroup = $groups[$groups.Count-1]
                $lastKey = $lastGroup.Value.replace("['","").replace("']","")
                $parent = Invoke-Expression $ptExpression.replace($lastGroup.Value,"")
                if (!$parent.Contains($lastKey)) {
                    throw "Invalid key sequence: $($Key)"
                }
            }

            return $Keys ? $result.Keys : $result

        }
        Set-Alias -Name pt -Value Get-PlatformTopology -Scope Global

        function global:Save-PlatformTopology {

            [CmdletBinding()]
            param (
                [Parameter(ValueFromPipeline)][object]$Topology,
                [Parameter(Mandatory=$false)][string]$Extension,
                [switch]$AsDefault,
                [switch]$UseTimeStamp
            )

            begin {

                if (!$Extension -and !$AsDefault -and !$UseTimeStamp) {
                    $Extension = Read-Host "Extension"
                    if (!$Extension) {throw "Extension must be specified."}
                }

                if ($AsDefault) {$Extension = "default"}
                if ($UseTimeStamp) {$Extension = "$(Get-Date -Format 'yyyyMMddHHmm')"}

                $platformTopology = @{}
            }
            process {
                $platformTopology = $Topology 
            }
            end {
                $platformTopology ??= Get-PlatformTopology
                $platformTopology | Write-Cache "platformtopology.$($Extension)"
            }
        }
        Set-Alias -Name ptSave -Value Save-PlatformTopology -Scope Global

        function global:Restore-PlatformTopology {
            
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][string]$Extension,
                [switch]$FromDefault
            )
            if ($FromDefault) {$Extension = "default"}

            if (!$Extension) {
                $Extension = Read-Host "Extension"
                if (!$Extension) {throw "Extension must be specified."}
            }
            
            $platformTopology = Read-Cache "platformtopology.$($Extension)" 
            $platformTopology | Write-Cache platformtopology

            return $platformTopology

        }
        Set-Alias -Name ptRestore -Value Restore-PlatformTopology -Scope Global

        function global:Get-PlatformTopologyAlias {

            [CmdletBinding()]
            param(
                [Parameter(Mandatory=$false,Position=0)][string]$Alias
            )
            $platformTopology = Get-PlatformTopology
            return $Alias ? $platformTopology.Alias.$Alias : $platformTopology.Alias
        
        }
        Set-Alias -Name ptGetAlias -Value Get-PlatformTopologyAlias -Scope Global
        Set-Alias -Name ptAlias -Value Get-PlatformTopologyAlias -Scope Global

        function global:Set-PlatformTopologyAlias {

            [CmdletBinding()]
            param(
                [Parameter(Mandatory=$true,Position=0)][string]$Alias,
                [Parameter(Mandatory=$true,Position=1)][string]$Value
            )
            $platformTopology = Get-PlatformTopology
            $platformTopology.Alias.$Alias = $Value
            $platformTopology | Write-Cache platformtopology
        
        }
        Set-Alias -Name ptSetAlias -Value Set-PlatformTopologyAlias -Scope Global

    #endregion TOPOLOGY

#endregion PLATFORM
#region TESTS

    function global:Get-IpAddress {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)][string]$ComputerName
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        return (Resolve-DnsName $ComputerName).IPAddress

    }

    function global:Test-Connections {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = (Get-PlatformTopology nodes -Keys)
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $dots = Write-Dots -Length 47 -Adjust (-(("  Network Connections").Length))
        Write-Host+ -NoTrace "  Network Connections",$dots,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray
        Write-Log -Action "Test" -Target "Network"

        $fail = $false
        foreach ($node in $ComputerName) {

            $ip = ([System.Net.Dns]::GetHostAddresses($node) | Where-Object {$_.AddressFamily -eq "InterNetwork"}).IPAddressToString

            $dots = Write-Dots -Length 39 -Adjust (-(("    Ping $($node) [$($ip)]").Length))
            Write-Host+ -NoTrace -NoNewLine "    Ping","$($node) [$($ip)]",$dots -ForegroundColor Gray,DarkBlue,DarkGray

            if (Test-Connection -ComputerName $node -Quiet) {
                Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen
            }
            else {
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
                Write-Log -Action "Test" -Target "Network" -Status "Fail" -EntryType "Error" -Message "Unable to ping $($node) [$($ip)]"
                $fail = $true
            }

        }

        $dots = Write-Dots -Length 47 -Adjust (-(("  Network Connections").Length))
        Write-Host+ -NoTrace -NoNewLine  "  Network Connections",$dots -ForegroundColor Gray,DarkGray

        if ($fail) {
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
            Write-Log -Action "Test" -Target "Network" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message
            # throw "Network Connections ... FAIL"
        }
        else {
            Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen
            Write-Log -Action "Test" -Target "Network" -Status "Pass"
        }
    }

    function global:Test-PSRemoting {

        [CmdletBinding()]
        param ()

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $dots = Write-Dots -Length 47 -Adjust (-(("  Powershell Remoting").Length))
        Write-Host+ -NoTrace "  Powershell Remoting",$dots,"PENDING" -ForegroundColor Gray,DarkGray,DarkGray
        Write-Log -Action "Test" -Target "Powershell-Remoting"

        $fail = $false
        foreach ($node in (Get-PlatformTopology nodes -Online -Keys)) {

            # Write-Host+ -NoNewline -NoTimestamp -NoTrace "." -ForegroundColor DarkGray

            $dots = Write-Dots -Length 39 -Adjust (-(("    Remote to $($node)").Length))
            Write-Host+ -NoTrace -NoNewLine "    Remote to","$($node)",$dots -ForegroundColor Gray,DarkBlue,DarkGray

            try {
                $psSession = Get-PSSession+ -ComputerName $node 
                Remove-PSSession -Session $psSession
                Write-Host+ -NoTimestamp -NoTrace " PASS" -ForegroundColor DarkGreen 
            }
            catch {
                Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
                Write-Log -Action "Test" -Target "Powershell-Remoting" -Status "Fail" -EntryType "Error" -Message "Powershell-Remoting to $($node) failed"
                $fail = $true
            }

        }

        $dots = Write-Dots -Length 47 -Adjust (-(("  Powershell Remoting").Length))
        Write-Host+ -NoTrace -NoNewLine "  Powershell Remoting",$dots -ForegroundColor Gray,DarkGray
        
        if ($fail) {
            Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed
            Write-Log -Action "Test" -Target "Powershell-Remoting" -Status "Fail" -EntryType "Error"
            throw "Powershell Remoting ... FAIL"
        }
        else {
            Write-Host+ -NoTimestamp -NoTrace  " PASS" -ForegroundColor DarkGreen
            Write-Log -Action "Test" -Target "Powershell-Remoting" -Status "Pass"
        }
    }

    <#
        .DESCRIPTION
        Outputs the SSL protocols that the client is able to successfully use to connect to a server.

        .PARAMETER ComputerName
        The name of the remote computer to connect to.

        .PARAMETER Port
        The remote port to connect to. The default is 443.

        .EXAMPLE
        Test-SslProtocol -ComputerName "www.google.com"

        ComputerName       : www.google.com
        Port               : 443
        KeyLength          : 2048
        SignatureAlgorithm : rsa-sha1
        Ssl2               : False
        Ssl3               : True
        Tls                : True
        Tls11              : True
        Tls12              : True

        .NOTES
        Copyright 2014 Chris Duck
        http://blog.whatsupduck.net

        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
    #>
    function global:Test-SslProtocol {
        param(
            [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ValueFromPipeline=$true)]
            $ComputerName = $global:Platform.Uri.Host,

            [Parameter(ValueFromPipelineByPropertyName=$true)]
            [int]$Port = 443
        )

        begin {
                
            Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

            $message = "  SSL Protocol: PENDING"
            Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray

            $now = Get-Date -AsUTC
            $30days = New-TimeSpan -days 30
            # $emptyString = ""
            $fail = $false
            $warn = $false

            $ProtocolNames = [System.Security.Authentication.SslProtocols] |
                Get-Member -Static -MemberType Property |
                Where-Object -Filter { $_.Name -notin @("Default","None") } |
                Foreach-Object { $_.Name }

            $bestPractice = @{
                protocols = @("TLS12")
                signatureAlgorithms = @("sha256RSA")
            }

        }

        process {

            $ProtocolStatus = [Ordered]@{}
            $ProtocolStatus.Add("ComputerName", $ComputerName)
            $ProtocolStatus.Add("Port", $Port)
            $ProtocolStatus.Add("KeyLength", $null)
            $ProtocolStatus.Add("SignatureAlgorithm", $null)
            $ProtocolStatus.Add("SupportedProtocols",@())

            $ProtocolNames | ForEach-Object {
                $ProtocolName = $_
                $Socket = New-Object System.Net.Sockets.Socket( `
                    [System.Net.Sockets.SocketType]::Stream,
                    [System.Net.Sockets.ProtocolType]::Tcp)
                $Socket.Connect($ComputerName, $Port)
                try {
                    $NetStream = New-Object System.Net.Sockets.NetworkStream($Socket, $true)
                    $SslStream = New-Object System.Net.Security.SslStream($NetStream, $true)
                    $SslStream.AuthenticateAsClient($ComputerName,  $null, $ProtocolName, $false )
                    $RemoteCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]$SslStream.RemoteCertificate
                    $ProtocolStatus["KeyLength"] = $RemoteCertificate.PublicKey.Key.KeySize
                    $ProtocolStatus["SignatureAlgorithm"] = $RemoteCertificate.SignatureAlgorithm.FriendlyName
                    $ProtocolStatus["Certificate"] = $RemoteCertificate
                    $ProtocolStatus.Add($ProtocolName, $true)
                } catch  {
                    $ProtocolStatus.Add($ProtocolName, $false)
                } finally {
                    $SslStream.Close()
                }
            }

        }

        end {

            $thisWarn = $false
            $thisFail = $false

            $expiresInDays = $ProtocolStatus.Certificate.NotAfter - $now
            
            $thisWarn = $expiresInDays -le $30days
            $warn = $warn -or $thiswarn
            $thisFail = $expiresInDays -le [timespan]::Zero
            $fail = $fail -or $thisFail

            $expiryColor = $thisFail ? "DarkRed" : ($thisWarn ? "DarkYellow" : "DarkGray")
            
            $message = "    Certificate : PENDING"
            Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 40 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,DarkGray
            $message = "      Subject:      $($ProtocolStatus.Certificate.Subject)"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Issuer:       $($ProtocolStatus.Certificate.Issuer.split(",")[0])"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Serial#:      $($ProtocolStatus.Certificate.SerialNumber)"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Thumbprint:   $($ProtocolStatus.Certificate.Thumbprint)"
            Write-Host+ -NoTrace -NoSeparator $message -ForegroundColor DarkGray
            $message = "      Expiry:      | $($ProtocolStatus.Certificate.NotAfter)"
            Write-Host+ -NoTrace -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor DarkGray,$expiryColor
            $message = "      Status:      | $($thisFail ? "Expired" : ($thisWarn ? "Expires in $([math]::round($expiresInDays.TotalDays,1)) days" : "Valid"))"
            Write-Host+ -NoTrace -NoSeparator $message.Split("|")[0],$message.Split("|")[1] -ForegroundColor DarkGray,$expiryColor

            # change expireColor success from darkgray to darkgreen for PASS indicators
            $expiryColor = $thisFail ? "DarkRed" : ($thisWarn ? "DarkYellow" : "DarkGreen")

            $message = "    Certificate : $($thisFail ? "FAIL" : ($thisWarn ? "WARN" : "PASS"))"
            Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 40 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,$expiryColor

            $thisWarn = $false
            $thisFail = $false

            foreach ($signatureAlgorithm in $bestPractice.signatureAlgorithms) {
                $thisFail = $ProtocolStatus.SignatureAlgorithm -ne $signatureAlgorithm
                $fail = $fail -or $thisFail
                $message = "    Signature Algorithm : $($thisFail ? "FAIL": "PASS")"
                Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 40 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($thisFail ? "DarkRed" : "DarkGreen")
            }

            $thisWarn = $false
            $thisFail = $false

            foreach ($protocol in $bestPractice.protocols) {
                $thisFail = !$ProtocolStatus.$protocol
                $fail = $fail -or $thisFail
                $message = "    $protocol Enabled : $($thisFail ? "FAIL": "PASS")"
                Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 40 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,($thisFail ? "DarkRed" : "DarkGreen")
            }

            $thisWarn = $false
            $thisFail = $false

            $message = "  SSL Protocol : $($fail ? "FAIL" : ($warn ? "WARN" : "PASS"))"
            Write-Host+ -NoTrace -NoSeparator $message.Split(":")[0],(Write-Dots -Length 48 -Adjust (-($message.Split(":")[0]).Length)),$message.Split(":")[1] -ForegroundColor Gray,DarkGray,$expiryColor
            Write-Log -Action "Test" -Target "SSL" -Status $($fail ? "FAIL" : ($warn ? "WARN" : "PASS"))
        
            # return [PSCustomObject]$ProtocolStatus
        }

    }

#endregion TESTS
#region MISC

    function global:Get-PlatformCimInstance {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string]$View
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $PlatformServices = Get-PlatformService -ErrorAction SilentlyContinue
        $PlatformProcesses = Get-PlatformProcess -ErrorAction SilentlyContinue
        $PlatformTasks = Get-PlatformTask -ErrorAction SilentlyContinue
        $platformCimInstance = [array]$PlatformServices + [array]$PlatformProcesses + [array]$PlatformTasks

        return $platformCimInstance  | Select-Object -Property $($View ? $CimView.$($View) : $CimView.Default)

    }

    function global:Copy-Object {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0,ValueFromPipeline)][object]$InputObject
        )

        begin {
            $outputObject = @()
        }
        process {
            $outputObject += $InputObject
        }
        end {
            # return $outputObject  | ConvertTo-Json -Depth 99 | ConvertFrom-Json -Depth 99
            return [System.Management.Automation.PSSerializer]::Deserialize(
                [System.Management.Automation.PSSerializer]::Serialize(
                    $InputObject
                )
            )
        }

    }

    function global:Get-PSSession+ {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName=$env:COMPUTERNAME,
            [switch]$All
        )

        if ($All) {return Get-PSSession}

        $allSessions = @()
        foreach ($node in $ComputerName) {
            $psSession = $null
            $nodeIsLocalhost = $node.ToLower() -eq "localhost" -or $node.ToLower() -eq $env:COMPUTERNAME.ToLower()
            $psSessions = $nodeIsLocalhost ? (Get-PSSession | Where-Object {$_.ComputerName.ToLower() -eq "localhost"}) : (Get-PSSession -ComputerName $node)
            $psSessions = $psSessions | Sort-Object -Property @{Expression = "State"; Descending = $true}, @{Expression = "Availability"; Descending = $false}
            foreach ($nodePSSession in $psSessions) {
                if ($null -ne $nodePSSession -and 
                    ($nodePSSession.Availability -eq [System.Management.Automation.Runspaces.RunspaceAvailability]::Available)) {
                    #   -or $nodePSSession.Availability -eq [System.Management.Automation.Runspaces.RunspaceAvailability]::None)) {
                        $psSession = $nodePSSession
                        break
                }
            }
            if ($null -eq $psSession) {
                $psSession = New-PSSession -ComputerName $node -ErrorAction SilentlyContinue
                if ($null -eq $psSession -and $nodeIsLocalhost) {
                    $psSession = New-PSSession -EnableNetworkAccess
                }
            }
            # if ($psSession.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Disconnected) {
            #     Connect-PSSession -Session $psSession | Out-Null
            # }
            $allSessions += $psSession
        }

        return $allSessions

    }

    function global:ConvertTo-Hashtable {

        # Author: Adam Bertram
        # Reference: https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/

        [CmdletBinding()]
        [OutputType('hashtable')]
        param (
            [Parameter(ValueFromPipeline)]
            $InputObject
        )
    
        process {
            ## Return null if the input is null. This can happen when calling the function
            ## recursively and a property is null
            if ($null -eq $InputObject) {
                return $null
            }
    
            ## Check if the input is an array or collection. If so, we also need to convert
            ## those types into hash tables as well. This function will convert all child
            ## objects into hash tables (if applicable)
            if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
                $collection = @(
                    foreach ($object in $InputObject) {
                        ConvertTo-Hashtable -InputObject $object
                    }
                )
    
                ## Return the array but don't enumerate it because the object may be pretty complex
                Write-Output -NoEnumerate $collection
            } elseif ($InputObject -is [psobject]) { ## If the object has properties that need enumeration
                ## Convert it to its own hash table and return it
                $hash = @{}
                foreach ($property in $InputObject.PSObject.Properties) {
                    $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
                }
                $hash
            } else {
                ## If the object isn't an array, collection, or other object, it's already a hash table
                ## So just return it.
                $InputObject
            }
        }
    }

#endregion MISC
#region TESTS

    function global:Set-PlatformService {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][string[]]$ComputerName = "localhost",
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][ValidateSet("Manual","Automatic","AutomaticDelayedStart","Disabled")][Microsoft.PowerShell.Commands.ServiceStartupType]$StartupType
        )

        $psSession = Get-PSSession+ -ComputerName $ComputerName -ErrorAction SilentlyContinue

        Invoke-Command -Session $psSession {
            Get-Service -Name $using:Name -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.StartMode -ne $using:StartupType) {
                    Set-Service -Name $_.Name -StartupType $using:StartupType
                }
            }
        }

        # $svc = Invoke-Command -Session $psSession {
        #     Get-Service -Name $using:Name -ErrorAction SilentlyContinue
        # }

        Remove-PSSession $psSession

        return # $svc

    }

#endregion TESTS