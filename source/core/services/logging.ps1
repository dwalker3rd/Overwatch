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
    Event = 50
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
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Newest")][int32]$Tail = $script:logMinRecordCount
    )

    foreach ($node in $ComputerName) {
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")
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

    foreach ($node in $ComputerName) {
        Clear-Log -Name $Name -Path $Path -ComputerName $node -Tail $logOptimalRecordCount
    }

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

    $log = foreach ($node in $ComputerName) {
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")
        [LogObject]::new($Path, $node)
    }

    return $log | Select-Object -Property $($View ? $LogObjectView.$($View) : $($LogObjectView.$($Name) -and !$UseDefaultView ? $LogObjectView.$($Name) : $LogObjectView.Default))

}

function global:New-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    $newLog = foreach ($node in $ComputerName){
        if ([string]::IsNullOrEmpty($Name)) { $Name = Get-EnvironConfig Environ.Instance -ComputerName $node }
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")
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
        [switch]$UseDefaultView,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    ) 

    $logEntry = Read-Log -Name $Name -ComputerName $ComputerName -Tail 10
    $lastIndex = $logEntry[$logEntry.Count-1].Index
    $logEntry | Select-Object -Property $($View ? $LogEntryView.$($View) : $($LogEntryView.$($Name) -and !$UseDefaultView ? $LogEntryView.$($Name) : $LogEntryView.Default)) | Format-Table

    while ($true) {
        $logEntry = Read-Log -Name $Name -ComputerName $ComputerName -FromIndex $lastIndex
        if ($logEntry) {
            $lastIndex = $logEntry[$logEntry.Count-1].Index
            $logEntry | Select-Object -Property $($View ? $LogEntryView.$($View) : $($LogEntryView.$($Name) -and !$UseDefaultView ? $LogEntryView.$($Name) : $LogEntryView.Default)) | Format-Table
        }
        Start-Sleep -Seconds $Seconds
    }

    return 

}

function global:Read-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
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
    
    if ($PSBoundParameters.ContainsKey('Head') -and $PSBoundParameters.ContainsKey('Tail')) {throw "Head and Tail cannot be used together."}
    if ($PSBoundParameters.ContainsKey('Newest') -and $PSBoundParameters.ContainsKey('Oldest')) {throw "Newest and Oldest cannot be used together."}
    if ($Index -and $Index -eq 0) {throw "Invalid Index"}
    if ($FromIndex -and $FromIndex -eq 0) {throw "Invalid FromIndex"}
    if ($ToIndex -and $ToIndex -eq 0) {throw "Invalid ToIndex"}
    if ($FromIndex -and $ToIndex -and $FromIndex -ge $ToIndex) {throw "Invalid FromIndex:ToIndex"}

    $logEntry = @()
    foreach ($node in $ComputerName) {

        # if $Name not specified, get the node's platform instance
        if ([string]::IsNullOrEmpty($Name)) { $Name = Get-EnvironConfig Environ.Instance -ComputerName $node }

        # if $Path not specified, build the path with the node's $Location.Logs definition and $Name
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")

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

    return $logEntry | Select-Object -Property $($View ? $LogEntryView.$($View) : $($LogEntryView.$($Name) -and !$UseDefaultView ? $LogEntryView.$($Name) : $LogEntryView.Default))

}

function global:Summarize-Log {

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute("PsUseApprovedVerbs", "")]

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][Alias("Since")][object]$After,
        [Parameter(Mandatory=$false)][int32]$Days,
        [Parameter(Mandatory=$false)][int32]$Hours,
        [Parameter(Mandatory=$false)][int32]$Minutes,
        [Parameter(Mandatory=$false)][Alias("Until")][object]$Before,
        [Parameter(Mandatory=$false)][object]$During,
        [Parameter(Mandatory=$false)][Alias("Last")][int32]$Newest,
        [Parameter(Mandatory=$false)][Alias("First")][int32]$Oldest,
        [Parameter(Mandatory=$false)][string]$View,
        [switch]$UseDefaultView,
        [switch]$Today,
        [switch]$Yesterday,
        [Parameter(Mandatory=$false)][ValidateSet("All","Event","Error","Warning","Information","None","Default")][string[]]$ShowDetails = "Default"
    )

    if ($ShowDetails -eq "All") { $ShowDetails += @("Event","Error","Warning","Information") }
    if ($ShowDetails -eq "Default") { $ShowDetails += @("Event","Error","Warning") }

    $defaultColor = $global:consoleSequence.BackgroundForegroundDefault
    
    $formatData = [ordered]@{}
    $logSummaryFormatData = Get-FormatData -TypeName Overwatch.Log.Summary
    $formatDataDisplayEntries = $logSummaryFormatData.FormatViewDefinition.Control.Rows.Columns.DisplayEntry.Value
    $formatDataHeaders = $logSummaryFormatData.FormatViewDefinition.Control.Headers
    for ($i = 0; $i -lt $formatDataDisplayEntries.Count; $i++) {
        $formatData += @{
            $formatDataDisplayEntries[$i] = $formatDataHeaders[$i]
        }
    }

    # $After is a datetime passed as an object
    # This allows using strings to specify today or yesterday

    $After = $Days ? ([datetime]::Today).AddDays(-1 * [math]::Abs($Days)) : $After
    $After = $Hours ? ([datetime]::Now).AddHours(-1 * [math]::Abs($Hours)) : $After
    $After = $Minutes ? ([datetime]::Now).AddMinutes(-1 * [math]::Abs($Minutes)) : $After

    If (![string]::IsNullOrEmpty($After)) {
        $After = switch ($After) {
            "Today" { [datetime]::Today }
            "Yesterday" { ([datetime]::Today).AddDays(-1) }
            default { 
                switch ($After.GetType().Name) {
                    "String" { Get-Date ($After) }
                    "DateTime" { $After }
                    "TimeSpan" { [datetime]::Today.Add(-$After.Duration()) }
                }
            }
        }
    }

    If (![string]::IsNullOrEmpty($Before)) {
        $Before = switch ($Before) {
            "Today" { [datetime]::Today }
            "Yesterday" { ([datetime]::Today).AddDays(-1) }
            default { 
                switch ($Before.GetType().Name) {
                    "String" { Get-Date ($Before) }
                    "DateTime" { $Before }
                    "TimeSpan" { [datetime]::Today.Add(-$Before.Duration()) }
                }
            }
        }
    }

    Write-Host+ -ResetAll
    Write-Host+

    $summary = @()
    $summaryFormatted = @()
    $logEntries = @()

    foreach ($node in $ComputerName) {
        $logs = @() 
        if (![string]::IsNullOrEmpty($Name)) {
            $log = Get-Log -Name $Name -ComputerName $node | Where-Object {([LogObject]$_).Exists()}
            if ($log) { $logs += $log }
        }
        else {
            foreach ($logFileInfo in (Get-Log -ComputerName $node).FileInfo) {
                $logName = [Path]::GetFileNameWithoutExtension($logFileInfo.Name)
                $logs += Get-Log -Name $logName -ComputerName $node
            }
        }

        foreach ($log in $logs) {

            $logEntry = Read-Log -Name $log.FileNameWithoutExtension.ToLower() -ComputerName $node.ToLower()

            if ($After) {$logEntry = $logEntry | Where-Object {$_.TimeStamp -gt $After}}
            if ($Before) {$logEntry = $logEntry | Where-Object {$_.TimeStamp -lt $Before}}
            if ($Newest) {$logEntry = $logEntry | Select-Object -Last $Newest}
            if ($Oldest) {$logEntry = $logEntry | Select-Object -First $Oldest}

            if ($logEntry.Count -gt 0) {

                $logName = $log.FileNameWithoutExtension.ToLower()

                # $totals = [array]($logEntry | Group-Object -Property EntryType -NoElement)
                # $infoCount = ($totals | Where-Object {$_.Name -eq "Information"}).Count ?? 0
                # $warningCount = ($totals | Where-Object {$_.Name -eq "Warning"}).Count ?? 0
                # $errorCount = ($totals | Where-Object {$_.Name -eq "Error"}).Count ?? 0

                $totals = [array]($logEntry | Group-Object -Property EntryType)
                $infos = $totals | Where-Object {$_.Name -eq "Information"}
                $infoCount = $infos.Count ?? 0
                $warnings = $totals | Where-Object {$_.Name -eq "Warning"}
                $warningCount = $warnings.Count ?? 0
                $errors = $totals | Where-Object {$_.Name -eq "Error"}
                $errorCount = $errors.Count ?? 0
                $events = $totals | Where-Object {$_.Name -eq "event"}
                # $eventCount = $events.Count ?? 0

                # this is only used to determine max column width in the table headers below
                $summary += [PSCustomObject]@{
                    PSTypeName = "Overwatch.Log.Summary"
                    Log = $logName
                    Rows = "$($logEntry.Count)"
                    Information = "$($infoCount)"
                    Warning = "$($warningCount)"
                    Error = "$($errorCount)"
                    MinTimeStamp = ($After ?? ((($logEntry | Select-Object -First 1).TimeStamp).AddSeconds(-1))).ToString('u')
                    MaxTimeStamp = ($Before ?? ((($logEntry | Select-Object -Last 1).TimeStamp).AddSeconds(1))).ToString('u')
                    ComputerName = $node.ToLower()
                }

                $infoColor = $infoCount -gt 0 ? $defaultColor : $global:consoleSequence.ForegroundDarkGrey
                $warningColor = $warningCount -gt 0 ? $global:consoleSequence.ForegroundYellow : $global:consoleSequence.ForegroundDarkGrey
                $errorColor = $errorCount -gt 0 ? $global:consoleSequence.ForegroundRed : $global:consoleSequence.ForegroundDarkGrey
                $eventColorBright = $global:consoleSequence.BrightForegroundCyan
                $eventColorDark = $global:consoleSequence.ForegroundCyan
                $logColor = $errorCount -gt 0 ? $errorColor : ($warningCount -gt 0 ? $warningColor : $global:consoleSequence.ForegroundDarkGrey)
                $countColor = $logEntry.Count -gt 0 ? $defaultColor : $global:consoleSequence.ForegroundDarkGrey
        
                # format summary rows with console sequences to control color
                $summaryFormatted += [PSCustomObject]@{
                    # these fields are NOT displayed
                    PSTypeName = "Overwatch.Log.Summary"
                    Node = $node.ToLower()
                    # these fields ARE displayed
                    ComputerName = "$($logColor)$($node.ToLower())$($defaultColor)"
                    Log = "$($logColor)$($logName)$($emptyString.PadLeft($formatData.Log.Width-$logName.Length))$($defaultColor)"
                    Rows = "$($countColor)$($logEntry.Count)$($defaultColor)"
                    Information = "$($infoColor)$($infoCount)$($defaultColor)"
                    Warning = "$($warningColor)$($warningCount)$($defaultColor)"
                    Error = "$($errorColor)$($errorCount)$($defaultColor)"
                    MinTimeStamp = "$($global:consoleSequence.ForegroundDarkGrey)$(($After ?? ((($logEntry | Select-Object -First 1).TimeStamp).AddSeconds(-1))).ToString('u'))$($defaultColor)"
                    MaxTimeStamp = "$($global:consoleSequence.ForegroundDarkGrey)$(($Before ?? ((($logEntry | Select-Object -Last 1).TimeStamp).AddSeconds(1))).ToString('u'))$($defaultColor)"
                }

                $_fieldsToHightlight = @("LogName","TimeStamp","EntryType","Message","Context","Action","Target","Status")

                foreach ($_info in $infos.Group) {
                    $_timestamp = $_info.Timestamp
                    foreach ($key in $_info.psobject.properties.name) {
                        if ($_info.$key -ne "ComputerName") {
                            $_info.$key = "$($global:consoleSequence.ForegroundDarkGrey)$($_info.$key)$($defaultColor)"
                        }
                    }
                    $logEntries += [PSCustomObject]@{
                        Node = $node
                        LogName = "$($global:consoleSequence.ForegroundDarkGrey)$($logName)$($defaultColor)"
                        Type = "Information"
                        LogEntry = $_info
                        TimeStamp = $_timeStamp
                    }
                }
                foreach ($_warning in $warnings.Group) {
                    $_timeStamp = $_warning.TimeStamp
                    foreach ($key in $_warning.psobject.properties.name) {
                        $_warning.$key = 
                            if ($key -in $_fieldsToHightlight) {
                                "$($warningColor)$($_warning.$key)$($defaultColor)"
                            }
                            else {
                                "$($global:consoleSequence.ForegroundDarkGrey)$($_warning.$key)$($defaultColor)" 
                            }
                    }
                    $logEntries += [PSCustomObject]@{
                        Node = $node
                        LogName = "LogName" -in $_fieldsToHightlight ? "$($warningColor)$($logName)$($defaultColor)" : "$($global:consoleSequence.ForegroundDarkGrey)$($logName)$($defaultColor)"
                        Type = "Warning"
                        LogEntry = $_warning
                        TimeStamp = $_timeStamp
                    }
                }
                foreach ($_error in $errors.Group) {
                    $_timeStamp = $_error.TimeStamp
                    foreach ($key in $_error.psobject.properties.name) {
                        $_error.$key = 
                            if ($key -in $_fieldsToHightlight) {
                                "$($errorColor)$($_error.$key)$($defaultColor)"
                            }
                            else {
                                "$($global:consoleSequence.ForegroundDarkGrey)$($_error.$key)$($defaultColor)" 
                            }
                    }
                    $logEntries += [PSCustomObject]@{
                        Node = $node
                        LogName = "LogName" -in $_fieldsToHightlight ? "$($errorColor)$($logName)$($defaultColor)" : "$($global:consoleSequence.ForegroundDarkGrey)$($logName)$($defaultColor)"
                        Type = "Error"
                        LogEntry = $_error
                        TimeStamp = $_timeStamp
                    }
                }
                foreach ($_event in $events.Group) {
                    $_timeStamp = $_event.TimeStamp
                    # $_fieldsToHightlight = @("EntryType","Context","Action","Target","Status")
                    foreach ($key in $_event.psobject.properties.name) {
                        $_event.$key = 
                            if ($key -in $_fieldsToHightlight) {
                                "$($eventColorBright)$($_event.$key)$($defaultColor)"
                            }
                            else {
                                "$($global:consoleSequence.ForegroundDarkGrey)$($_event.$key)$($defaultColor)" 
                            }
                    }
                    $logEntries += [PSCustomObject]@{
                        Node = $node
                        LogName = "LogName" -in $_fieldsToHightlight ? "$($eventColorBright)$($logName)$($defaultColor)" : "$($global:consoleSequence.ForegroundDarkGrey)$($logName)$($defaultColor)"
                        Type = "Event"
                        LogEntry = $_event
                        TimeStamp = $_timeStamp
                    }
                }
            }
            
        }
    }

    if ($summaryFormatted) { Write-Host+ }

    foreach ($node in $ComputerName) {

        $summaryFormattedByNode = $summaryFormatted | Where-Object {$_.Node -eq $node}
        if ($summaryFormattedByNode) {

            Write-Host+ -NoTrace -NoTimestamp -NoNewLine "   ComputerName: " 
            Write-Host+ -NoTrace -NoTimestamp $node.ToLower() -ForegroundColor Darkgray
            Write-Host+

            # write column labels
            foreach ($key in $formatData.Keys) {
                $columnWidth = $key -in ("Log","ComputerName") ? $formatData.$key.Width : ($summary.$key | Measure-Object -Property Length -Maximum).Maximum
                $columnWidth = $columnWidth -lt $formatData.$key.Label.Length ? $formatData.$key.Label.Length : $columnWidth
                $header = "$($global:consoleSequence.ForegroundDarkGrey)$($formatData.$key.Label)$($emptyString.PadLeft($columnWidth-$formatData.$key.Label.Length))$($defaultColor) "
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine $header
                if ($formatData.$key.Label -in @("Log","Error","Warn")) {
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine " "
                }
            }
            Write-Host+

            # underline column labels
            foreach ($key in $formatData.Keys) {
                $underlineChar = $formatData.$key.Label.Trim().Length -gt 0 ? "-" : " "
                $columnWidth = $key -in ("Log","ComputerName") ? $formatData.$key.Width : ($summary.$key | Measure-Object -Property Length -Maximum).Maximum
                $columnWidth = $columnWidth -lt $formatData.$key.Label.Length ? $formatData.$key.Label.Length : $columnWidth
                $header = "$($global:consoleSequence.ForegroundDarkGrey)$($emptyString.PadLeft($formatData.$key.Label.Length,$underlineChar))$($emptyString.PadLeft($columnWidth-$formatData.$key.Label.Length," "))$($defaultColor) "
                Write-Host+ -NoTrace -NoTimestamp -NoNewLine $header
                if ($formatData.$key.Label -in @("Log","Error","Warn")) {
                    Write-Host+ -NoTrace -NoTimestamp -NoNewLine " "
                }
            }

            $summaryFormattedByNode | Where-Object {$_.Node -eq $node} | Format-Table -HideTableHeaders

        }

    }

    foreach ($node in $ComputerName) {

        $platformEventHistory = Get-PlatformEventHistory -ComputerName $node
        if ($After) {$platformEventHistory = $platformEventHistory | Where-Object {$_.TimeStamp -gt $After}}
        if ($Before) {$platformEventHistory = $platformEventHistory | Where-Object {$_.TimeStamp -lt $Before}}

        if (![string]::IsNullOrEmpty($ShowDetails) -and $ShowDetails -ne "None") {

            $logEntriesByNode = $logEntries | Where-Object {$_.type -in $ShowDetails -and $_.Node -eq $node}

            #find matching platform events
            foreach ($logEntry in $logEntriesByNode) {
                $_event = $platformEventHistory | Where-Object {$_.TimeStamp -le (Get-Date($logEntry.TimeStamp) -Millisecond 0)} | Select-Object -Last 1
                if ($_event) {
                    $_eventColor = $logEntry.Type -eq "Event" ? $eventColorBright : $eventColorDark
                    $_timestampDiff = $_.TimeStamp - $logEntry.timeStamp
                    if (!($_event.Event -eq "Start" -and $_event.EventHasCompleted -and [math]::Abs($_timestampDiff.TotalSeconds) -gt 30)) {
                        $logEntry | Add-Member -NotePropertyName Event -NotePropertyValue "$($_eventColor)$($_event.Event)$($defaultColor)" 
                        $logEntry | Add-Member -NotePropertyName EventStatus -NotePropertyValue "$($_eventColor)$($_event.EventStatus)$($defaultColor)" 
                    }
                }
            }        

            # Write-Host+ -NoTimestamp -NoTrace "   $($global:consoleSequence.ForegroundDarkGrey)Details: $($ShowDetails -join ", ")$($defaultColor)"

            if ($logEntriesByNode.Count -gt 0) {
                $logEntriesByNode | 
                    Sort-Object -Property TimeStamp -Descending | 
                        Select-Object LogName,Event,EventStatus -ExpandProperty logEntry |
                            Select-Object ComputerName,LogName,Index,TimeStamp,EntryType,Context,Action,Target,Status,Event,EventStatus,Message | 
                                Format-Table * -GroupBy ComputerName # -HideTableHeaders
            }
        }

    }

}
Set-Alias -Name logSummary -Value Show-LogSummary -Scope Global

function global:Remove-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    $log = @()
    foreach ($node in $ComputerName) {

        # if $Path not specified, build the path with the node's $Location.Logs definition and $Name
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")

        $log += Get-Log -Name $Name -Path $Path -ComputerName $node | 
            Where-Object {([LogObject]$_event).Exists()} | ForEach-Object {
                ([LogObject]$_).Remove()
        }

    }

    return $log

}
function global:Repair-Log {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME
    )

    foreach ($node in $ComputerName) {

        if ([string]::IsNullOrEmpty($Name)) { $Name = Get-EnvironConfig Environ.Instance -ComputerName $node }
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log") 
        $logs = Get-Log -Name $Name -Path $Path -ComputerName $node | Where-Object {([LogObject]$_).Exists()}

        $logEntry = @()
        foreach ($log in $logs) {

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

    foreach ($node in $ComputerName) {

        $pathFrom = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($From ? "\$($From).log" : "\*.log")
        $pathTo = (Get-EnvironConfig Location.Logs -ComputerName $node) + $($To ? "\$($To).log" : "\merged.log")  
        $logs = Get-Log -Name $From -Path $pathFrom -ComputerName $node | Where-Object {([LogObject]$_).Exists() -and ([LogObject]$_).Name -ne $Exclude}

        $logEntry = @()
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

        $logEntry = $logEntry | Sort-Object -Property TimeStamp

        if ($($logEntry.Index | Sort-Object -Unique) -eq -1) {
            throw {"$($log.Path) cannot be reindexed."}
        }
    
        for ($i=0;$i -lt $logEntry.Count;$i++) {$logEntry[$i].Index = $i}
    
        $logEntry | Select-Object -Property $logFieldsDefault | 
            Export-Csv -Path $pathTo -QuoteFields $logFieldsQuoted -NoTypeInformation
    }

    return
    
}

function global:Test-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME
    )

    $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $ComputerName) + $($Name ? "\$($Name).log" : "\*.log")

    if (!(Test-Path $Path)) {return $false}

    $log = Get-Log -Name $Name -Path $Path -ComputerName $ComputerName

    # Write-Host+ -NoTrace -IfDebug "Row Count: $(([LogObject]$log).Count())"
    # Write-Host+ -NoTrace -IfDebug "logMaxRecordCount: $logMaxRecordCount"
    # Write-Host+ -NoTrace -IfDebug "logOptimalRecordCount: $logOptimalRecordCount"

    return ([LogObject]$log).Exists()
}

function global:Write-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Context = $global:Product.Id,
        [Parameter(Mandatory=$false,Position=0)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Data,
        [Parameter(Mandatory=$false)][ValidateSet("Information","Warning","Error","Verbose","Debug","Event")][string]$EntryType = 'Information',
        [Parameter(Mandatory=$false)][string]$Action="Log",
        [Parameter(Mandatory=$false)][string]$Status,
        [Parameter(Mandatory=$false)][string]$Target,
        [Parameter(Mandatory=$false)][string]$LogLevel = "Warning",
        [Parameter(Mandatory=$false)][datetime]$TimeStamp = [datetime]::Now,
        [switch]$Force
    )

    if (!$Force -and $LogLevels.$EntryType -gt $LogLevels.$LogLevel) { return }

    if ([string]::IsNullOrEmpty($Name)) {
        # $Context can be something that is not a valid catalog object such as "Azure Update Management"
        # thus the need to append -ErrorAction SilentlyContinue to the call to Get-Catalog
        $Name = (Get-Catalog $Context -ErrorAction SilentlyContinue).Log ? ((Get-Catalog $Context -ErrorAction SilentlyContinue).Log).ToLower() : $Platform.Instance
        if (!(Test-Log -Name $Name)) {
            New-Log -Name $Name | Out-Null
        }
    }

    # $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")

    $logEntry = 
        [LogEntry]@{
            Index = -1
            TimeStamp = $TimeStamp
            EntryType = $EntryType
            Context = $Context
            Action = $Action
            Target = $Target
            Message = $Message
            Data = $Data
            Status = $Status
        }    
    
    foreach ($node in $ComputerName) {

        # if $Path not specified, build the path with the node's $Location.Logs definition and $Name
        $Path = $Path ? $Path : (Get-EnvironConfig Location.Logs -ComputerName $node) + $($Name ? "\$($Name).log" : "\*.log")
        $log = Get-Log -Name $Name -Path $Path -ComputerName $node | Where-Object {([LogObject]$_).Exists()}

        if ($log) {

            $logRecordCount = ([LogObject]$log).Count()
            if ($logRecordCount -ge $logMaxRecordCount) {
                Optimize-Log -Name $Name -ComputerName $node -Tail $logOptimalRecordCount
                $logRecycleData = @{
                    name = $Name
                    logRecordCount = $logRecordCount
                    logMaxRecordCount = $logMaxRecordCount
                    logOptimalRecordCount = $logOptimalRecordCount
                    timestamp = Get-Date -AsUTC
                } | ConvertTo-Json -Compress
                Write-Log -Name $Name -ComputerName $node -Action Recycle -Target $Name -Data $logRecycleData -Force
            }

            try {
                $lastLogEntry = Read-Log -ComputerName $node -Tail 1 -Path ([LogObject]$log).Path
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