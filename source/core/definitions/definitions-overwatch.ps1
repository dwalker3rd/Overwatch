#region OVERWATCH DEFINITIONS
    
$global:Overwatch = $global:Catalog.Overwatch

#region FILES

    $global:InstallSettingsFile = "$($global:Location.Install)\data\installSettings.ps1"
    $global:DefaultSettingsFile = "$($global:Location.Install)\data\defaultSettings.ps1"

    $global:SourceEnvironFile = "$($global:Location.Scripts)\source\environ\environ-template.ps1"
    $global:TempEnvironFile = "$($global:Location.Scripts)\temp\environ.ps1"
    $global:DestinationEnvironFile = "$($global:Location.Scripts)\environ.ps1"

    $global:ContactsDB = "$($global:Location.Data)\contacts.csv"

#endregion FILES
#region STATE

    #region OrderSensitive

        $global:PlatformServiceDownState = @('Stopped','StopPending','StartPending')
        $global:PlatformServiceUpState = @('Running')
        $global:PlatformServiceState = [array]$PlatformServiceDownState + [array]$PlatformServiceUpState

    #endregion OrderSensitive

    $global:PlatformProcessUpState = 'Responding'
    $global:PlatformTaskUpState = 'Ready','Enabled','Running'
    $global:PlatformTaskDownState = 'Disabled'

#endregion STATE    
#region EVENTS

    $global:PlatformEvent=@{ Stop='Stop'; Start='Start'; Restart='Restart'; Testing='Testing'; }
    $global:PlatformEventStatusTarget=@{ Stop='Stopped'; Start='Running'; }
    $global:PlatformEventStatus=@{ InProgress='In Progress'; Completed='Completed'; Failed='Failed'; Reset='Reset'; Testing='Testing'; }

#endregion EVENTS
#region MESSAGES

    $global:PlatformMessageType=@{ Information='Information'; Warning='Warning'; Alert='Alert'; AllClear='AllClear'; UserNotification='UserNotification'; Heartbeat='Heartbeat'; }

#endregion MESSAGES
#region CONSTANTS

    $global:emptyString = [string]::Empty
    $global:today = [datetime]::Today
    $global:yesterday = $global:today.AddDays(-1)

    $global:NumberWords = @{ 
        '1'='One'; '2'='Two'; '3'='Three'; '4'='Four'; '5'='Five'; '6'='Six'; '7'='Seven'; '8'='Eight'; '9'='Nine'; '10'='Ten'; 
        '11'='Eleven'; '12'='Twelve'; '13'='Thirteen'; '14'='Fourteen'; '15'='Fifteen'; '16'='Sixteen'; 
    }

#endregion CONSTANTS
#region CONSOLE SEQUENCES

    $global:consoleSequence = @{
        Default = "`e[0m"
        BoldBright = "`e[1m"
        NoBoldBright = "`e[22m"
        Underline = "`e[4m"
        NoUnderline = "`e[24m"
        Negative = "`e[7m"
        Positive = "`e[27m"
        ForegroundBlack = "`e[30m"
        ForegroundRed = "`e[31m"
        ForegroundGreen = "`e[32m"
        ForegroundYellow = "`e[33m"
        ForegroundBlue = "`e[34m"
        ForegroundMagenta = "`e[35m"
        ForegroundCyan = "`e[36m"
        ForegroundWhite = "`e[37m"
        ForegroundExtended = "`e[38m"
        ForegroundDefault = "`e[39m"
        BackgroundBlack = "`e[40m"
        BackgroundRed = "`e[41m"
        BackgroundGreen = "`e[42m"
        BackgroundYellow = "`e[43m"
        BackgroundBlue = "`e[44m"
        BackgroundMagenta = "`e[45m"
        BackgroundCyan = "`e[46m"
        BackgroundWhite = "`e[47m"
        BackgroundExtended = "`e[48m"
        BackgroundDefault = "`e[49m"
        BrightForegroundBlack = "`e[90m"
        BrightForegroundRed = "`e[91m"
        BrightForegroundGreen = "`e[92m"
        BrightForegroundYellow = "`e[93m"
        BrightForegroundBlue = "`e[94m"
        BrightForegroundMagenta = "`e[95m"
        BrightForegroundCyan = "`e[96m"
        BrightForegroundWhite = "`e[97m"
        BrightBackgroundBlack = "`e[100m"
        BrightBackgroundRed = "`e[101m"
        BrightBackgroundGreen = "`e[102m"
        BrightBackgroundYellow = "`e[103m"
        BrightBackgroundBlue = "`e[104m"
        BrightBackgroundMagenta = "`e[105m"
        BrightBackgroundCyan = "`e[106m"
        BrightBackgroundWhite = "`e[107m"
        ForegroundDarkGrey = "`e[38;2;128;128;128m"
    }
    $global:consoleSequence += @{
        BackgroundForegroundDefault = $global:consoleSequence.BackgroundDefault + $global:consoleSequence.ForegroundDefault
    }

#endregion CONSOLE SEQUENCES    

#endregion OVERWATCH DEFINITIONS        