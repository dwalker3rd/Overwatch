#region WINDOWS DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    $global:OS = [OS]@{
        Id = "WindowsServer"
        Name = "Windows Server"
        DisplayName = "Windows Server"
        Image = "$($global:Location.Images)/windows_server.png"  
    }

    $global:ServerEvent = @{
        Startup = "Startup"
        Shutdown = "Shutdown"
    }

    $global:ServerEventStatus = @{
        InProgress = 'In Progress'
        Completed = 'Completed'
    }

    $global:PerformanceCounters = @(
        [PerformanceMeasurement]@{Class="Win32_PerfFormattedData_PerfOS_Processor";Instance="_Total";Counter="PercentProcessorTime";Name="Processor Utilization";Suffix="%"},
        [PerformanceMeasurement]@{Class="Win32_PerfFormattedData_PerfOS_Memory";Counter="AvailableBytes";Name="Available Memory";Suffix=" GB";Factor=1/1gb} #,
        # [PerformanceMeasurement]@{Class="Win32_LogicalDisk";Instance="C:";Counter="Size";Name="Size (C:)";Suffix=" GB";Factor=1/1gb;SingleSampleOnly="True"},
        # [PerformanceMeasurement]@{Class="Win32_PerfFormattedData_PerfDisk_LogicalDisk";Instance="C:";Counter="PercentFreeSpace";Name="Free Space (C:)";Suffix="%"}, #;SingleSampleOnly="True"},
        # [PerformanceMeasurement]@{Class="Win32_PerfFormattedData_Tcpip_NetworkAdapter";Instance="Microsoft Hyper-V Network Adapter";Counter="BytesTotalPerSec";Name="Network Bytes Total/sec";Factor=1/1kb;Suffix=" KB"}
    )
    $global:PerformanceCounterMaxSamples = 5
    $global:PerformanceMeasurementampleInterval = 0 

#endregion WINDOWS DEFINITIONS