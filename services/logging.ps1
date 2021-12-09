
$global:logOptimalRecordCount = 5000
$global:logMaxRecordCount = 10000
$global:logMinRecordCount = 1000
$global:logFieldsExtended = @("ComputerName")
$global:logFieldsDefault = $([logentry]@{} | ConvertTo-Csv -UseQuotes Never)[0] -split "," | Where-Object {$_ -notin $logFieldsExtended}
$global:logFileHeader = $logFieldsDefault -join ","
$global:logFieldsQuoted = @("Target","Status","Message","Data")
$global:CommonParameters = $([System.Management.Automation.Internal.CommonParameters]).DeclaredProperties.Name
$global:LogLevels = @{
    None = 0
    Error = 100
    Warning = 200
    Information = 300
    Verbose = 400
    Debug = 500
    All = [int]::MaxValue
}


function global:Clear-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name = $global:Platform.Instance,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Newest")][int32]$Tail = $script:logMinRecordCount
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    foreach ($node in $ComputerName) {
        $log = Get-Log -Name $Name -Path $Path -ComputerName $node | Where-Object {([LogObject]$_).Exists()}
        $rows = Import-Csv -Path ([LogObject]$log).Path | Select-Object -Last $($Tail) 
        $rows | Export-Csv -Path ([LogObject]$log).Path -QuoteFields $logFieldsQuoted -NoTypeInformation
    }
    
    return # $log
}

function global:Optimize-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name = $global:Platform.Instance,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Newest")][int32]$Tail = $logOptimalRecordCount
    )

    Clear-Log -Name $Name -Path $Path -ComputerName $ComputerName -Tail $logOptimalRecordCount

    return

}

function global:Get-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$View,
        [switch]$UseDefaultView
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    $log = foreach ($node in $ComputerName) {
        [LogObject]::new($Path, $node)
    }

    return $log | Select-Object -Property $($View ? $LogObjectView.$($View) : $($LogObjectView.$($Name) -and !$UseDefaultView ? $LogObjectView.$($Name) : $LogObjectView.Default))

}

function global:New-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    $newLog = foreach ($node in $ComputerName){
        [LogObject]::new($Path, $node).New($logFileHeader)
    }

    return $newLog

}

function global:Watch-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name = $global:Platform.Instance,
        [Parameter(Mandatory=$false)][int]$Seconds = 15,
        [Parameter(Mandatory=$false)][int]$Tail = 10,
        [Parameter(Mandatory=$false)][string]$View,
        [switch]$UseDefaultView
    ) 

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $logEntry = read-log -Name $Name -Tail 10
    $lastIndex = $logEntry[$logEntry.Count-1].Index
    $logEntry | Select-Object -Property $($View ? $LogEntryView.$($View) : $($LogEntryView.$($Name) -and !$UseDefaultView ? $LogEntryView.$($Name) : $LogEntryView.Default)) | Format-Table

    while ($true) {
        $logEntry = read-log -Name $Name -FromIndex $lastIndex
        if ($logEntry) {
            $lastIndex = $logEntry[$logEntry.Count-1].Index
            $logEntry | Select-Object -Property $($View ? $LogEntryView.$($View) : $($LogEntryView.$($Name) -and !$UseDefaultView ? $LogEntryView.$($Name) : $LogEntryView.Default)) | Format-Table
        }
        start-sleep -Seconds $Seconds
    }

    return 

}

function global:Read-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name=$global:Platform.Instance,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Instance")][string]$Context,
        [Parameter(Mandatory=$false)][int32]$Tail,
        [Parameter(Mandatory=$false)][int32]$Head,
        [Parameter(Mandatory=$false)][Alias("Since")][DateTime]$After,
        [Parameter(Mandatory=$false)][DateTime]$Before,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][Alias("Id")][int64]$Index,
        [Parameter(Mandatory=$false)][int64]$FromIndex,
        [Parameter(Mandatory=$false)][int64]$ToIndex,
        [Parameter(Mandatory=$false)][Alias("Class")][string]$EntryType,
        [Parameter(Mandatory=$false)][Alias("Event")][string]$Action,
        [Parameter(Mandatory=$false)][int32]$Newest,
        [Parameter(Mandatory=$false)][int32]$Oldest,
        [Parameter(Mandatory=$false)][string]$View,
        [Parameter(Mandatory=$false)][string]$Sort,
        [Parameter(Mandatory=$false)][string]$Status,
        [switch]$UseDefaultView
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    if ($PSBoundParameters.ContainsKey('Head') -and $PSBoundParameters.ContainsKey('Tail')) {throw "Head and Tail cannot be used together."}
    if ($PSBoundParameters.ContainsKey('Newest') -and $PSBoundParameters.ContainsKey('Oldest')) {throw "Newest and Oldest cannot be used together."}
    if ($Index -and $Index -eq 0) {throw "Invalid Index"}
    if ($FromIndex -and $FromIndex -eq 0) {throw "Invalid FromIndex"}
    if ($ToIndex -and $ToIndex -eq 0) {throw "Invalid ToIndex"}
    if ($FromIndex -and $ToIndex -and $FromIndex -ge $ToIndex) {throw "Invalid FromIndex:ToIndex"}

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    $logEntry = @()
    foreach ($node in $ComputerName) {
        $log = Get-Log -Name $Name -Path $Path -ComputerName $node | Where-Object {([LogObject]$_).Exists()}
        if ($log) {
            $rows = Import-Csv -Path ([LogObject]$log).Path  | 
                Foreach-Object {
                    [LogEntry]@{
                        Index = [int]$_.Index
                        TimeStamp = $_.TimeStamp -as [datetime] ? [datetime]$_.TimeStamp : [DateTime]::FromFileTimeutc($_.TimeStamp)
                        EntryType = $_.EntryType
                        Context = $_.Context
                        Action = $_.Action
                        Status = $_.Status
                        Target = $_.Target
                        Message = $_.Message
                        Data = $_.Data
                        ComputerName = $log.ComputerName
                    } 
                }  

            $rows = $rows | Sort-Object -Property Index

            if ($($rows.Index | Sort-Object -Unique) -eq -1) {
                $rows = $rows | Sort-Object -Property TimeStamp
                for ($i = 0; $i -lt $rows.Count; $i++) {
                    $rows[$i].Index = $i
                }
            }

            if ($Tail) {$rows = $rows | Select-Object -Last $Tail}
            if ($Head) {$rows = $rows | Select-Object -First $Head}

            $logEntry += $rows
        }
    }

    if ($Index) {$logEntry = $logEntry | Where-Object {$_.Index -eq $Index}}
    if ($FromIndex) {$logEntry = $logEntry | Where-Object {$_.Index -gt $FromIndex}}
    if ($ToIndex) {$logEntry = $logEntry | Where-Object {$_.Index -le $ToIndex}}
    if ($Message) {$logEntry = $logEntry | Where-Object {$_.Message -eq $Message}}
    if ($EntryType) {$logEntry = $logEntry | Where-Object {$_.EntryType -eq $EntryType}}
    if ($After) {$logEntry = $logEntry | Where-Object {$_.TimeStamp -gt $After}}
    if ($Before) {$logEntry = $logEntry | Where-Object {$_.TimeStamp -lt $Before}}
    if ($Action) {$logEntry = $logEntry | Where-Object {$_.Action -eq $Action}}
    if ($Context) {$logEntry = $logEntry | Where-Object {$_.Context -eq $Context}}
    if ($Status) {$logEntry = $logEntry | Where-Object {$_.Status -eq $Status}}

    if ($Newest) {$logEntry = $logEntry | Select-Object -Last $Newest}
    if ($Oldest) {$logEntry = $logEntry | Select-Object -First $Oldest}

    # if (!$logEntry) {
    #    $FunctionParameters = $(Get-Command $PSCmdlet.MyInvocation.InvocationName).Parameters.Keys | Select-String -Pattern $CommonParameters -NotMatch
    #     if ($PSCmdlet.MyInvocation.BoundParameters.Keys | Select-String -Pattern $FunctionParameters) {
    #         Write-Information  "No records matched the filter criteria."
    #     }
    #     else {
    #         Write-Information  "$($log.Path) contains no records."
    #     }

    #     return
    # }

    # view priority:  caller-provided, product-specific, default
    # UseDefaultView overrides product-specific view and forces default view

    return $logEntry | Select-Object -Property $($View ? $LogEntryView.$($View) : $($LogEntryView.$($Name) -and !$UseDefaultView ? $LogEntryView.$($Name) : $LogEntryView.Default))

}

function global:Remove-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    $log = Get-Log -Name $Name -Path $Path -ComputerName $ComputerName | 
        Where-Object {([LogObject]$_).Exists()} | ForEach-Object {
            ([LogObject]$_).Remove()
    }

    return $log

}
function global:Repair-Log {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name = $global:Platform.Instance,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    foreach ($node in $ComputerName) {

        $log = Get-Log -Name $Name -Path $Path -ComputerName $node | Where-Object {([LogObject]$_).Exists()}
        if ($log) {
            $logEntry = Import-Csv -Path ([LogObject]$log).Path

            if ($($logEntry.Index | Sort-Object -Unique) -eq -1) {
                throw {"$($log.Path) cannot be reindexed."}
            }
        
            for ($i=0;$i -lt $logEntry.Count;$i++) {$logEntry[$i].Index = $i}

            $logEntry | Select-Object -Property $logFieldsDefault | 
                Export-Csv -Path ([LogObject]$log).Path -QuoteFields $logFieldsQuoted -NoTypeInformation
        }

    }

    return
}

function global:Merge-Log {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$From,
        [Parameter(Mandatory=$false,Position=0)][string]$To,
        [Parameter(Mandatory=$false,Position=0)][string]$Exclude="OverWatch",
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $pathFrom = $Path ? $Path : "$($global:Location.Logs)" + $($From ? "\$($From).log" : "\*.log")
    $pathTo = $global:Location.Logs + $($To ? "\$($To).log" : "\merged.log")

    foreach ($node in $ComputerName) {
        $logs = Get-Log -Name $From -Path $pathFrom -ComputerName $node | Where-Object {([LogObject]$_).Exists() -and ([LogObject]$_).Name -ne $Exclude}
        foreach ($log in $logs.FileInfo) {

            $logEntry += Import-Csv -Path $log | Foreach-Object {
                [LogEntry]@{
                    Index = [int]$_.Index
                    TimeStamp = $_.TimeStamp -as [datetime] ? [datetime]$_.TimeStamp : [DateTime]::FromFileTimeutc($_.TimeStamp)
                    EntryType = $_.EntryType
                    Context = $_.Context
                    Action = $_.Action
                    Status = $_.Status
                    Target = $_.Target
                    Message = $_.Message
                    ComputerName = $log.ComputerName
                } 
            }  

        }
    }

    $logEntry = $logEntry | Sort-Object -Property TimeStamp

    if ($($logEntry.Index | Sort-Object -Unique) -eq -1) {
        throw {"$($log.Path) cannot be reindexed."}
    }

    for ($i=0;$i -lt $logEntry.Count;$i++) {$logEntry[$i].Index = $i}

    $logEntry | Select-Object -Property $logFieldsDefault | 
        Export-Csv -Path $pathTo -QuoteFields $logFieldsQuoted -NoTypeInformation

    return
}

function global:Test-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")
    $log = Get-Log -Name $Name -Path $Path -ComputerName $ComputerName

    Write-Host+ -NoTrace -IfDebug "Row Count: $(([LogObject]$log).Count())"
    Write-Host+ -NoTrace -IfDebug "logMaxRecordCount: $logMaxRecordCount"
    Write-Host+ -NoTrace -IfDebug "logOptimalRecordCount: $logOptimalRecordCount"

    return ([LogObject]$log).Exists()
}

function global:Write-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id,
        [Parameter(Mandatory=$false,Position=0)][string]$Name = $global:Platform.Instance,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Data,
        [Parameter(Mandatory=$false)][ValidateSet("Information","Warning","Error","Verbose","Debug")][string]$EntryType = 'Information',
        [Parameter(Mandatory=$false)][string]$Action="Log",
        [Parameter(Mandatory=$false)][string]$Status,
        [Parameter(Mandatory=$false)][string]$Target,
        [Parameter(Mandatory=$false)][string]$LogLevel = "Warning",
        [switch]$Force

    )

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    Write-Debug "LogLevel: $($LogLevel)"
    Write-Debug "EntryType: $($EntryType)"

    if (!$Force -and $LogLevels.$EntryType -ge $LogLevels.$LogLevel) {return}

    $Path = $Path ? $Path : "$($global:Location.Logs)" + $($Name ? "\$($Name).log" : "\*.log")

    $logEntry = 
        [LogEntry]@{
            Index = -1
            TimeStamp = $(Get-Date)
            EntryType = $EntryType
            Context = $Context
            Action = $Action
            Target = $Target
            Message = $Message
            Data = $Data
            Status = $Status
        }    
    
    foreach ($node in $ComputerName) {
        $log = Get-Log -Name $Name -Path $Path -ComputerName $node | Where-Object {([LogObject]$_).Exists()}
        if ($log) {

            $logRecordCount = ([LogObject]$log).Count()
            if ($logRecordCount -ge $logMaxRecordCount) {
                Optimize-Log -Name $Name -Tail $logOptimalRecordCount
                $logRecycleData = @{
                    name = $Name
                    logRecordCount = $logRecordCount
                    logMaxRecordCount = $logMaxRecordCount
                    logOptimalRecordCount = $logOptimalRecordCount
                    timestamp = Get-Date -AsUTC
                } | ConvertTo-Json -Compress
                Write-Log -Name $Name -Action Recycle -Target $Name -Data $logRecycleData -Force
            }

            try {
                $lastLogEntry = Read-Log -Tail 1 -Path ([LogObject]$log).Path
                $logEntry.Index = [int]$lastLogEntry.Index
            }
            catch {
                $logEntry.Index = -1
            }
            $logEntry.Index++

            $logEntry | Export-Csv -Path ([LogObject]$log).Path -Append -QuoteFields $logFieldsQuoted -NoTypeInformation
        }
    }

    return

}