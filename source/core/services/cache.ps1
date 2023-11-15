<# 
.Synopsis
Cache service for Overwatch
.Description
This script provides file-based caching for Overwatch objects via Powershell's Import-Clixml 
and Export-Clixml cmdlets.
#>

$script:lockRetryDelay = New-Timespan -Milliseconds 1500
$script:lockRetryMaxAttempts = 5

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

    if ($cache.Exists) {
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
    if ($cache.Exists) {
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
        $($cache).Exists = $false
    }
    return $null
}

function Format-CacheItemKey {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Key
    )

    # examine each key to see if it needs to be quoted
    $_keys = $Key -split "\."
    $quotedKey = ""
    foreach ($_key in $_keys) {
        if ($_key -match "^`".*`"`$") {
            $quotedKey += $_key
        }
        else {
            if ($_key -notmatch "^[0-9a-zA-Z-_]*`$") {
                throw "Invalid characters in subkey '$_key' of key '$Key'. Valid chars: '^[0-9a-zA-Z-_]*`$'"
            }
            if ($_key -match ".*-|_.*") {
                $quotedKey += "`"$($_key)`""
            }
            else {
                $quotedKey += $_key 
            }
        }
        $quotedKey += "."
    }
    $quotedKey = $quotedKey -replace "\.$"

    return $quotedKey

}

function global:Get-CacheItem {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$false)][timespan]$MaxAge = [timespan]::MaxValue
    )

    # quote subkeys as necessary
    $quotedKey = Format-CacheItemKey -Key $Key

    # the cache is structured as follows:
    # key0 = @{ Value = @ { key1 = @{ Value = ... @{ keyN = valueObject }}}}
    # so to ensure that $Key will work ...
    # reformat the key to be key1.Value.key2.Value ... keyN.Value
    $quotedKey = (($quotedKey -split "\." | Where-Object {$_ -ne "Value"}) -join ".Value.") + ".Value"

    $cacheItem = $null
    if ((Get-Cache $Name).Exists) {
        $cache = Read-Cache $Name
        $cacheItem = Invoke-Expression "`$cache.$quotedKey"
        if (Invoke-Expression "`$cache.$quotedKey.CacheItemTimestamp") {
            $cacheItemTimestamp = Get-Date (Invoke-Expression "`$cache.$quotedKey.CacheItemTimestamp") -AsUTC
        }
        if ($cacheItem -and $CacheItemTimestamp -and $MaxAge -ne [timespan]::MaxValue) {
            if ([datetime]::Now - $CacheItemTimestamp -gt $MaxAge) {
                $cacheItemParentKey = ($Key -split "\.",-2)[0]
                $cacheItemKey = ($Key -split "\.",-2)[1]
                $expression = "`$cache.$cacheItemParentKey.Remove(`"$cacheItemKey`")"
                Invoke-Expression $expression
                $cache | Write-Cache $Name
                $cacheItem = $null
            }
        }
    }
    return $cacheItem

}

function Invoke-CacheItemOperation {

    [CmdletBinding(DefaultParameterSetName="Add")]
    param (

        [Parameter(Mandatory=$true,ParameterSetName="Add")]
        [Parameter(Mandatory=$true,ParameterSetName="Update")]
        [Parameter(Mandatory=$true,ParameterSetName="Remove")]
        [string]$Name,

        [Parameter(Mandatory=$true,ParameterSetName="Add")]
        [Parameter(Mandatory=$true,ParameterSetName="Update")]
        [Parameter(Mandatory=$true,ParameterSetName="Remove")]
        [string]$Key,

        [Parameter(Mandatory=$true,ParameterSetName="Add")]
        [Parameter(Mandatory=$true,ParameterSetName="Update")]
        [AllowNull()][object]$Value,
        
        [Parameter(Mandatory=$true,ParameterSetName="Add")]
        [switch]$Add,

        [Parameter(Mandatory=$false,ParameterSetName="Add")]
        [switch]$Overwrite,
        
        [Parameter(Mandatory=$true,ParameterSetName="Update")]
        [switch]$Update,
        
        [Parameter(Mandatory=$true,ParameterSetName="Remove")]
        [switch]$Remove
    ) 

    # quote subkeys as necessary
    $quotedKey = Format-CacheItemKey -Key $Key

    $cache = @{}
    if ((Get-Cache $Name).Exists) {
        $cache = Read-Cache $Name
    }

    if ($Add -and $null -ne (Get-CacheItem -Name $Name -Key $quotedKey) -and !$Overwrite) {
        if ($ErrorActionPreference -ne "SilentlyContinue") {
            Write-Host+ "ERROR: Unable to ADD cache item '$($Key)' in cache '$Name' because it already exists" -ForegroundColor DarkRed
            Write-Host+ -NoTrace "ERROR: To overwrite the cache item, add the '-Overwrite' switch" -ForegroundColor DarkRed
        }
        return
    }

    if ($Update -and $null -eq (Get-CacheItem -Name $Name -Key $quotedKey)) {
        if ($ErrorActionPreference -ne "SilentlyContinue") {
            Write-Host+ "ERROR: Unable to UPDATE cache item $($Key) in cache $Name because it does not exist" -ForegroundColor DarkRed
        }
        return
    }

    if ($Remove -and $null -eq (Get-CacheItem -Name $Name -Key $quotedKey)) {
        if ($ErrorActionPreference -ne "SilentlyContinue") {
            Write-Host+ "ERROR: Unable to REMOVE cache item $($Key) in cache $Name because it does not exist" -ForegroundColor DarkRed
        }
        return
    }

    # REMOVE cache item from cache
    if ($Remove) {
        if (Invoke-Expression "`$cache.$quotedKey") {
            $cacheItemParentKey = ($Key -split "\.",-2)[0]
            $cacheItemKey = ($Key -split "\.",-2)[1]
            $expression = "`$cache.$cacheItemParentKey.Remove(`"$cacheItemKey`")"
        }

    }

    # ADD/UPDATE cache item to cache
    else {

        # $Key can be dot-notation; split into individual keys
        $_keys = $quotedKey -split "\."

        $expression = ""
        $closingBracketCount = 0
        for ($i = 0; $i -lt $_keys.Count; $i++) {
            # build the key for the current iteration
            $_key = ""
            for ($j = 0; $j -le $i; $j++) {
                if ($i -gt 0 -and $j -gt 0) {
                    $_key += ".Value"
                }
                if (![string]::IsNullOrEmpty($_key)) {
                    $_key += "."
                }
                $_key += $_keys[$j]
            }
            # bound to be a more efficient way than the above plus this
            # but this is a quick hack to get it working
            $objectKey = $null
            $valueKey = $null
            if ($i -eq 0) {
                $objectKey = "keys"
                $valueKey = $_key
            }
            else {
                $valueKey = ($_key -split "\.")[-1]
                $objectKey = $_key -replace [Regex]::Escape(".$valueKey")
            }
            # if the key for this iteration doesn't exist,
            # build the value portion of the expression
            if ((Invoke-Expression "`$cache.$($objectKey)") -notcontains $valueKey) { 
                # if this is the first part of the assignment, then
                # add the assignment operator if not already present
                if ($expression -notlike "* += *") {
                    $expression += " += "
                }
                # add the value for this iteration
                $expression += "@{ $($_keys[$i]) = @{ Value = "
                # count how many closing brackets will be needed later
                $closingBracketCount++
                $closingBracketCount++
            }
            # if the key for this iteration DOES exist,
            # then add the key to the key portion of the expression
            else {
                $expression += ".$($_keys[$i]).Value"
            }
        }
        # prepend $cache to the expression
        # result: "$cache = <value expression>" or "$cache.<key expression> = <value expression>"
        $expression = "`$cache" + $expression

        # otherwise, this is an ADD or UPDATE operation
        # complete the expression
        if ($Add -or $Update) {
            if ($expression.EndsWith("{ Value = ")) {
                $expression = $expression -replace "\@\{ Value = `$"
                $closingBracketCount--
            }
            if ($expression -notlike "* = *") {
                $expression += " = "
            }
            $expression += "`$Value"
            for ($i = 0; $i -lt $closingBracketCount; $i++) {
                $expression += " }"
            }
        }
    }

    Invoke-Expression $expression
    $cache | Write-Cache $Name

}

function Add-CacheItemTimestamp {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][AllowNull()][object]$Value
    ) 

    # System.Object
    if ($Value.GetType().BaseType.Name -eq "Object") {
        # if cacheItemTimestamp doesn't exist, add it
        if (!$Value.CacheItemTimestamp) {
            # object is empty/null
            # add cacheItemTimestamp to object
            if ($Value.Count -eq 0) {
                $Value = @{ CacheItemTimestamp = (Get-Date -AsUTC) }
            }
            # object is NOT empty/null; redefine object
            # put cloned object into value property
            # add cacheItemTimestamp to object
            else {
                $Value = @{ value = $Value | Copy-Object; CacheItemTimestamp = (Get-Date -AsUTC) }
            }
        }
        # if cacheItemTimestamp exists, update it
        else {
            $Value.CacheItemTimestamp = Get-Date -AsUTC
        }
    }
    # System.ValueType and System.Array
    elseif ($Value.GetType().BaseType.Name -in @("ValueType","Array")) {
        $Value = @{ value = $Value; CacheItemTimestamp = (Get-Date -AsUTC) }
    }
    else {
        throw "Unhandled type '$($Value.GetType().BaseType)'"
    }

    return $Value

}

function global:Add-CacheItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][AllowNull()][object]$Value,
        [switch]$Overwrite
    ) 

    $Value = Add-CacheItemTimestamp -Value $Value
    Invoke-CacheItemOperation -Name $Name -Key $Key -Value $Value -Add -Overwrite:$Overwrite.IsPresent

}

function global:Update-CacheItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][AllowNull()][object]$Value
    ) 

    $Value = Add-CacheItemTimestamp -Value $Value
    Invoke-CacheItemOperation -Name $Name -Key $Key -Value $Value -Update

}

function global:Remove-CacheItem {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Key
    ) 

    Invoke-CacheItemOperation -Name $Name -Key $Key -Remove

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

    $lockFile = $Cache.FullName -replace $Cache.Extension,".lock"
    
    $lockRetryAttempts = 0
    do {
        try {
            $lockRetryAttempts++
            $FileStream = [System.IO.File]::Open($lockFile, $Mode, $Access, $Share)
        }
        catch {
            Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
        }
    } 
    until ( 
        ($Access -eq "ReadWrite" -and $FileStream.CanWrite) -or 
        ($Access -eq "Read" -and $FileStream.CanRead) -or 
        $lockRetryAttempts -ge $lockRetryMaxAttempts 
    )
    
    if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
        $message = "Unable to acquire lock on cache '$cache' after $($lockRetryAttempts) attempts."
        Write-Log -Action "LockCache" -Target $Cache.FileNameWithoutExtension -Status "Error" -Message $message -EntryType "Error"
        return $null
    }

    if ($lockRetryAttempts -gt 2) {
        # this is only here b/c after this many times, something is probably wrong and we need to figure out what and why
        $message = "Lock acquired on cache '$cache' after $($lockRetryAttempts) attempts."
        Write-Log -Action "LockCache" -Target $Cache.FileNameWithoutExtension -Status "Success" -Message $message -Force
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
    $lockFile = $cache.FullName -replace $cache.Extension,".lock"

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
    # $lockFile = $cache.FullName -replace $cache.Extension,".lock"

    $lockRetryAttempts = 0
    while (Test-IsCacheLocked $cache.FileNameWithoutExtension) {
        if ($lockRetryAttempts -ge $lockRetryMaxAttempts) {
            $message = "Timeout waiting for lock to be released."
            # $lockMeta = @{retryDelay = $script:lockRetryDelay; retryMaxAttempts = $script:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
            Write-Log -Action "WaitCache" -Target $cache.FileNameWithoutExtension -Status "Timeout" -Message $message -EntryType "Warning" # -Data $lockMeta 
            throw "($message -replace ".","") on $($cache.FileNameWithoutExtension)."
        }
        $lockRetryAttempts++
        Start-Sleep -Milliseconds $lockRetryDelay.TotalMilliseconds
    }

    if ($lockRetryAttempts -gt 1) {
        $message = "Lock released."
        # $lockMeta = @{retryDelay = $script:lockRetryDelay; retryMaxAttempts = $script:lockRetryMaxAttempts; retryAttempts = $lockRetryAttempts} | ConvertTo-Json -Compress
        Write-Log -Action "WaitCache" -Target $cache.FileNameWithoutExtension -Status "CacheAvailable" -Message $message -Force # -Data $lockMeta
    }

    return

}