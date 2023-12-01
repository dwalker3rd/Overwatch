#region PLATFORM DEFINITIONS

    $global:Platform =
        [Platform]@{
            Id = "AlteryxDesigner"
            Name = "Alteryx Designer"
            DisplayName = "Alteryx Designer"
            Image = "$($global:Location.Images)/alteryx_a_logo.png"
            Description = ""
        }

    $global:PlatformDictionary = @{
        AlteryxEngine = "AlteryxEngine"
        AlteryxEngineCmd = "AlteryxEngineCmd"
        LastRunTime = "Last Run Time"
        NextRunTime = "Next Run Time"
        Start = "Running"
        Stop = "Stopped"
    }     

    $global:PlatformServiceConfig = @(
        [PlatformCim]@{
            Name = "AlteryxService"
            DisplayName = $PlatformDictionary.AlteryxService
            StatusOK = $ServiceUpState
            Required = $true
            Class = "Service"
        }
    )

    $global:PlatformProcessConfig = @(
        [PlatformCim]@{
            Name = "AlteryxService"
            DisplayName = $PlatformDictionary.AlteryxServiceProcess
            StatusOK = "Responding"
            Required = $true
            Class = "Process"
        },
        [PlatformCim]@{
            Name = "AlteryxEngineCmd"
            DisplayName = $PlatformDictionary.AlteryxEngineCmd
            StatusOK = "Responding"
            Required = $true
            Transient = $true
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Worker"
        }
    )

    $global:PlatformStatusColor = @{
        Stopping = "DarkYellow"
        Stopped = "DarkRed"
        Starting = "DarkYellow"
        Restarting = "DarkYellow"
        Running = "DarkGreen"
        Responding = "DarkGreen"
        Online = "DarkGreen"
        Offline = "DarkGray"
        Degraded = "DarkRed"
        Shutdown = "DarkGray"
        Unknown = "DarkGray"
    }     

    $global:Location += @{
        RuntimeSettings = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
    }  

#endregion PLATFORM DEFINITIONS