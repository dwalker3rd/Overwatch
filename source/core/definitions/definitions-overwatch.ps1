#region OVERWATCH DEFINITIONS
    
    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    $global:Overwatch = 
        [Overwatch]@{
            Id = "Overwatch"
            Name = "Overwatch"
            Description = ""
            Version = "2.0"
        }
    $global:Overwatch.DisplayName = "$($global:Overwatch.Name) $($global:Overwatch.Version)"

    #region OrderSensitive

        $global:PlatformServiceDownState = @('Stopped','StopPending','StartPending')
        $global:PlatformServiceUpState = @('Running')
        $global:PlatformServiceState = [array]$PlatformServiceDownState + [array]$PlatformServiceUpState

    #endregion OrderSensitive

    $global:PlatformProcessUpState = 'Responding'
    $global:PlatformTaskUpState = 'Ready','Enabled','Running'
    $global:PlatformTaskDownState = 'Disabled'

    $global:PlatformEvent=@{ Stop='Stop'; Start='Start'; Restart='Restart'; Testing='Testing'; }
    $global:PlatformEventStatusTarget=@{ Stop='Stopped'; Start='Running'; }
    $global:PlatformEventStatus=@{ InProgress='In Progress'; Completed='Completed'; Failed='Failed'; Reset='Reset'; Testing='Testing'; }
    $global:PlatformMessageType=@{ Information='Information'; Warning='Warning'; Alert='Alert'; AllClear='AllClear'; UserNotification='UserNotification'; Heartbeat='Heartbeat'; }

    $global:ContactsDB = "$($global:Location.Data)\contacts.csv"

    $global:NumberWords = @{ 
        '1'='One'; '2'='Two'; '3'='Three'; '4'='Four'; '5'='Five'; '6'='Six'; '7'='Seven'; '8'='Eight'; '9'='Nine'; '10'='Ten'; 
        '11'='Eleven'; '12'='Twelve'; '13'='Thirteen'; '14'='Fourteen'; '15'='Fifteen'; '16'='Sixteen'; 
    }

    $global:emptyString = [string]::Empty
    $global:today = [datetime]::Today
    $global:yesterday = $global:today.AddDays(-1)

    $global:consoleSequence = @{
        Default = "`e[0m"
        ForegroundWhite = "`e[37m"
        ForegroundDefault = "`e[39m"
        ForegroundDarkGrey = "`e[38;2;128;128;128m"
        BackgroundDefault = "`e[49m"
        BrightForegroundRed = "`e[91m"
        BrightForegroundYellow = "`e[93m"
    }
    $global:consoleSequence += @{
        BackgroundForegroundDefault = $global:consoleSequence.BackgroundDefault + $global:consoleSequence.ForegroundDefault
    }

#endregion OVERWATCH DEFINITIONS        