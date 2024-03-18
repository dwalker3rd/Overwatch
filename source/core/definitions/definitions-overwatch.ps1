#region OVERWATCH DEFINITIONS

$global:Overwatch = $global:Catalog.Overwatch.Overwatch

#endregion OVERWATCH DEFINITIONS
#region CONSTANTS

    $global:emptyString = [string]::Empty
    $global:epoch = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

#endregion CONSTANTS
#region STATUS

    $global:PlatformStatusBooleanColor = @{ $true = "DarkGreen"; $false = "DarkRed" }

    $global:PlatformStatusColor = @{}
    $global:PlatformStatusColor += @{
        Active = "DarkGreen"
        ActiveSyncing = "DarkGreen"
        Busy = "Green"
        Connected = "DarkGreen"
        Connecting = "DarkGreen"
        DecommisioningReadOnly = "DarkYellow"
        DecommisionedReadOnly = "DarkYellow"
        DecommissionFailedReadOnly = "DarkYellow"
        DecommissionedReadOnly = "DarkYellow"
        DecommissioningReadOnly = "DarkYellow"
        Degraded = "DarkRed"
        Disabled = "DarkRed"
        Disconnected = "DarkRed"
        Disconnecting = "DarkRed"
        Down = "DarkRed"
        Inactive = "DarkYellow"
        "InActive (IsNotOK)" = "DarkRed"
        "Inactive (IsOK)" = "DarkGray"        
        NotAvailable = "DarkYellow"
        Offline = "DarkGray"
        Online = "DarkGreen"
        Passive = "DarkGreen"
        Queued = "DarkGreen"
        ReadOnly = "DarkGreen"
        Ready = "DarkGreen"
        Responding = "DarkGreen"
        Restarting = "DarkYellow"
        Running = "DarkGreen"
        Shutdown = "DarkGray"
        Starting = "DarkYellow"
        StatusNotAvailable = "DarkYellow"
        StatusNotAvailableSyncing = "DarkYellow"
        StatusUnAvailable = "DarkYellow"
        Stopped = "DarkRed"
        Stopping = "DarkYellow"
        Unknown = "DarkGray"
        Unlicensed = "DarkRed"
    }    

#endregion STATUS
#region EVENTS

    $global:PlatformEventColor = @{ Stop = "DarkRed"; Start = "DarkGreen"; Reset = "DarkYellow" }
    $global:PlatformEventStatusTarget = @{ Stop = "Stopped"; Start = "Running"; }
    $global:PlatformEventStatus = @{ 
        InProgress = "In Progress" 
        "In Progress" = "In Progress" 
        Completed = "Completed" 
        Failed = "Failed" 
        Reset = "Reset" 
        Testing = "Testing" 
        Cancelled = "Cancelled"
        Created = "Created"
    }
    $global:PlatformEventStatusColor = @{ 
        InProgress = "DarkYellow" 
        "In Progress" = "DarkYellow" 
        Completed = "DarkGreen" 
        Failed = "DarkRed" 
        Reset = "DarkYellow" 
        Testing = "DarkYellow" 
        Cancelled = "DarkYeallow"
        Created = "DarkGreen"
    }

#endregion EVENTS
#region TASKS

    $global:PlatformTaskState = @{
        Ready = "Ready"
        Running = "Running"
        Queued = "Queued"
        Enabled = @("Ready","Running","Queued")
        Disabled = "Disabled"
        Started = @("Running","Queued")
        Stopped = @("Ready","Disabled")
        Unknown = "Unknown" 
    }

#endregion TASKS
#region MESSAGES

    $global:PlatformMessageType = @{ 
        Information = "Information"
        Warning = "Warning"
        Alert = "Alert"
        AllClear = "AllClear"
        UserNotification = "UserNotification"
        Heartbeat = "Heartbeat"
        Intervention = "Intervention"
    }

    $global:PlatformMessageTypeAlwaysSend = @{
        Intervention = "Intervention"
    }

    $global:PlatformMessageStatus = @{ 
        Disabled = "Disabled"
        Enabled = "Enabled"
        Throttled = "Throttled"
        Transmitted = "Transmitted"
    }

    $global:PlatformMessageDisabledTimeout = New-Timespan -Minutes 90

#endregion MESSAGES    
#region FILES

    $global:ContactsDB = "$($global:Location.Data)\contacts.csv"
    $global:InstallSettings = "$($global:Location.Install)\data\installSettings.ps1"

#endregion FILES  
#region OVERWATCH TOPOLOGY 

    $global:OverwatchControllers = @()
    $global:OverwatchControllers += $env:COMPUTERNAME.ToLower()
    $global:OverwatchRemoteControllers = @()
    # add overwatch remote controllers in platform instance definitions file

#endregion OVERWATCH TOPOLOGY
#region TRACE OVERWATCH CONTROLLERS

    $global:TestOverwatchControllers = $false

#endregion TRACE OVERWATCH CONTROLLERS
#region VAULTS

    $global:DefaultConnectionStringsVault = "connectionStrings"
    $global:DefaultCredentialsVault = "credentials"

#endregion VAULTS