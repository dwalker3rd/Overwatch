#region OVERWATCH DEFINITIONS

    $global:Overwatch = $global:Catalog.Overwatch

#endregion OVERWATCH DEFINITIONS
#region CONSTANTS

    $global:emptyString = [string]::Empty

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
        Throttled = $global:PlatformMessageStatus.Throttled
        Transmitted = $global:PlatformMessageStatus.Transmitted
    }

#endregion MESSAGES    
#region FILES

    $global:ContactsDB = "$($global:Location.Data)\contacts.csv"
    $global:InstallSettings = "$($global:Location.Install)\data\installSettings.ps1"

#enregion FILES   