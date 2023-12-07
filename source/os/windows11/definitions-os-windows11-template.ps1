#region WINDOWS SERVER DEFINITIONS

    $global:OS = $global:Catalog.OS.WindowsServer
    $global:OS.Image = "$($global:Location.Images)/windows_server.png" 

#endregion WINDOWS SERVER DEFINITIONS
#region SERVER EVENTS

    $global:ServerEvent = @{
        Startup = "Startup"
        Shutdown = "Shutdown"
    }

    $global:ServerEventStatus = @{
        InProgress = "In Progress"
        Completed = "Completed"
    }

#endregion SERVER EVENTS
#region SERVICE STATES

    $global:ServiceDownState = @("Stopped","StopPending","StartPending")
    $global:ServiceUpState = @("Running")
    $global:ServiceAnyState = $global:ServiceDownState + $global:ServiceUpState

#endregion SERVICE STATES
#region PERFORMANCE COUNTERS

    $global:PerformanceCounters = @(
        [PerformanceMeasurement]@{Class="Win32_PerfFormattedData_PerfOS_Processor";Instance="_Total";Counter="PercentProcessorTime";Name="Processor Utilization";Suffix="%"},
        [PerformanceMeasurement]@{Class="Win32_PerfFormattedData_PerfOS_Memory";Counter="AvailableBytes";Name="Available Memory";Suffix=" GB";Factor=1/1gb}
    )
    $global:PerformanceCounterMaxSamples = 5
    $global:PerformanceMeasurementampleInterval = 0 

#endregion PERFORMANCE COUNTERS