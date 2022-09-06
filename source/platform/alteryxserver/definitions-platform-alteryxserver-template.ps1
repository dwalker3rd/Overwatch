#region PLATFORM DEFINITIONS

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

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
            StatusOK = $PlatformServiceUpState
            Required = $true
            Class = "Service"
        }
    )

    $global:PlatformProcessConfig = @(
        [PlatformCim]@{
            Name = "AlteryxService"
            DisplayName = $PlatformDictionary.AlteryxServiceProcess
            StatusOK = $PlatformProcessUpState
            Required = $true
            Class = "Process"
        },
        [PlatformCim]@{
            Name = "AlteryxServerHost"
            DisplayName = $PlatformDictionary.AlteryxServerHost
            StatusOK = $PlatformProcessUpState
            Required = $true
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Gallery"
        },
        [PlatformCim]@{
            Name = "AlteryxService_MongoController"
            DisplayName = $PlatformDictionary.AlteryxService_MongoController
            StatusOK = $PlatformProcessUpState
            Required = $true
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Database"
        },
        [PlatformCim]@{
            Name = "AlteryxEngineCmd"
            DisplayName = $PlatformDictionary.AlteryxEngineCmd
            StatusOK = $PlatformProcessUpState
            Required = $true
            Transient = $true
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Worker"
        },
        [PlatformCim]@{
            Name = "AlteryxService_MapRenderWorker"
            DisplayName = $PlatformDictionary.AlteryxService_MapRenderWorker
            StatusOK = $PlatformProcessUpState
            Required = $false
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Worker"
        },
        # [PlatformCim]@{
        #     Name = "AlteryxCEFRenderer"
        #     DisplayName = $PlatformDictionary.AlteryxCEFRenderer
        #     StatusOK = $PlatformProcessUpState
        #     Required = $false
        #     Class = "Process"
        #     ParentName = ???
        # },
        [PlatformCim]@{
            Name = "AlteryxAuthHost"
            DisplayName = $PlatformDictionary.AlteryxAuthHost
            StatusOK = $PlatformProcessUpState
            Required = $false
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Gallery"
        },
        [PlatformCim]@{
            Name = "AlteryxService_WebInterface"
            DisplayName = $PlatformDictionary.AlteryxService_WebInterface
            StatusOK = $PlatformProcessUpState
            Required = $false
            Class = "Process"
            ParentName = "AlteryxService"
            Component = "Gallery"
        },
        [PlatformCim]@{
            Name = "AlteryxMetrics"
            DisplayName = $PlatformDictionary.AlteryxMetrics
            StatusOK = $PlatformProcessUpState
            Required = $true
            Class = "Process"
            ParentName = @("AlteryxService","")
            Component = "Controller","Gallery", "Worker"
        },
        [PlatformCim]@{
            Name = "mongod"
            DisplayName = $PlatformDictionary.mongod
            StatusOK = $PlatformProcessUpState
            Required = $true
            Class = "Process"
            ParentName = "AlteryxService_MongoController"
            Component = "Controller"
        }

    )

#endregion PLATFORM DEFINITIONS