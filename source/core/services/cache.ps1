<# 
.Synopsis
Cache service for Overwatch
.Description
This script provides file-based caching for Overwatch objects via Powershell's Import-Clixml 
and Export-Clixml cmdlets.
#>

$global:lockRetryDelay = New-Timespan -Seconds 1
$global:lockRetryMaxAttempts = 5

<# 
.Synopsis
Gets the properties of an Overwatch cache.
.Description
Returns the properties of Overwatch caches.
.Parameter Name
The name of the cache.  If the named cache does not exist, then a stubbed cache object is returned to
the caller.  If Name is not specified, then the properties of ALL Overwatch caches are returned.  
.Parameter MaxAge
The maximum allowed age of the cache[s].  If the duration since the LastWriteTime of the cache file 
is greater than the MaxAge, the Expired property of the cache[s] is marked as true.
.Outputs
Cache object properties (not the content of the cache).
#>

function global:Get-Cache {
    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][timespan]$MaxAge = [timespan]::MaxValue
    ) 

    $path = "$($global:Location.Data)\$($Name).cache"
    $cache = [CacheObject]::new($path, $ComputerName, $MaxAge)

    return $cache
}

<# 
.Synopsis
Read the contents of an Overwatch object from cache.
.Description
Retrieves the contents of a named cache and returns the object to the caller.  If the cache has expired, 
the cache is cleared and a null object is returned to the caller.
.Parameter Name
The name of the cache.
.Parameter MaxAge
The maximum allowed age of the cache.  The MaxAge is compared to the LastWriteTime of the cache to determine
if the cache has expired.  If MaxAge is not specified, the cache never expires.
.Outputs
Overwatch (or null) object.
#>
function global:Read-Cache {
    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][timespan]$MaxAge = [timespan]::MaxValue
    )

    $cache = Get-Cache $Name -MaxAge $MaxAge -ComputerName $ComputerName

    if ($cache.Exists()) {
        if ($cache.Expired()) {
            $cache = Clear-Cache $cache.FileNameWithoutExtension
            return $null
        }
        $lock = Lock-Cache $cache -Share "Read"
        if ($lock) {
            $outputObject = Import-Clixml $cache.Path
            Unlock-Cache $lock
            return $outputObject
        }
        else {
            throw "Unable to acquire lock on cache $Name"
        }
    }
    else {
        return $null
    }
}

<# 
.Synopsis
Write an Overwatch to cache.
.Description
Writes the contents of an object to the named cache.
.Parameter Name
The name of the cache.
.Parameter InputObject
The object to be cached.
#>
function global:Write-Cache {
    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(ValueFromPipeline)][Object]$InputObject,
        [Parameter(Mandatory=$false)][int]$Depth=2,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    begin {
        $cache = Get-Cache $Name -ComputerName $ComputerName
        $outputObject = @()
    }
    process {
        $outputObject += $InputObject
    }
    end {
        $lock = Lock-Cache $cache -Share "None"
        if ($lock) {
            $outputObject  | Export-Clixml $cache.Path -Depth $Depth
            Unlock-Cache $lock
        }
        else {
            throw "Unable to acquire lock on cache $Name"
        }
    }
}

<# 
.Synopsis
Clears an Overwatch cache.
.Description
Clearing a cache results in the deletion of the cache file.
.Parameter Name
The name of the cache.  If Name is not specified, then ALL caches are cleared.
.Outputs
Stubbed cache object.
#>
function global:Clear-Cache {
    param (
        [Parameter(Mandatory=$false,Position=0)][String]$Name='*',
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )
    
    $cache = Get-Cache $Name -ComputerName $ComputerName
    if ($cache.Exists()) {
        foreach ($fileInfo in $cache.FileInfo) {
            # $cacheName = $fileInfo.BaseName
            $cachePath = $fileInfo.FullName
            $lock = Lock-Cache $cache -Share "None"
            if ($lock) {
                Remove-Files $cachePath -Verbose:$false
                Unlock-Cache $lock
            }
            else {
                throw "Unable to acquire lock on cache $($fileInfo.FullName)"
            }
        }
        $($cache).Exists() = $false
    }
    return $null
}

<# 
.Synopsis
Locks an Overwatch cache.
.Description
Creates a separate file used to indicate the cache is locked.
.Parameter Name
The name of the cache.
.Parameter Share
None (exclusive access) or Read (others can read).
.Outputs
The FileStream object for the lock file.
#>
function global:Lock-Cache {

    param (
        [Parameter(Mandatory=$true,Position=0)][object]$Cache,
        [Parameter(Mandatory=$false)][ValidateSet("Open","OpenOrCreate")][String]$Mode = "OpenOrCreate",
        [Parameter(Mandatory=$false)][ValidateSet("Read","Write","ReadWrite")][String]$Access = ($Share -eq "None" ? "ReadWrite" : "Read"),
        [Parameter(Mandatory=$false)][ValidateSet("Read","None")][String]$Share = "Read"
    )

    # $cache = Get-Cache $Name -ComputerName $ComputerName
    $lockFile = $Cache.FullPathName -replace $Cache.Extension,".lock"
    
    $lockRetryAttempts = 0
    while (!($Access -eq "ReadWrite" -and $FileStream.CanWrite) -and !($Access -eq "Read" -and $FileStream.CanRead)) {
        # if (!(Test-Path -Path $lockFile)) {
        #     Set-Content -Path $lockFile -Value (Get-Date -AsUTC)
        # }
        try {
            if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
                $message = "Unable to acquire lock after $($lockRetryAttempts) attempts."
                # $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
                Write-Log -Action "LockCache" -Target $Cache.FileNameWithoutExtension -Status "Error" -Message $message -EntryType "Error" # -Data $lockMeta
                return $null
            }
            $lockRetryAttempts++
            $FileStream = [System.IO.File]::Open($lockFile, $Mode, $Access, $Share)
        }
        catch {
            Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
        }
    }

    if ($lockRetryAttempts -gt 2) {
        $message = "Lock acquired after $($lockRetryAttempts) attempts."
        # $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "LockCache" -Target $Cache.FileNameWithoutExtension -Status "Success" -Message $message -Force # -Data $lockMeta
    }

    return $FileStream
}

<# 
.Synopsis
Unlocks a locked Overwatch cache.
.Description
Removes the cache's lock file making the cache available.
.Parameter Lock
The FileStream object for the lock file.
.Outputs
None.
#>
function global:Unlock-Cache {

    param (
        [Parameter(Mandatory=$true,Position=0)][object]$Lock
    )

    $Lock.Close()
    $Lock.Dispose()
    Remove-Item -Path $Lock.Name -Force -ErrorAction SilentlyContinue

    # Write-Log -Action "UnlockCache" -Target $cache.FileNameWithoutExtension -Status "Success" -Force

}

<# 
.Synopsis
Determine if cache is locked.
.Description
Uses Test-Path to check for the existence of a cache lock file.
.Parameter Name
The name of the cache.
.Outputs
Boolean result from Test-Path
#>
function global:Test-IsCacheLocked {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $cache = Get-Cache $Name -ComputerName $ComputerName
    $lockFile = $cache.FullPathName -replace $cache.Extension,".lock"

    return Test-Path -Path $lockFile

}

<# 
.Synopsis
Wait for a cache to be unlocked.
.Description
Waits until the cache lock is released.
.Parameter Name
The name of the cache.
.Outputs
None
#>
function global:Wait-CacheUnlocked {

    param (
        [Parameter(Mandatory=$true,Position=0)][String]$Name,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $cache = Get-Cache $Name -ComputerName $ComputerName
    # $lockFile = $cache.FullPathName -replace $cache.Extension,".lock"

    $lockRetryAttempts = 0
    while (Test-IsCacheLocked $cache.FileNameWithoutExtension) {
        if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
            $message = "Timeout waiting for lock to be released."
            # $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
            Write-Log -Action "WaitCache" -Target $cache.FileNameWithoutExtension -Status "Timeout" -Message $message -EntryType "Warning" # -Data $lockMeta 
            throw "($message -replace ".","") on $($cache.FileNameWithoutExtension)."
        }
        $lockRetryAttempts++
        Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
    }

    if ($lockRetryAttempts -gt 1) {
        $message = "Lock released."
        # $lockMeta = @{retryDelay = $global:lockRetryDelay; retryMaxAttempts = $global:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "WaitCache" -Target $cache.FileNameWithoutExtension -Status "CacheAvailable" -Message $message -Force # -Data $lockMeta
    }

    return

}