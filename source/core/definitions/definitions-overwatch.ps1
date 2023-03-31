#region OVERWATCH DEFINITIONS

    $global:Overwatch = $global:Catalog.Overwatch.Overwatch

#endregion OVERWATCH DEFINITIONS
#region CONSTANTS

    $global:emptyString = [string]::Empty
    $global:epoch = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

#endregion CONSTANTS
#region EVENTS

    $global:PlatformEventStatusTarget=@{ Stop="Stopped"; Start="Running"; }
    $global:PlatformEventStatus=@{ InProgress="In Progress"; Completed="Completed"; Failed="Failed"; Reset="Reset"; Testing="Testing"; }

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
        Information="Information"
        Warning="Warning"
        Alert="Alert"
        AllClear="AllClear"
        UserNotification="UserNotification"
        Heartbeat="Heartbeat"
    }

    $global:PlatformMessageStatus = @{ 
        Disabled = "Disabled"
        Enabled = "Enabled"
        Throttled = "Throttled"
        Transmitted = "Transmitted"
    }

#endregion MESSAGES    
#region FILES

    $global:ContactsDB = "$($global:Location.Data)\contacts.csv"
    $global:InstallSettings = "$($global:Location.Install)\data\installSettings.ps1"

#endregion FILES  
#region OVERWATCH TOPOLOGY 

    # The following line indicates a post-installation configuration to the installer
    # Manual Configuration > Overwatch > Topology > Remote Controllers
    $global:OverwatchRemoteControllers = @()

#endregion OVERWATCH TOPOLOGY