#region PLATFORM DEFINITIONS

    $global:Platform =
        [Platform]@{
            Id = "AlteryxServer"
            Name = "Alteryx Server"
            DisplayName = "Alteryx Server"
            Image = "$($global:Location.Images)/alteryx_a_logo.png"
            Description = ""
        }

    $global:PlatformDictionary = @{
        AlteryxService = "AlteryxService"
        AlteryxServiceProcess = "AlteryxService"
        AlteryxServerHost = "ServerHost"
        AlteryxService_MongoController = "MongoController"
        AlteryxEngineCmd = "AlteryxEngine"
        AlteryxService_MapRenderWorker = "MapRenderer"
        AlteryxCEFRenderer = "CEFRenderer"
        AlteryxAuthHost = "AuthHost"
        AlteryxService_WebInterface = "WebInterface"
        AlteryxMetrics = "Metrics"
        mongod = "MongoDB"
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
            Name = "AlteryxServerHost"
            DisplayName = $PlatformDictionary.AlteryxServerHost
            StatusOK = "Responding"
            Required = $true
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Gallery"
        },
        [PlatformCim]@{
            Name = "AlteryxService_MongoController"
            DisplayName = $PlatformDictionary.AlteryxService_MongoController
            StatusOK = "Responding"
            Required = $true
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Database"
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
        },
        [PlatformCim]@{
            Name = "AlteryxService_MapRenderWorker"
            DisplayName = $PlatformDictionary.AlteryxService_MapRenderWorker
            StatusOK = "Responding"
            Required = $false
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Worker"
        },
        # [PlatformCim]@{
        #     Name = "AlteryxCEFRenderer"
        #     DisplayName = $PlatformDictionary.AlteryxCEFRenderer
        #     StatusOK = "Responding"
        #     Required = $false
        #     Class = "Process"
        #     ParentName = ???
        # },
        [PlatformCim]@{
            Name = "AlteryxAuthHost"
            DisplayName = $PlatformDictionary.AlteryxAuthHost
            StatusOK = "Responding"
            Required = $false
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Gallery"
        },
        [PlatformCim]@{
            Name = "AlteryxService_WebInterface"
            DisplayName = $PlatformDictionary.AlteryxService_WebInterface
            StatusOK = "Responding"
            Required = $false
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Gallery"
        },
        [PlatformCim]@{
            Name = "AlteryxMetrics"
            DisplayName = $PlatformDictionary.AlteryxMetrics
            StatusOK = "Responding"
            Required = $true
            Class = "Process"
            ParentName = @("AlteryxService","")
            Component = "Controller","Gallery", "Worker"
        },
        [PlatformCim]@{
            Name = "mongod"
            DisplayName = $PlatformDictionary.mongod
            StatusOK = "Responding"
            Required = $true
            Class = "Process"
            ParentName = "AlteryxService_MongoController"
            Component = "Controller"
        }

        $global:PlatformStatusColor = @{
            Stopping = "DarkYellow"
            Stopped = "DarkRed"
            Starting = "DarkYellow"
            Restarting = "DarkYellow"
            Running = "DarkGreen"
            Responding = "DarkGreen"
            Online = "DarkGreen"
            Offline = "DarkYellow"
            Degraded = "DarkRed"
        }      

    )

    $global:Location += @{
        RuntimeSettings = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
    }  

#endregion PLATFORM DEFINITIONS